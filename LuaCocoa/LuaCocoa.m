/*
 LuaCocoa
 Copyright (C) 2009-2010 PlayControl Software, LLC. 
 Eric Wing <ewing . public @ playcontrol.net>
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 
 */
 
//
//  LuaCocoa.m
//  LuaCocoa
//
//  Created by Eric Wing on 10/10/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "LuaCocoa.h"
#import "BridgeSupportController.h"
//#import <ffi/ffi.h>

#include <stdlib.h>
#include <stdbool.h>
#include <errno.h>

//#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/objc-auto.h>
// #import <objc/message.h>
#include <ffi/ffi.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h" // used by luaL_openlibs
#include "LuaCUtils.h"
#include "LuaStructBridge.h"
#import "LuaObjectBridge.h"

#import "ParseSupport.h"
#import "ParseSupportStruct.h"

#import "LuaFFISupport.h"

#import "NSStringHelperFunctions.h"
#import "LuaFunctionBridge.h"
#import "LuaSelectorBridge.h"
#import "LuaSubclassBridge.h"
#import "LuaBlockBridge.h"

#include "LuaCocoaWeakTable.h"
#include "LuaCocoaStrongTable.h"
#include "LuaFFIClosure.h"

#import "ParseSupportCache.h"
#import "LuaClassDefinitionMap.h"
#import "LuaCocoaAvailableLuaStates.h"

/*
// No lpeg.h, so I forward declare it here so I can use it.
extern int luaopen_lpeg (lua_State *L);
*/

//NSString* const kLuaCocoaErrorDomain = @"kLuaCocoaErrorDomain";



const char* LUACOCOA_CONTROLLER_POINTER = "LuaCocoa.ControllerPointer";
static NSString* LUACOCOA_BUNDLE_IDENTIFIER = @"net.PlayControl.LuaCocoa";

static void CreateGenerateFromXMLFunction(lua_State* lua_state);
static void GenerateFunctionFromXML(lua_State* lua_state, NSString* xml_string, NSString* function_name);
static void GenerateVariadicFunctionFromXML(lua_State* lua_state, NSString* xml_string, NSString* function_name);


static void LuaCocoa_StorePointerInGlobalRegistry(lua_State* lua_state, const char* key_name, void* the_pointer)
{
	int the_top = lua_gettop(lua_state);
	
	lua_pushstring(lua_state, key_name); // push key
	lua_pushlightuserdata(lua_state, the_pointer); // push value
	lua_settable(lua_state, LUA_REGISTRYINDEX);
	
	int new_top = lua_gettop(lua_state);
	assert(the_top == new_top);
}

// Does not leave result on stack. Don't pop.
static void* LuaCocoa_GetPointerInGlobalRegistry(lua_State* lua_state, const char* key_name)
{
	int the_top = lua_gettop(lua_state);
	
	lua_getfield(lua_state, LUA_REGISTRYINDEX, key_name);
	
	void* the_pointer = lua_touserdata(lua_state, -1);
	
	// For convenience, I pop the stack here so the stack remains balanced.
	// This works since this is just a user light data (pointer) and nothing should be garbage collected.
	lua_pop(lua_state, 1);
	
	int new_top = lua_gettop(lua_state);
	assert(the_top == new_top);
	return the_pointer;
}

// Modifies the package.path to prepend the specified string. Should be in proper lua format:
// e.g. /Users/ewing/Source/HG/LuaCocoa/Xcode/build/Debug/LuaCocoa.framework/Resources/?.lua
void LuaCocoa_PrependToLuaSearchPath(lua_State* lua_state, const char* search_path)
{
//	int top0 = lua_gettop(lua_state);
	
	// FIXME: Consider disabling for sandboxing
	// Get the old package.path
	lua_getglobal(lua_state, "package");
	lua_getfield(lua_state, -1, "path");
	//	NSLog(@"package.path is %s", lua_tostring(lua_state, -1));
	NSString* package_path = [NSString stringWithUTF8String:lua_tostring(lua_state, -1)];
	lua_pop(lua_state, 2); // pop the path string and the package table to get back to start position
//	int top1 = lua_gettop(lua_state);
//	assert(top0 == top1);
	
	
	NSString* new_package_path = [NSString stringWithFormat:@"%s;%@", search_path, package_path];
	//	NSString* new_package_path = [NSString stringWithUTF8String:search_path];
//	NSLog(@"new_package_path is %s", [[new_package_path stringByStandardizingPath] fileSystemRepresentation]);
	// Set the new package.path
	lua_getglobal(lua_state, "package");
	//	lua_pushstring(lua_state, "/Users/ewing/Source/HG/LuaCocoa/Xcode/build/Debug/LuaCocoa.framework/Versions/A/Resources/?.lua");
	lua_pushstring(lua_state, [[new_package_path stringByStandardizingPath] fileSystemRepresentation]);
	//	lua_pushstring(lua_state, [[new_package_path stringByStandardizingPath] UTF8String]);
	lua_setfield(lua_state, -2, "path");
	lua_pop(lua_state, 1); // pop the package table
//	int top2 = lua_gettop(lua_state);
//	assert(top1 == top2);
}


// Modifies the package.path to append the specified string. Should be in proper lua format:
// e.g. /Users/ewing/Source/HG/LuaCocoa/Xcode/build/Debug/LuaCocoa.framework/Resources/?.lua
void LuaCocoa_AppendToCSearchPath(lua_State* lua_state, const char* search_path)
{
//	int top0 = lua_gettop(lua_state);
	
	// FIXME: Consider disabling for sandboxing
	// Get the old package.path
	lua_getglobal(lua_state, "package");
	lua_getfield(lua_state, -1, "cpath");
//	NSLog(@"package.path is %s", lua_tostring(lua_state, -1));
	NSString* package_path = [NSString stringWithUTF8String:lua_tostring(lua_state, -1)];
	lua_pop(lua_state, 2); // pop the path string and the package table to get back to start position
//	int top1 = lua_gettop(lua_state);
//	assert(top0 == top1);
	
	
	NSString* new_package_path = [package_path stringByAppendingFormat:@";%s", search_path];
//	NSString* new_package_path = [NSString stringWithUTF8String:search_path];
//	NSLog(@"new_package_path is %s", [[new_package_path stringByStandardizingPath] fileSystemRepresentation]);
	// Set the new package.path
	lua_getglobal(lua_state, "package");
//	lua_pushstring(lua_state, "/Users/ewing/Source/HG/LuaCocoa/Xcode/build/Debug/LuaCocoa.framework/Versions/A/Resources/?.lua");
	lua_pushstring(lua_state, [[new_package_path stringByStandardizingPath] fileSystemRepresentation]);
//	lua_pushstring(lua_state, [[new_package_path stringByStandardizingPath] UTF8String]);
	lua_setfield(lua_state, -2, "cpath");
	lua_pop(lua_state, 1); // pop the package table
//	int top2 = lua_gettop(lua_state);
//	assert(top1 == top2);
}


// Modifies the package.path to prepend the specified string. Should be in proper lua format:
// e.g. /Users/ewing/Source/HG/LuaCocoa/Xcode/build/Debug/LuaCocoa.framework/Resources/?.lua
void LuaCocoa_PrependToCSearchPath(lua_State* lua_state, const char* search_path)
{
	//	int top0 = lua_gettop(lua_state);
	
	// FIXME: Consider disabling for sandboxing
	// Get the old package.path
	lua_getglobal(lua_state, "package");
	lua_getfield(lua_state, -1, "cpath");
	//	NSLog(@"package.path is %s", lua_tostring(lua_state, -1));
	NSString* package_path = [NSString stringWithUTF8String:lua_tostring(lua_state, -1)];
	lua_pop(lua_state, 2); // pop the path string and the package table to get back to start position
	//	int top1 = lua_gettop(lua_state);
	//	assert(top0 == top1);
	
	
	NSString* new_package_path = [NSString stringWithFormat:@"%s;%@", search_path, package_path];
	//	NSString* new_package_path = [NSString stringWithUTF8String:search_path];
	//	NSLog(@"new_package_path is %s", [[new_package_path stringByStandardizingPath] fileSystemRepresentation]);
	// Set the new package.path
	lua_getglobal(lua_state, "package");
	//	lua_pushstring(lua_state, "/Users/ewing/Source/HG/LuaCocoa/Xcode/build/Debug/LuaCocoa.framework/Versions/A/Resources/?.lua");
	lua_pushstring(lua_state, [[new_package_path stringByStandardizingPath] fileSystemRepresentation]);
	//	lua_pushstring(lua_state, [[new_package_path stringByStandardizingPath] UTF8String]);
	lua_setfield(lua_state, -2, "cpath");
	lua_pop(lua_state, 1); // pop the package table
	//	int top2 = lua_gettop(lua_state);
	//	assert(top1 == top2);
}


// Modifies the package.path to append the specified string. Should be in proper lua format:
// e.g. /Users/ewing/Source/HG/LuaCocoa/Xcode/build/Debug/LuaCocoa.framework/Resources/?.lua
void LuaCocoa_AppendToLuaSearchPath(lua_State* lua_state, const char* search_path)
{
	//	int top0 = lua_gettop(lua_state);
	
	// FIXME: Consider disabling for sandboxing
	// Get the old package.path
	lua_getglobal(lua_state, "package");
	lua_getfield(lua_state, -1, "path");
	//	NSLog(@"package.path is %s", lua_tostring(lua_state, -1));
	NSString* package_path = [NSString stringWithUTF8String:lua_tostring(lua_state, -1)];
	lua_pop(lua_state, 2); // pop the path string and the package table to get back to start position
	//	int top1 = lua_gettop(lua_state);
	//	assert(top0 == top1);
	
	
	NSString* new_package_path = [package_path stringByAppendingFormat:@";%s", search_path];
	//	NSString* new_package_path = [NSString stringWithUTF8String:search_path];
	//	NSLog(@"new_package_path is %s", [[new_package_path stringByStandardizingPath] fileSystemRepresentation]);
	// Set the new package.path
	lua_getglobal(lua_state, "package");
	//	lua_pushstring(lua_state, "/Users/ewing/Source/HG/LuaCocoa/Xcode/build/Debug/LuaCocoa.framework/Versions/A/Resources/?.lua");
	lua_pushstring(lua_state, [[new_package_path stringByStandardizingPath] fileSystemRepresentation]);
	//	lua_pushstring(lua_state, [[new_package_path stringByStandardizingPath] UTF8String]);
	lua_setfield(lua_state, -2, "path");
	lua_pop(lua_state, 1); // pop the package table
	//	int top2 = lua_gettop(lua_state);
	//	assert(top1 == top2);
}


static void LuaCocoa_RegisterConstants(lua_State* lua_state, NSXMLDocument* xml_document, NSString* dict_key, NSString* dict_value)
{
	// FIXME: Refactor into reusable function
#if __LP64__	
	NSString* type_encoding_string = [[[xml_document rootElement] attributeForName:@"type64"] stringValue];
	if(nil == type_encoding_string)
	{
		type_encoding_string = [[[xml_document rootElement] attributeForName:@"type"] stringValue];				
	}
#else
	NSString* type_encoding_string = [[[xml_document rootElement] attributeForName:@"type"] stringValue];
#endif	
	
	__strong const char* type_cstring = [type_encoding_string UTF8String];
	
	while(_C_CONST == *type_cstring)
	{
		type_cstring++;
	}
	void* const_symbol = dlsym(RTLD_DEFAULT, [dict_key UTF8String]);
	// FIXME: NSURLVolumeSupportsPersistentIDsKey is an example of a 10.6 only symbol which seems to return NULL when set to the 10.5 SDK.
	if(NULL == const_symbol)
	{
		NSLog(@"Symbol for constant %@ was NULL", dict_key);
		return;
	}
	// FIXME: Need to handle CoreFoundation objects
	switch(*type_cstring)
	{
		case _C_ID:
		{
			id the_value = *(id*)const_symbol;
			LuaObjectBridge_Pushid(lua_state, the_value);
			lua_setglobal(lua_state, [dict_key UTF8String]);
			break;
		}
		case _C_CLASS:
		{
			Class the_value = *(Class*)const_symbol;
			LuaObjectBridge_PushClass(lua_state, the_value);
			lua_setglobal(lua_state, [dict_key UTF8String]);
			break;
		}
		case _C_CHARPTR:
		{
			__strong const char* the_value = *(const char**)const_symbol;
			LuaCUtils_RegisterString(lua_state, the_value, [dict_key UTF8String], NULL);
			break;
		}
		case _C_BOOL:
		{
			bool the_value = *(bool*)const_symbol;
			LuaCUtils_RegisterBoolean(lua_state, the_value, [dict_key UTF8String], NULL);
			break;
		}
		case _C_CHR:
		case _C_UCHR:
		case _C_SHT:
		case _C_USHT:
		case _C_INT:
		case _C_UINT:
		case _C_LNG:
		case _C_ULNG:
		case _C_LNG_LNG:
		case _C_ULNG_LNG:
		{
			lua_Integer the_value = *(lua_Integer*)const_symbol;
			LuaCUtils_RegisterInteger(lua_state, the_value, [dict_key UTF8String], NULL);
			break;
		}
		case _C_FLT:
		case _C_DBL:
		{
			lua_Number the_value = *(lua_Number*)const_symbol;
			LuaCUtils_RegisterNumber(lua_state, the_value, [dict_key UTF8String], NULL);
			break;
		}
		case _C_PTR:
		{
			// Oops: I can be __CF or __CG. I think I need to track the CFType/tollfree bridge stuff and some how resolve the mapping.
			//					if([type_encoding_string hasPrefix:@"^{__CF"])
			if([type_encoding_string hasPrefix:@"^{__C"] && !ParseSupport_IsMagicCookie([xml_document rootElement]))
			{
				//				 NSLog(@"May have found a CFType: %@", type_encoding_string);
				// FIXME: Should cross check with database to verify this is a cftype that can bridge to nsobject
				// Pretend that this is a _C_ID object type.
				id the_value = *(id*)const_symbol;
				LuaObjectBridge_PushidWithRetainOption(lua_state, the_value, false);
				lua_setglobal(lua_state, [dict_key UTF8String]);
			}
			else
			{
				// Verified: Must use *(void**) and not const_symbol directly
				void* the_value = *(void**)const_symbol;
				//				NSLog(@"0x%x", kCFAllocatorUseContext);
				//				NSLog(@"0x%x", the_value);
				//				NSLog(@"0x%x", const_symbol);
				
				LuaCUtils_RegisterLightUserData(lua_state, the_value, [dict_key UTF8String], NULL);
			}
			break;				
		}
		case _C_STRUCT_B:
		{
			type_cstring++;
			__strong const char* start_ptr = type_cstring;
			while('=' != *type_cstring)
			{
				type_cstring++;				
			}
			NSString* struct_structname = [[[NSString alloc] initWithBytes:start_ptr length:type_cstring-start_ptr encoding:NSUTF8StringEncoding] autorelease];
			// Using NSString* struct_keyname = [ParseSupportStruct keyNameFromStructName:struct_structname];
			// may fail if the DependsOn doesn't include the proper framework.
			// For example, Foundation gives us:
			// <constant name='NSZeroPoint' declared_type='NSPoint' type64='{CGPoint=dd}' const='true' type='{_NSPoint=ff}'/>
			// The struct name is CGPoint in 64-bit, but Foundation forgets to include CoreGraphics as a DependsOn framework.
			// So calling the function won't work since we don't have a CGPoint defintion because we haven't loaded CoreGraphics.
			// So the work-around is to depend on the declared_type.
			// Update: Lion workaround: We no longer have declared_type to work with.
#if LUACOCOA_USE_FULL_BRIDGESUPPORT
			NSString* struct_keyname = [[[xml_document rootElement] attributeForName:@"declared_type"] stringValue];
#else
			// Stripping underscores is only necessary for 32-bit as far as I know.
			// I'm worried the lack of declared_type will pose problems for 64-bit mappings like NSPoint->CGPoint
			NSString* struct_keyname = NSStringHelperFunctions_StripLeadingUnderscores(struct_structname);
#endif			
			// Can't use sizeOfStructureFromStructureName because the struct may not be in the database yet.
			//			size_t struct_size = [ParseSupport sizeOfStructureFromStructureName:struct_name];
			NSArray* array_of_primitive_types = [ParseSupport typeEncodingsOfStructureFromFunctionTypeEncoding:type_encoding_string];
			size_t struct_size = [ParseSupport sizeOfStructureFromArrayOfPrimitiveObjcTypes:array_of_primitive_types];
			
			void* struct_ptr = lua_newuserdata(lua_state, struct_size);
			
			//			void* the_value = *(void**)const_symbol;
			memcpy(struct_ptr, const_symbol, struct_size);
			LuaStructBridge_SetStructMetatableOnUserdata(lua_state, -1, struct_keyname, struct_structname);
			lua_setglobal(lua_state, [dict_key UTF8String]);
			break;
		}
		default:
		{
			NSLog(@"Unhandled constant case for %@, type;%@", dict_key, type_encoding_string);
			break;			
		}
	}
	
}


static bool LuaCocoa_RegisterFunctions(lua_State* lua_state, NSXMLDocument* xml_document, NSString* dict_key, NSString* dict_value)
{
	//	NSLog(@"dict: %@, key: %@", dict_value, dict_key);
	if(nil == dict_value)
	{
		NSLog(@"bad data");
		return false;
	}
	
	/*
	 
	 key:NSBeep, value:<function name='NSBeep'/>
	 
	 key:NSBeginAlertSheet, value:<function name='NSBeginAlertSheet' variadic='true'>
	 <arg type='@'/>
	 <arg type='@'/>
	 <arg type='@'/>
	 <arg type='@'/>
	 <arg type='@'/>
	 <arg type='@'/>
	 <arg sel_of_type='v20@0:4@8i12^v16' type=':' sel_of_type64='v40@0:8@16q24^v32'/>
	 <arg sel_of_type='v20@0:4@8i12^v16' type=':' sel_of_type64='v36@0:8@16i24^v28'/>
	 <arg type='^v' type_modifier='n'/>
	 <arg printf_format='true' type='@' type_modifier='n'/>
	 </function>
	 
	 
	 2009-10-10 22:24:34.552 TestApp[33063:a0f] key:NSConvertHostDoubleToSwapped, value:<function name='NSConvertHostDoubleToSwapped' inline='true'>
	 <arg type='d'/>
	 
	 2009-10-10 22:24:34.767 TestApp[33063:a0f] key:NSLog, value:<function name='NSLog' variadic='true'>
	 <arg printf_format='true' type='@'/>
	 </function>
	 
	 2009-10-10 22:24:34.897 TestApp[33063:a0f] key:NSStringFromSelector, value:<function name='NSStringFromSelector'>
	 <arg type=':'/>
	 <retval type='@'/>
	 </function>
	 2009-10-10 22:24:34.918 TestApp[33063:a0f] key:NSSwapDouble, value:<function name='NSSwapDouble' inline='true'>
	 <arg type='{_NSSwappedDouble=Q}'/>
	 <retval type='{_NSSwappedDouble=Q}'/>
	 </function>
	 
	 2009-10-10 22:24:34.978 TestApp[33063:a0f] key:NSSwapShort, value:<function name='NSSwapShort' inline='true'>
	 <arg type='S'/>
	 <retval type='S'/>
	 </function>
	 2009-10-10 22:24:34.97
	 */ 
	
	
#if 1	
	// This is how to find a substring in Cocoa.
	// Switch to this if the Lua string library dependency (for string.match) becomes a problem for sandboxing.
	// (Currently, just having one central Lua function to handle either case is very convenient.)
	NSRange substring_range = [dict_value rangeOfString:@"variadic='true'"];
	if(NSNotFound != substring_range.location)
	{
		// Is variadic
		GenerateVariadicFunctionFromXML(lua_state, dict_value, dict_key);
		
	}
	else
	{
		// Not variadic
		GenerateFunctionFromXML(lua_state, dict_value, dict_key);
		
	}
#else
	GenerateFunctionFromXML(lua_state, dict_value, dict_key);
#endif
	
	
	return true;
}

static void LuaCocoa_RegisterClasses(lua_State* lua_state, NSXMLDocument* xml_document, NSString* dict_key, NSString* dict_value)
{
	/*
	 NSString* class_name = [[[xml_document rootElement] attributeForName:@"name"] stringValue];
	 NSLog(@"key=%@, class_name=%@, value=%@", dict_key, class_name, dict_value);
	 */
	// dict_key happens to also be the class name.
	LuaObjectBridge_CreateNewClassUserdata(lua_state, dict_key);
	
}

static bool LuaCocoa_RegisterEnums(lua_State* lua_state, NSXMLDocument* xml_document, NSString* dict_key, NSString* dict_value)
{
	NSXMLNode* enum_value = nil;
#if __LP64__
	enum_value = [[xml_document rootElement] attributeForName:@"value64"];
	if(nil == enum_value)
	{
		enum_value = [[xml_document rootElement] attributeForName:@"value"];
	}
#else
	enum_value = [[xml_document rootElement] attributeForName:@"value"];
#endif
	
	// Untested: Should also handle le_value and be_value for little/big endian differences.
	// (I haven't encountered any in Cocoa.)
	if(nil == enum_value)
	{
#if __BIG_ENDIAN__
		enum_value = [[xml_document rootElement] attributeForName:@"be_value"];
#else
		enum_value = [[xml_document rootElement] attributeForName:@"le_value"];
#endif
		if(enum_value)
		{
			NSLog(@"found be/le_value enum key: %@, value: %@", dict_key, dict_value);					
		}
	}
	
	// This case is triggered for:
	// key: kCGDirectMainDisplay, value: <enum name='kCGDirectMainDisplay' suggestion='Call CGMainDisplayID.' ignore='true'/>
	if(nil == enum_value)
	{
		//				NSLog(@"Could not find value for enum key: %@, value: %@\n", dict_key, dict_value);
		return false;
	}
	
	// Note: I caught a bug (7293683) with
	/*
	 key:NSMaxXEdge, value:<enum name='NSMaxXEdge' value64='2'/>
	 key:NSMaxYEdge, value:<enum name='NSMaxYEdge' value64='3'/>
	 key:NSMinXEdge, value:<enum name='NSMinXEdge' value64='0'/>
	 key:NSMinYEdge, value:<enum name='NSMinYEdge' value64='1'/>
	 These should only exist in 32-bit, not 64-bit.	
	 */
	
	// "enum" can also mean #define which can be a floating point number.
	// e.g. NSAppKitVersionNumber10_5_3 is 949.33000000000004
	// This means I need to be careful about number precision.
	
	NSString* enum_string = [enum_value stringValue];
	if(NSStringHelperFunctions_HasSinglePeriod(enum_string))
	{
		// assuming floating point
		lua_Number retrieved_value = [enum_string doubleValue];		
		//		lua_Number retrieved_value = strtold([[enum_value stringValue] UTF8String], NULL);		
		LuaCUtils_RegisterNumber(lua_state, retrieved_value, [dict_key UTF8String], NULL);
	}
	else
	{
		// assuming integer
		lua_Integer retrieved_value = [enum_string integerValue];
		LuaCUtils_RegisterInteger(lua_state, retrieved_value, [dict_key UTF8String], NULL);
	}
	
	return true;
	
}

// Seems that NSStrings hit the constants sections, but I'm getting CFSTR("") here.
// <string_constant name='kSCNetworkConnectionBytesIn' nsstring='true' value='BytesIn'/>
// I think the way this works is that the "value" is the actual value of the string and name is the variable name.
// If nsstring is true, I should treat it as an object, otherwise a C-string.
// This is somewhat easier than the constants because I have the actual string value in the XML instead of needing dlsym
// to look up the symbol.
static bool LuaCocoa_RegisterStringConstants(lua_State* lua_state, NSXMLDocument* xml_document, NSString* dict_key, NSString* dict_value)
{
	NSXMLNode* string_value = nil;
#if __LP64__
	string_value = [[xml_document rootElement] attributeForName:@"value64"];
	if(nil == string_value)
	{
		string_value = [[xml_document rootElement] attributeForName:@"value"];
	}
#else
	string_value = [[xml_document rootElement] attributeForName:@"value"];
#endif
	
	NSXMLNode* is_nsstring_value = [[xml_document rootElement] attributeForName:@"nsstring"];
	bool is_nsstring = false;
	if([[is_nsstring_value stringValue] isEqualToString:@"true"])
	{
		is_nsstring = true;
	}
	
	if(true == is_nsstring)
	{
		LuaObjectBridge_Pushid(lua_state, [string_value stringValue]);
		lua_setglobal(lua_state, [dict_key UTF8String]);		
	}
	else
	{
		LuaCUtils_RegisterString(lua_state, [[string_value stringValue] UTF8String], [dict_key UTF8String], NULL);
	}
	
	return true;
	
}

static void LuaCocoa_RegisterItemForKeyWithXMLFragment(lua_State* lua_state, NSString* dict_key, NSString* xml_fragment)
{
	NSError* the_error = nil;
	NSString* item_type = nil;
	NSXMLDocument* xml_document = [[NSXMLDocument alloc] initWithXMLString:xml_fragment options:0 error:&the_error];
	if(nil != the_error)
	{
		NSLog(@"registerItemsInXmlHash: malformed xml while getting key: %@, value: %@, error is: %@", dict_key, xml_fragment, the_error);
		[xml_document release];
		return;
	}
	
	item_type = [[xml_document rootElement] name];
	//		NSLog(@"key:%@, item_type:%@", dict_key, item_type);
	if([dict_key isEqualToString:@"depends_on"])
	{
		NSLog(@"Depends on path: %@", xml_fragment);
		
		
	}
	
	// Function
	
	if([item_type isEqualToString:@"function"])
	{
		LuaCocoa_RegisterFunctions(lua_state, xml_document, dict_key, xml_fragment);
	}
	
	// Struct
	else if([item_type isEqualToString:@"struct"])
	{
		// TODO: Provide function to create struct? Or provide userdata with constructor methods?
		//			[self registerStructs:xml_document dictKey:dict_key dictValue:dict_value];
		LuaStructBridge_GenerateAliasStructConstructor(lua_state, dict_key);
	}
	
	// Constant
	else if([item_type isEqualToString:@"constant"])
	{
		// meIntervalSince1970, value:<constant name='kCFAbsoluteTimeIntervalSince1970' type='d'/>
		// <constant name='kCFAllocatorUseContext' magic_cookie='true' type='^{__CFAllocator=}'/>
		//2009-10-10 22:24:27.910 TestApp[33063:a0f] key:kCFAllocatorDefault, value:<constant name='kCFAllocatorDefault' type='^{__CFAllocator=}'/>
		//2009-10-10 22:24:27.911 TestApp[33063:a0f] key:kCFAllocatorMalloc, value:<constant name='kCFAllocatorMalloc' type='^{__CFAllocator=}'/>
		// <constant name='kCFBooleanFalse' type='^{__CFBoolean=}'/>
		// <constant name='kCFBooleanTrue' type='^{__CFBoolean=}'/>
		// <constant name='kCFBundleVersionKey' type='^{__CFString=}'/>
		// <constant name='NSDeallocateZombies' type='B'/>
		// <constant name='NSDebugEnabled' type='B'/>
		// 
		/*
		 2009-10-10 22:24:32.106 TestApp[33063:a0f] key:NSIntHashCallBacks, value:<constant name='NSIntHashCallBacks' type='{_NSHashTableCallBacks=^?^?^?^?^?}'/>
		 2009-10-10 22:24:32.106 TestApp[33063:a0f] key:NSIntMapKeyCallBacks, value:<constant name='NSIntMapKeyCallBacks' type='{_NSMapTableKeyCallBacks=^?^?^?^?^?^v}'/>
		 
		 2009-10-10 22:24:32.557 TestApp[33063:a0f] key:NSYearMonthWeekDesignations, value:<constant name='NSYearMonthWeekDesignations' type='@'/>
		 2009-10-10 22:24:32.558 TestApp[33063:a0f] key:NSZeroPoint, value:<constant name='NSZeroPoint' type64='{CGPoint=dd}' type='{_NSPoint=ff}'/>
		 2009-10-10 22:24:32.558 TestApp[33063:a0f] key:NSZeroRect, value:<constant name='NSZeroRect' type64='{CGRect={CGPoint=dd}{CGSize=dd}}' type='{_NSRect={_NSPoint=ff}{_NSSize=ff}}'/>
		 2009-10-10 22:24:32.558 TestApp[33063:a0f] key:NSZeroSize, value:<constant name='NSZeroSize' type64='{CGSize=dd}' type='{_NSSize=ff}'/>
		 2009-10-10 22:24:32.559 TestApp[33063:a0f] key:NSZombieEnabled, value:<constant name='NSZombieEnabled' type='B'/>
		 
		 2009-10-10 22:24:31.806 TestApp[33063:a0f] key:NSCocoaErrorDomain, value:<constant name='NSCocoaErrorDomain' type='@'/>
		 
		 2009-10-10 22:24:24.075 TestApp[33063:a0f] key:NSWhite, value:<constant name='NSWhite' type64='d' type='f'/>
		 
		 */
		
		LuaCocoa_RegisterConstants(lua_state, xml_document, dict_key, xml_fragment);
		
	}
	
	// Enum
	else if([item_type isEqualToString:@"enum"])
	{
		LuaCocoa_RegisterEnums(lua_state, xml_document, dict_key, xml_fragment);
	}
	else if([item_type isEqualToString:@"class"])
	{
		LuaCocoa_RegisterClasses(lua_state, xml_document, dict_key, xml_fragment);
	}
	else if([item_type isEqualToString:@"string_constant"])
	{
		//			NSLog(@"found string_constant: %@", dict_key);
		LuaCocoa_RegisterStringConstants(lua_state, xml_document, dict_key, xml_fragment);
	}
	else if([item_type isEqualToString:@"function_alias"])
	{
		NSLog(@"found function_alias: %@", dict_key);
		
	}
	else if([item_type isEqualToString:@"cftype"])
	{
		//		NSLog(@"found cftype: %@", dict_key);
		//			<cftype name='CGColorRef' gettypeid_func='CGColorGetTypeID' type='^{CGColor=}' tollfree='__NSCFType'/>
		// I'm not sure if I really need to do anything for this case, and if so, what that might be.
		// It seems there might be two subcases, tollfree bridged to NSObject and not bridged.
		// In the bridged case, I'm not sure if I need to do anything. As Obj-C objects, they can be
		// treated as NSObjects and I don't know if the type information is important since on the Lua side,
		// everything is loosely typed.
		// As C-objects, they are only created through C functions so there aren't any operations I can think
		// of that require a type except for casting, which again doesn't seem relevant in a loosely typed language.
		// So I guess for now, I don't have to implement anything for this case.
		
		
		// Update: I'm wrong about needing to track this. I need to use this information to decide whether I push a raw pointer or push a LuaCocoa object userdata wrapper around Core Foundation objects.
		// CGEventSourceCreate for key stroke generation broke me.
		// Note that this is CG and not CF so checking for CF isn't sufficient.
	}
	
	else
	{
		NSLog(@"unhandled item_type:%@", item_type);
		
	}
	[xml_document release];
}


// LuaCocoa.import("CoreFoundation")
// stack position 1: Framework name to load (do not include .framework extension)
// stack position 2 (optional): search hint path
// TODO: Add optional arguments to supply search order, etc?
// TODO: Support NSString userdata?
static int LuaCocoa_Import(lua_State* lua_state)
{
	int number_of_arguments = lua_gettop(lua_state);
	if(number_of_arguments < 1)
	{
		return luaL_error(lua_state, "LuaCocoa.import requires at least one argument containing a framework name to load");
	}
	// Don't need to pop the stack using this function.
	void* the_pointer = LuaCocoa_GetPointerInGlobalRegistry(lua_state, LUACOCOA_CONTROLLER_POINTER);

	LuaCocoa* lua_controller = (LuaCocoa*)the_pointer;

	// Considering sandboxing
	if(true == lua_controller.disableImportFromLua)
	{
		return 0;
	}
	
	NSString* framework_base_name = [NSString stringWithUTF8String:luaL_checkstring(lua_state, 1)];
	NSString* hint_path = nil;
	if(number_of_arguments >= 2)
	{
		hint_path = [NSString stringWithUTF8String:luaL_checkstring(lua_state, 2)];
	}
	bool ret_flag = [lua_controller loadFrameworkWithBaseName:framework_base_name hintPath:hint_path searchHintPathFirst:nil skipDLopen:lua_controller.skipDLopen];

	// TODO: Consider making semantics more like Lua require?
	lua_pushboolean(lua_state, ret_flag);
	return 1;
}

// Provides easy access to the lua_State pointer on the lua side.
// Might be useful when dealing with Obj-C methods that explicitly want the lua_State.
static int LuaCocoa_GetLuaState(lua_State* lua_state)
{
	lua_pushlightuserdata(lua_state, lua_state);
	return 1;
}

/*
typedef struct BridgeSupportExtraData
{
	char itemName[256];
	char returnValueObjcEncodingType;
	NSUInteger numberOfArguments;
	char argumentObjcEncodingTypes[];
} BridgeSupportExtraData;
*/

// NSObject = LuaCocoa.resolveName(table, "NSObject")
// stack position 1: keyname to look up
// stack position 1: keyname to look up
static int LuaCocoa_ResolveName(lua_State* lua_state)
{
/*
	int number_of_arguments = lua_gettop(lua_state);
	if(number_of_arguments != 1)
	{
		return luaL_error(lua_state, "LuaCocoa.resolveName requires one argument containing the key name to lookup/load");
	}
*/
	const char* the_name = lua_tostring(lua_state, 2);
	
	if(NULL == the_name)
	{
		return 0;
	}
	
	NSString* dict_key = [NSString stringWithUTF8String:the_name];
	
/*	
	// Don't need to pop the stack using this function.
	void* the_pointer = LuaCocoa_GetPointerInGlobalRegistry(lua_state, LUACOCOA_CONTROLLER_POINTER);
	
	LuaCocoa* lua_controller = (LuaCocoa*)the_pointer;
*/	
	NSDictionary* xml_hash = [[BridgeSupportController sharedController] masterXmlHash];
	NSString* dict_value = [xml_hash objectForKey:dict_key];
	if(nil == dict_value)
	{
#if ! LUACOCOA_USE_FULL_BRIDGESUPPORT
		// Lion workaround:
		// If not using Full bridgesupport files, common class names like NSMutableDictionary may not appear.
		// To handle this case, we should try to do a dynamic runtime check.
		Class the_class = NSClassFromString(dict_key);
		if(nil == the_class)
		{
			return 0;
		}
		else
		{
			LuaObjectBridge_CreateNewClassUserdata(lua_state, dict_key);			
		}
#endif
	}
	else
	{
		// Note: In the non-full bridge support case for classes, dict_value is nil, so we need to be careful.	
		LuaCocoa_RegisterItemForKeyWithXMLFragment(lua_state, dict_key, dict_value);
	}
	
	// Optimization Point: The item was cleared from the stack when we registered it.
	// We could change things so the item is not popped so we don't have to re-push it.

	// Don't use lua_getglobal because we want to avoid metamethod access.
	//	lua_getglobal(lua_state, the_name);

	lua_pushstring(lua_state, the_name);
	lua_rawget(lua_state, LUA_GLOBALSINDEX);

	return 1;
}

static int Internal_toLua(lua_State* lua_state)
{
	id ret_val = LuaCocoa_ToInstance(lua_state, 1);
	LuaCocoa_PushUnboxedPropertyList(lua_state, ret_val);
	return 1;
}

static int Internal_toCocoa(lua_State* lua_state)
{
	id ret_val = LuaCocoa_ToPropertyList(lua_state, 1);
	if(nil == ret_val)
	{
		lua_pushnil(lua_state);
	}
	else
	{
		LuaCocoa_PushInstance(lua_state, ret_val);
	}
	return 1;
}

const luaL_reg lua_LuaCocoa_functions[] = 
{
//	{"ffi_prep_cif", lua_ffi_prep_cif},
//	{"ffi_call", lua_ffi_call},
	{"import", LuaCocoa_Import},
	{"luaState", LuaCocoa_GetLuaState},
	{"resolveName", LuaCocoa_ResolveName},

	{"toLua", Internal_toLua},
	{"toCocoa", Internal_toCocoa},

	{NULL,NULL},
};

int luaopen_LuaCocoa(lua_State* state)
{
//	luaL_newmetatable(state, LUACOCOA_FFI_CIF);
	//	lua_pushvalue(state, -1);
	//	lua_setfield(state, -2, "__index");
	//	luaL_register(state, NULL, methods_for_cgpoint);

//	luaL_newmetatable(state, LUACOCOA_BRIDGESUPPORT_EXTRA_DATA);
//	luaL_register(state, NULL, methods_for_BridgeSupportExtraData);

    luaL_register(state, "LuaCocoa", lua_LuaCocoa_functions);
	return 1;
}

static const char* GenerateFunctionFromXML_code = 
"function LuaCocoa.GenerateFunctionFromXML(xml_string)\n" 
"	local cif, bridge_support_extra_data = LuaCocoa.ffi_prep_cif(xml_string)\n" 
"	local return_function = function(...)\n" 
"		return LuaCocoa.ffi_call(cif, bridge_support_extra_data, ...)\n" 
"	end\n" 
"	return return_function\n" 
"end\n";

// Because libffi doesn't seem to directly support variadic functions,
// we cannot call ffi_prep_cif until on-demand when we know exactly how many 
// arguments we are dealing with.
// So this variation of Generate defers calling ffi_prep_cif until demand, whereas
// the main version calls/caches prep ahead of time to allow faster calling performance.
static const char* GenerateVariadicFunctionFromXML_code = 
"function LuaCocoa.GenerateVariadicFunctionFromXML(xml_string)\n" 
"	local return_function = function(...)\n"
"		local cif, bridge_support_extra_data = LuaCocoa.ffi_prep_cif(xml_string, ...)\n" 
"		return LuaCocoa.ffi_call(cif, bridge_support_extra_data, ...)\n" 
"	end\n" 
"	return return_function\n" 
"end\n";

/*
// Combined version of the above two because string.match is easier to do in Lua than Cocoa.
static const char* GenerateFunctionFromXML_code = 
"function LuaCocoa.GenerateFunctionFromXML(xml_string)\n" 
"	if string.match(xml_string, \"variadic='true'\") then\n"
"		local return_function = function(...)\n"
"			local cif, bridge_support_extra_data = LuaCocoa.ffi_prep_cif(xml_string, ...)\n" 
"			return LuaCocoa.ffi_call(cif, bridge_support_extra_data, ...)\n" 
"		end\n" 
"		return return_function\n" 
"	else\n"
"		local cif, bridge_support_extra_data = LuaCocoa.ffi_prep_cif(xml_string)\n" 
"		local return_function = function(...)\n" 
"			return LuaCocoa.ffi_call(cif, bridge_support_extra_data, ...)\n" 
"		end\n" 
"		return return_function\n" 
"	end\n"
"end\n";
*/

// TODO: Is it really worth writing the Lua-C-API-equivalent of the above Lua function?
// Any volunteers?
static void CreateGenerateFromXMLFunction(lua_State* lua_state)
{
	luaL_loadstring(lua_state, GenerateFunctionFromXML_code);
	lua_call(lua_state, 0, 0);
	
	luaL_loadstring(lua_state, GenerateVariadicFunctionFromXML_code);
	lua_call(lua_state, 0, 0);
}

/* Essentially, this function uses the generic ffi function creator (GenerateFunctionFromXML_code)
 * to register a function with its proper user-friendly name in Lua.
 * e.g.
 * NSSwapShort = LuaCocoa.GenerateFunctionFromXML("<function name='NSSwapShort' inline='true'> <arg type='S'/> <retval type='S'/> </function>")
 *
 * I'm not sure if this differs from other bridges where function mapping is deferred until use.
 * But for Lua, this seemed to make some sense as it allows all the functions to be inspected dynamically
 * through the global table.
 * I could have opted to do a deferred system, but I think this would have required a metatable 
 * in the global table (since I currently add functions there). Since people like to add their own
 * metatables for their own uses, I wanted to avoid polluting the space.
 *
 * This function could be enhanced to put functions in namespaces, but looking at other bridges,
 * it doesn't seem to be done too often.
 * (And who really wants to type CoreFoundation.CFCreateBlah() all the time?)
 */
static void GenerateFunctionFromXML(lua_State* lua_state, NSString* xml_string, NSString* function_name)
{
#if 1
	/* NSBeep = LuaCocoa.GenerateFunction("<function name='NSBeep'/>") */
	int top0 = lua_gettop(lua_state);
	lua_getfield(lua_state, LUA_GLOBALSINDEX,"LuaCocoa");
	lua_pushliteral(lua_state, "GenerateFunctionFromXML");
	lua_gettable(lua_state, -2);
	lua_remove(lua_state, -2);
	lua_pushstring(lua_state, [xml_string UTF8String]);
	lua_call(lua_state, 1,1);
	lua_setfield(lua_state, LUA_GLOBALSINDEX, [function_name UTF8String]);
//	assert(lua_gettop(lua_state) - lc_nextra == 0);
	int top1 = lua_gettop(lua_state);
	assert(top1==top0);
#else
//	NSString* code_string = [[NSString alloc] initWithFormat:@"%@ = LuaCocoa.GenerateFunctionFromXML(\"%@\")", function_name, xml_string];
	NSString* code_string = [[NSString alloc] initWithFormat:@"local xml_string = [[%@]]; %@ = LuaCocoa.GenerateFunctionFromXML(xml_string)", xml_string, function_name];
//	NSLog(@"code_string: %@", code_string);
/*
	if([@"NSSwapShort" isEqualToString:function_name])
	{
		NSLog(@"code_string: %@", code_string);
		[code_string autorelease];
//		code_string = [[NSString alloc] initWithFormat:@"%@ = LuaCocoa.GenerateFunctionFromXML(\"%@\")\nprint('NSSwapShort func', NSSwapShort)\nNSSwapShort(12345)", function_name, xml_string];
		code_string = [[NSString alloc] initWithFormat:@"local xml_string = [[%@]]; %@ = LuaCocoa.GenerateFunctionFromXML(xml_string)\nprint('NSSwapShort func', NSSwapShort)\nNSSwapShort(12345)", xml_string, function_name];
	}
*/
	luaL_loadstring(lua_state, [code_string UTF8String]);
	lua_call(lua_state, 0, 0);
//	luaL_dostring(lua_state, [code_string UTF8String]);
/*
	if(lua_isfunction(lua_state, -1))
	{
//		NSLog(@"function at top");
	}
	else
	{
		NSLog(@"function not at top: %s", lua_tostring(lua_state, -1));
	}
*/
	[code_string release];
#endif
}

static void GenerateVariadicFunctionFromXML(lua_State* lua_state, NSString* xml_string, NSString* function_name)
{
	/* NSBeep = LuaCocoa.GenerateFunction("<function name='NSBeep'/>") */
	lua_getfield(lua_state, LUA_GLOBALSINDEX,"LuaCocoa");
	lua_pushliteral(lua_state, "GenerateVariadicFunctionFromXML");
	lua_gettable(lua_state, -2);
	lua_remove(lua_state, -2);
	lua_pushstring(lua_state, [xml_string UTF8String]);
	lua_call(lua_state, 1,1);
	lua_setfield(lua_state, LUA_GLOBALSINDEX, [function_name UTF8String]);
	//	assert(lua_gettop(lua_state) - lc_nextra == 0);
}

#if ! LUACOCOA_REGISTER_ITEMS_IMMEDIATELY
static const char* s_ResolveNameMetaTable = 
"setmetatable(_G, { __index = LuaCocoa.resolveName })";
#endif

// Used for finalizer/threading issues
@interface LuaCocoaDataForCleanup : NSObject
{
	lua_State* luaState;
	bool ownsState;
}
@property(nonatomic, assign, readonly) lua_State* luaState;
@property(nonatomic, assign, readonly) bool ownsState;

- (id) initWithLuaState:(lua_State*)lua_state ownsState:(bool)owns_state;
@end

@implementation LuaCocoaDataForCleanup

@synthesize luaState;
@synthesize ownsState;

- (id) initWithLuaState:(lua_State*)lua_state ownsState:(bool)owns_state
{
	self = [super init];
	if(nil != self)
	{
		luaState = lua_state;
		ownsState = owns_state;
	}
	return self;
}

@end

@interface LuaCocoa ()
- (void) commonInit;

- (void) registerItemsForFramework:(NSString*)base_name;

- (void) registerItemsInXmlHash:(NSDictionary*)xml_hash;

- (void) registerAllItems;
@end

@implementation LuaCocoa

@synthesize luaState;
@synthesize skipDLopen;
@synthesize disableImportFromLua;
/*
@synthesize luaErrorFunction;
@synthesize errorDelegate;
*/
// assumes you already loaded the luaState
- (void) commonInit
{
	frameworksLoaded = [[NSMutableDictionary alloc] init];

	// Need to CFRetain because I need this alive in finalize so I can invoke non-thread-safe stuff
	originThread = [NSThread currentThread];
	CFRetain(originThread);
	
	// Keep track of Lua states that are available.
	// This is intended to guard against asynchronous block callbacks from invoking dead Lua states.
	// This may have other uses. (Subclass bridge has a different mechanism for tracking.)
	[[LuaCocoaAvailableLuaStates sharedAvailableLuaStates] addLuaState:luaState];

	lua_gc(luaState, LUA_GCSTOP, 0);  /* stop collector during initialization */

	// FIXME: Consider explicit opt-in for sandboxing
	luaL_openlibs(luaState);

	// Add bundle paths to package.path.
	// FIXME: May want to put these in front of search path instead of at the end so users
	// with alternative installations won't pull in unexpected versions if versions differ.
	
	NSString* main_bundle_plugins_path = [[NSBundle mainBundle] builtInPlugInsPath];
	main_bundle_plugins_path = [main_bundle_plugins_path stringByAppendingPathComponent:@"/?.so"];
	
	LuaCocoa_PrependToCSearchPath(luaState, [main_bundle_plugins_path UTF8String]);
	
	
	// Also, add the application (main bundle) to the search path.
	// Put this before LuaCocoa bundle path so it can override.
	// Note: This might be garbage if the main bundle is a framework
	NSString* main_bundle_resource_path = [[NSBundle mainBundle] resourcePath];
	main_bundle_resource_path = [main_bundle_resource_path stringByAppendingFormat:@"/?.lua;%@/?/init.lua", main_bundle_resource_path];
	
	LuaCocoa_PrependToLuaSearchPath(luaState, [main_bundle_resource_path UTF8String]);

	
	
	NSBundle* lua_cocoa_bundle = [NSBundle bundleWithIdentifier:LUACOCOA_BUNDLE_IDENTIFIER];
	
	NSString* lua_cocoa_bundle_plugins_path = [lua_cocoa_bundle builtInPlugInsPath];
	lua_cocoa_bundle_plugins_path = [lua_cocoa_bundle_plugins_path stringByAppendingPathComponent:@"/?.so"];
	//NSLog(@"lua_cocoa_bundle_resource_path: %@", lua_cocoa_bundle_resource_path);
	// This must be called after package.path has been created; i.e. call after loading whichever standard lua library provides it
	// I call UTF8String here instead of fileSystemRepresentation because the function internally calls the latter
	// and doing so here seems to do something to break something so the path is not found.
	LuaCocoa_PrependToCSearchPath(luaState, [lua_cocoa_bundle_plugins_path UTF8String]);

	
	NSString* lua_cocoa_bundle_resource_path = [lua_cocoa_bundle resourcePath];
	lua_cocoa_bundle_resource_path = [lua_cocoa_bundle_resource_path stringByAppendingFormat:@"/?.lua;%@/?/init.lua", lua_cocoa_bundle_resource_path];
//NSLog(@"lua_cocoa_bundle_resource_path: %@", lua_cocoa_bundle_resource_path);
	// This must be called after package.path has been created; i.e. call after loading whichever standard lua library provides it
	// I call UTF8String here instead of fileSystemRepresentation because the function internally calls the latter
	// and doing so here seems to do something to break something so the path is not found.
	LuaCocoa_PrependToLuaSearchPath(luaState, [lua_cocoa_bundle_resource_path UTF8String]);
	


/*	
	// Open LPeg (which we need for Objective Lua)
	lua_pushcfunction(luaState, luaopen_lpeg);
	lua_pushstring(luaState, "lpeg");
	lua_call(luaState, 1, 0);
*/	
	
	// Create global weak table for objects
	// Must do this before opening the LuaCocoa related libraries
	LuaCocoaWeakTable_CreateGlobalWeakObjectTable(luaState);
	LuaCocoaStrongTable_CreateGlobalStrongObjectTable(luaState);

	
	lua_pushcfunction(luaState, luaopen_LuaCocoa);
	lua_pushstring(luaState, "LuaCocoa");
	lua_call(luaState, 1, 0);
	
	lua_pushcfunction(luaState, luaopen_LuaFunctionBridge);
	lua_pushstring(luaState, "LuaCocoa");
	lua_call(luaState, 1, 0);
	
	// Not actually public at the moment, but I want to create the user data metatable for private use in Objects
	lua_pushcfunction(luaState, luaopen_LuaFFIClosure);
	lua_pushstring(luaState, "LuaCocoa");
	lua_call(luaState, 1, 0);
	
	lua_pushcfunction(luaState, luaopen_LuaObjectBridge);
	lua_pushstring(luaState, "LuaCocoa");
	lua_call(luaState, 1, 0);
	
	lua_pushcfunction(luaState, luaopen_LuaStructBridge);
	lua_pushstring(luaState, "LuaCocoa");
	lua_call(luaState, 1, 0);
	
	lua_pushcfunction(luaState, luaopen_LuaSelectorBridge);
	lua_pushstring(luaState, "LuaCocoa");
	lua_call(luaState, 1, 0);
	
	lua_pushcfunction(luaState, luaopen_LuaSubclassBridge);
	lua_pushstring(luaState, "LuaCocoa");
	lua_call(luaState, 1, 0);
	
	lua_pushcfunction(luaState, luaopen_LuaBlockBridge);
	lua_pushstring(luaState, "LuaCocoa");
	lua_call(luaState, 1, 0);
	
	
	
	CreateGenerateFromXMLFunction(luaState);
	
	
	LuaCocoa_StorePointerInGlobalRegistry(luaState, LUACOCOA_CONTROLLER_POINTER, self);
	
#if ! LUACOCOA_REGISTER_ITEMS_IMMEDIATELY
	// Instead of registering all items immediately, we can do lazy resolving.
	// The technique I will rely on is to set a metamethod on _G to handle the look up.
	// This has the drawback that if somebody needs/changes the _G metamethod, things will break for them.
	luaL_loadstring(luaState, s_ResolveNameMetaTable);
	lua_call(luaState, 0, 0);
#endif
	
	lua_gc(luaState, LUA_GCRESTART, 0);

}

- (id) init
{
	self = [super init];
	if(nil != self)
	{
		
		luaState = luaL_newstate();
		ownsLuaState = true;
		[self commonInit];
				
//		[self loadFrameworkWithBaseName:@"Foundation" hintPath:nil searchHintPathFirst:false skipDLopen:false];
//		[self loadFrameworkWithBaseName:@"CoreGraphics" hintPath:@"/System/Library/Frameworks/ApplicationServices.framework/Frameworks" searchHintPathFirst:true skipDLopen:false];
	}
	return self;
}

- (id) initWithLuaState:(lua_State*)lua_state assumeOwnership:(bool)should_assume_ownership
{
	self = [super init];
	if(nil != self)
	{
		luaState = lua_state;
		ownsLuaState = should_assume_ownership;
		[self commonInit];

//		[self loadFrameworkWithBaseName:@"Foundation" hintPath:nil searchHintPathFirst:false skipDLopen:false];
		
//		[self loadFrameworkWithBaseName:@"CoreGraphics" hintPath:@"/System/Library/Frameworks/ApplicationServices.framework/Frameworks" searchHintPathFirst:true skipDLopen:false];

		
		
	}
	return self;
}


// See my comments elsewhere in the file about the potential finalize race condition.
// I've decided to make this a public function so particularly for lua states I don't "own",
// users can invoke this cleanup themselves. Or if they just want to run collection, they can call this.
+ (void) collectExhaustivelyWaitUntilDone:(bool)should_wait_until_done luaState:(lua_State*)lua_state
{
	// Is it sufficient to call this just before the Obj-C collector, or do I need to repeat in case
	// there are objects clinging in Obj-C that won't be picked up until finalize is called?
	// Right now, I think the answer is that only things that deal with finalize are suspect.
	// So there might be an issue with Lua subclass objects.
	lua_gc(lua_state, LUA_GCCOLLECT, 0);
	// Do I really need to call this since I call objc_collect?
	//	[[NSGarbageCollector defaultCollector] collectExhaustively];
	objc_collect(OBJC_FULL_COLLECTION);
	
	
	lua_gc(lua_state, LUA_GCCOLLECT, 0);
	
	// This might solve the race condition problem with tearing down the lua state.
	//	objc_collect(OBJC_EXHAUSTIVE_COLLECTION | OBJC_WAIT_UNTIL_DONE);
	if(should_wait_until_done)
	{
		objc_collect(OBJC_EXHAUSTIVE_COLLECTION | OBJC_WAIT_UNTIL_DONE);		
	}
	else
	{
		objc_collect(OBJC_EXHAUSTIVE_COLLECTION);		
	}
}

- (void) collectExhaustivelyWaitUntilDone:(bool)should_wait_until_done 
{
	[LuaCocoa collectExhaustivelyWaitUntilDone:should_wait_until_done luaState:luaState];
}

+ (void) collectExhaustivelyWaitUntilDone:(bool)should_wait_until_done
{
	// Do I really need to call this since I call objc_collect?
	[[NSGarbageCollector defaultCollector] collectExhaustively];
	//	objc_collect(OBJC_FULL_COLLECTION);
	// This might solve the race condition problem with tearing down the lua state.
	if(should_wait_until_done)
	{
		objc_collect(OBJC_EXHAUSTIVE_COLLECTION | OBJC_WAIT_UNTIL_DONE);		
	}
	else
	{
		objc_collect(OBJC_EXHAUSTIVE_COLLECTION);		
	}
	
}

+ (void) cleanUpForFinalizerLuaState:(lua_State*)lua_state ownsLuaState:(bool)owns_lua_state
{
	if(owns_lua_state)
	{
		// For Objective-C garbage collection:
		// Interesting race condition bug:
		// I think the lua_State can be closed (via luaobjc_bridge finalize) before a LuaCocoaProxyObject is finalized leading to a bad access to the lua_State.
		// I'm not sure how to deal with this. I suspect closing the lua_State at the latest possible time of shutting down
		// your application and not instructing the garbage
		// collector to collect will maximize your chance of not hitting this condition.
		// Alternatively, if there is a way you can guarantee all LuaCocoaProxyObjects are collected before you shutdown the lua_State,
		// then you probably will avoid this situation.
		// To minimize these possibilities, I will run the lua_gc before I close the state and then
		// run the Objective-C garbage collection system.
		// My current theory is that collecting lua_gc will apply any CFRelease's that need to be done.
		// Then running Obj-C's collector will clean up those released Proxy objects and they will call into Lua to remove their environment tables.
		// I don't think there are any more back-references at that point, so we don't need to ping-pong collections any more.
		// (lua_close will call lua's collector one more time though regardless.)
		// My problem is that since finalization cleanup may be interrupted or done out of order, 
		// I still don't know if calling here will guarantee that my objects will be cleaned up before I close the lua_State.
		// ALERT: 10.7 bug. collectExhaustivelyWaitUntilDone:true will cause the application to hang on quit.
		// My suspicion is that it is connected to subclassing in Lua because the 
		// CoreAnimationScriptability example does not hang.
		// For now, I am changing true to false.
		// Filed rdar://10660280
		[LuaCocoa collectExhaustivelyWaitUntilDone:false luaState:lua_state];

	}
	
	// We need to delete the entries in the LuaClassDefinitionMap for this state.
	// The reason is actually not totally obvious, but found in the field.
	// If the user defines a class in Lua and closes the state, but still uses the implementation,
	// technically that is a programmer error and not something I care to handle.
	// (Recall the implementation does try to allow multiple Lua states redefining the class if the definitions are the same as a convenience.)
	// But we hit a case where we were doing script relaunching like in HybridCoreAnimationScriptability 
	// and we sometimes got back a recycled pointer address for a new Lua state that was already used.
	// This triggered an internal assert.
	// I'm uncertain if I should do this for all lua states or just the ones I own.
	// The proper thing to do is remove the state from map.
	// Note: I do this after garbage collection to allow any Lua defined finalizers to be executed.
	// TODO: When we add blocks, we should do something similar to prevent asynchronus callbacks calling dead Lua states.
	[[LuaClassDefinitionMap sharedDefinitionMap] removeLuaStateFromMap:lua_state];
	[[LuaCocoaAvailableLuaStates sharedAvailableLuaStates] removeLuaState:lua_state];
	
	if(owns_lua_state)
	{
		// Hopefully it is now okay to close the state.
		lua_close(lua_state);
	}
}

+ (void) cleanUpForFinalizerWithData:(LuaCocoaDataForCleanup*)pointer_data
{
	[LuaCocoa cleanUpForFinalizerLuaState:[pointer_data luaState] ownsLuaState:[pointer_data ownsState]];
}


- (void) dealloc
{
	// We need to delete the entries in the LuaClassDefinitionMap for this state.
	// The reason is actually not totally obvious, but found in the field.
	// If the user defines a class in Lua and closes the state, but still uses the implementation,
	// technically that is a programmer error and not something I care to handle.
	// (Recall the implementation does try to allow multiple Lua states redefining the class if the definitions are the same as a convenience.)
	// But we hit a case where we were doing script relaunching like in HybridCoreAnimationScriptability 
	// and we sometimes got back a recycled pointer address for a new Lua state that was already used.
	// This triggered an internal assert.
	// I'm uncertain if I should do this for all lua states or just the ones I own.
	// The proper thing to do is remove the state from map.
	// Note: I do this after garbage collection to allow any Lua defined finalizers to be executed.
	// TODO: When we add blocks, we should do something similar to prevent asynchronus callbacks calling dead Lua states.
	[[LuaClassDefinitionMap sharedDefinitionMap] removeLuaStateFromMap:luaState];
	[[LuaCocoaAvailableLuaStates sharedAvailableLuaStates] removeLuaState:luaState];
	
	if(ownsLuaState)
	{
		// Hopefully it is now okay to close the state.
		lua_close(luaState);
		luaState = nil;
	}
	[frameworksLoaded release];
	
	if(nil != originThread)
	{
		CFRelease(originThread);
	}
	[super dealloc];
}

- (void) finalize
{
	if([originThread isEqualTo:[NSThread currentThread]])
	{
		// Because blocks may be asynchronous, the Lua state may have been killed off in the interim.
		// We must guard against calling into a dead Lua state.
		[LuaCocoa cleanUpForFinalizerLuaState:luaState ownsLuaState:ownsLuaState];
	}
	else
	{
		// Finalize is on a background thread, but not all the Lua/LuaCocoa stuff is thread safe.
		// I know the origin Lua thread, so I'll take advantage of it.
		LuaCocoaDataForCleanup* pointer_data = [[LuaCocoaDataForCleanup alloc] initWithLuaState:luaState ownsState:ownsLuaState];
		// This says you can use an NSObject class
		// http://www.cocoabuilder.com/archive/cocoa/217687-forcing-finalization-on-the-main-thread.html
		[LuaCocoa performSelector:@selector(cleanUpForFinalizerWithData:) onThread:originThread withObject:pointer_data waitUntilDone:NO]; 
		[pointer_data release];		
	}
	
	if(nil != originThread)
	{
		CFRelease(originThread);
	}
	
	[super finalize];
}


+ (void) purgeParseSupportCache
{
	[ParseSupportCache destroyCache];
}



/* algorithm
 BridgeSupport: Load XML. Has bridge support already loaded the information?
 - You should provide a framework or dylib name (include suffix .framework/.dylib or not?)
 - You might provide an alternative (hint) path
 - BridgeSupport should automatically look for common places
 
 .framework/Resources/BridgeSupport/%@.bridgeSupport
 
 o   /Library/Frameworks/MyFramework/Resources/BridgeSupport
 
 o   /Library/BridgeSupport
 
 o   ~/Library/BridgeSupport
 
 - Remember to also register all dependencies
 
 BridgeSupport: dlopen if not already loaded AND user doesn't opt-out
 
 LuaState: register all things associated with this library.
 - Remember that the bridge support may have already been loaded from a different lua state so don't make assumptions based on its existance.
 - Remember to also register all dependencies
 - BridgeSupport should have a way to isolate information contained in a particular library
 */
- (bool) loadFrameworkWithBaseName:(NSString*)base_name hintPath:(NSString*)hint_path searchHintPathFirst:(bool)search_hint_path_first skipDLopen:(bool)skip_dl_open
{
//	NSLog(@"loadFrameworkWithBaseName: %@, hintPath: %@", base_name, hint_path);
	BridgeSupportController* bridge_support_controller = [BridgeSupportController sharedController];

	// OPTIMIZATION: Will short circuit if framework has been loaded before and failed
	// This is done here and not in the core implementation because maybe we want to try to reload because we have a different path.
	if([bridge_support_controller isBridgeSupportFailedToLoad:base_name])
	{
		return false;
	}

	// OPTIMIZATION: Will temporary pools help since I am allocating/deallocating lots of memory?
	// Need to actually benchmark/profile.
	NSAutoreleasePool* autorelease_pool = [[NSAutoreleasePool alloc] init];
	BridgeSupportLoadState load_state = [bridge_support_controller loadFrameworkWithBaseName:base_name hintPath:hint_path searchHintPathFirst:search_hint_path_first skipDLopen:skip_dl_open];
	[autorelease_pool drain];
	
	switch (load_state) {
		case kBridgeSupportLoadOkay:
			break;

		// Lion: Seem to be getting in infinite loop. Adding cached case to escape.
		case kBridgeSupportLoadAlreadyCached:
			return true;
			break;

			// framework was loaded but bridge support files were not found.
		case kBridgeSupportLoadNotAvailable:
			return false;
			break;

		case kBridgeSupportLoadError:
		default:
			NSLog(@"Failed to load framework: %@", base_name);
			return false;
			break;
			
	}
	
	// Here's the problem: Each framework may depend on other frameworks for information.
	// Some of that information such as whether a CoreFoundation object is tollfree bridged to something
	// may be necessary to have before we try to register the items in our current framework.
	// (i.e. We may want to look up the information as we try to register it, but its dependencies
	// aren't in our xml hash yet so the query fails.)
	// To avoid this problem, we want to go through all the dependencies first and load them into the xml.
	// While we are at it, it seems to be a good idea to register them before we register our current framework.
	NSDictionary* list_of_depends_on = [bridge_support_controller listOfDependsOnNamesForFramework:base_name];
	for(NSString* a_dependency in list_of_depends_on)
	{
		[self loadFrameworkWithBaseName:a_dependency hintPath:[list_of_depends_on objectForKey:a_dependency] searchHintPathFirst:search_hint_path_first skipDLopen:skip_dl_open];
		
	}

	// Originally, all items in the BridgeSupport were traversed and registered in the Lua state.
	// This makes it possible to do things like:
	// local new_object = NSObject:alloc():init()
	// where NSObject is already defined in the Lua state.
	// Without this, we need some other mechanism to resolve what NSObject is since it is not known.
	// This also has benefits like being able to traverse the _G table and find all available items.
	// However, this added several seconds to the startup time.
	// So I am making this a #define which can be toggled.
#if LUACOCOA_REGISTER_ITEMS_IMMEDIATELY
	// Finally, we need to register all the items associated with this library into our Lua state
	[self registerItemsForFramework:base_name];
#else
	// Instead of registering immediately, we can do lazy resolving.
	// The technique I will rely on is to set a metamethod on _G to handle the look up.
	// This has the drawback that if somebody needs/changes the _G metamethod, things will break for them.

	// registerItemsForFramework sets frameworksLoaded. Since I don't call it, I will set it here for consistency.
	[frameworksLoaded setObject:[NSNumber numberWithBool:YES] forKey:base_name];
#endif	
	
	return true;
	
}

- (void) registerItemsInXmlHash:(NSDictionary*)xml_hash
{
	for(NSString* dict_key in xml_hash)
	{
		NSString* dict_value = [xml_hash objectForKey:dict_key];
		LuaCocoa_RegisterItemForKeyWithXMLFragment(luaState, dict_key, dict_value);
	}
}

- (bool) isFrameworkLoaded:(NSString*)base_name
{
	// check if already loaded
	// Ignoring the bool value in NSNumber value because I assume if the key exists, 
	// it will always be true
	if(nil != [frameworksLoaded objectForKey:base_name])
	{
		// already loaded
		return true;
	}
	return false;
}

- (void) registerItemsForFramework:(NSString*)base_name
{
	// check if already loaded
	if([self isFrameworkLoaded:base_name])
	{
		// already loaded
		return;
	}
//	NSLog(@"registerItemsForFramework: %@", base_name);
	NSAutoreleasePool* autorelease_pool = [[NSAutoreleasePool alloc] init];

	NSDictionary* xml_hash = [[BridgeSupportController sharedController] xmlHashForFramework:base_name];
	[self registerItemsInXmlHash:xml_hash];
	// Add to cache so we know not to reload this framework for this lua state
	// Adding a NSNumber to have something to put in the dictionary, but it assumed if the 
	// key exists, then the framework is loaded.
	[frameworksLoaded setObject:[NSNumber numberWithBool:YES] forKey:base_name];
	[autorelease_pool drain];
}

// probably shouldn't be called except in extreme circumstances.
- (void) registerAllItems
{
	NSDictionary* xml_hash = [[BridgeSupportController sharedController] masterXmlHash];
	[self registerItemsInXmlHash:xml_hash];
}





static NSString* LuaCocoa_ParseForErrorFilename(lua_State* L, NSString* the_string)
{
	NSString* ret_string = nil;
	
	//	NSLog(@"LuaCocoa_ParseForErrorLineNumber");
	
	lua_getglobal(L, "string");
	if(!lua_istable(L, -1))
	{
		NSLog(@"Error: Couldn't get string table");
		lua_pop(L, 1);
		return ret_string;
	}
	
	lua_getfield(L, -1, "match");
	lua_pushstring(L, [the_string UTF8String]);
	// File paths, support alphanumberic, . / \ - space
	lua_pushliteral(L, "'([%w%.%\\_/%-%s]+)':");
	
	int ret_val = lua_pcall(L, 2, 1, 0);
	if(0 != ret_val)
	{
		NSLog(@"Error with pcall in LuaCocoa_ParseForErrorFilename");
		lua_pop(L, 1);
		return ret_string;
	}
	
	if(lua_isstring(L, -1))
	{
		ret_string = [NSString stringWithUTF8String:lua_tostring(L, -1)];
	}
	lua_pop(L, 1);
	
	return ret_string;
}
static int LuaCocoa_ParseForErrorLineNumber(lua_State* L, NSString* the_string)
{
	//	NSLog(@"LuaCocoa_ParseForErrorLineNumber");
	int line_number = -1;
	
	lua_getglobal(L, "string");
	if(!lua_istable(L, -1))
	{
		NSLog(@"Error: Couldn't get string table");
		lua_pop(L, 1);
		return line_number;
	}
	
	lua_getfield(L, -1, "match");
	lua_pushstring(L, [the_string UTF8String]);
	lua_pushliteral(L, ":(%d+):");
	
	int ret_val = lua_pcall(L, 2, 1, 0);
	if(0 != ret_val)
	{
		NSLog(@"Error with pcall in LuaCocoa_ParseForErrorLineNumber");
		lua_pop(L, 1);
		return line_number;
	}
	
	if(lua_isnumber(L, -1))
	{
		line_number = lua_tointeger(L, -1);		
	}
	lua_pop(L, 1);
	return line_number;
}

NSString* LuaCocoa_ParseForErrorFilenameAndLineNumber(NSString* the_string, int* line_number)
{
	NSString* ret_string = nil;
	
	// This is probably overkill, but I'm creating a new Lua state so I can use Lua's reg-ex.
	// I probably don't need a new Lua state, but I'm being paranoid and don't want to risk working in a corrupt
	// lua state or risk polluting the current state.
	// I also don't need to worry about the string library being loaded and availabe in the table 'string'.
	lua_State* L = lua_open();
	//	luaL_openlibs(L):
	// Load string library
	lua_pushcfunction(L, luaopen_string);
    lua_pushstring(L, "string");
    lua_pcall(L, 1, 0, 0);
	
	
	/*
	*line_number = LuaCocoa_ParseForErrorLineNumber(L, the_string);
	ret_string = LuaCocoa_ParseForErrorFilename(L, the_string);
*/
	lua_getglobal(L, "string");
	if(!lua_istable(L, -1))
	{
		NSLog(@"Error: Couldn't get string table");
		lua_pop(L, 1);
		return ret_string;
	}
	
	lua_getfield(L, -1, "match");
	lua_pushstring(L, [the_string UTF8String]);
	lua_pushliteral(L, "([%w%.%\\_/%-%s]+):(%d+):");
	
	int ret_val = lua_pcall(L, 2, 2, 0);
	if(0 != ret_val)
	{
		NSLog(@"Error with pcall in LuaCocoa_ParseForErrorFilenameAndLineNumber");
		lua_pop(L, 1);
		return ret_string;
	}
	
	if(lua_isnumber(L, -1))
	{
		*line_number = lua_tointeger(L, -1);		
	}
	if(lua_isstring(L, -2))
	{
		ret_string = [NSString stringWithUTF8String:lua_tostring(L, -2)];
	}
	lua_pop(L, 2);
	
	
	//	NSLog(@"line_number=%d", *line_number);
	//	NSLog(@"ret_string=%@", ret_string);
	
	
	lua_close(L);
	return ret_string;
}

// Not sure if I want to make an API or not
#if 0
// Error intended to be used during a pcall failure
- (void) error:(const char *)fmt, ... 
{
	// Note that that the incoming fmt string is not necessarily the same as the errorString.

    va_list argp;
    va_start(argp, fmt);
//    vfprintf(stderr, fmt, argp);
    NSString* error_string = [[NSString alloc] initWithFormat:[NSString stringWithUTF8String:fmt] arguments: argp];
    va_end(argp);

//	NSLog(@"lua_stack: %d", lua_gettop(L));
//	NSLog(@"fileName:%@ functionName:%@ lineNumber:%d, error:%@, ", self.errorFileName, self.errorFunctionName, self.errorLineNumber, error_string);

	// Ugh!!!
	// In a failed require/dofile/loadfile situation from within a Lua script (at least from the root)
	// the error happens in pcall, but doesn't go through my custom error function.
	// So I don't necessarily have the filename and line number.
	// So I need to parse these things myself using the error string.
	// It doesn't help that the error string is modified with user stuff. I may need to rethink the API.
	// Error in runFileAtPath: error loading module 'strict' from file '/Users/ewing/DEVELOPMENT/MyApp/build/Debug/MyApp.app/Contents/Resources/strict.lua':
	// .../build/Debug/AnimationWrapper.app/Contents/Resources/strict.lua:10: '=' expected near 'local'
	int line_number = 0;
	NSString* error_file_name =  LuaCocoa_ParseForErrorFilenameAndLineNumber(error_string, &line_number);
/*
	if(nil == self.errorFileName)
	{
		int line_number = -1;
		self.errorFileName =  LuaCocoa_ParseForErrorFilenameAndLineNumber(error_string, &line_number);
		self.errorLineNumber = line_number;
	}
	// This might not work right. The risk is the parsed line number is from a different file.
	else if(-1 == self.errorLineNumber)
	{
		int new_line_number = -1;
		LuaCocoa_ParseForErrorFilenameAndLineNumber(error_string, &new_line_number);
		self.errorLineNumber = new_line_number;
	}	
*/	
	
	// Set to NO if you don't want the output to echo if delegate is set
	BOOL output_to_nslog = NO;
			
					
	NSObject<LuaCocoaErrorDelegate>* the_delegate = errorDelegate;
	if(nil != the_delegate)
	{
		if([the_delegate respondsToSelector:@selector(error:luaState:functionName:fileName:lineNumber:)])
		{
//			[the_delegate error:error_string luaState:L functionName:self.errorFunctionName fileName:self.errorFileName lineNumber:self.errorLineNumber];
			[the_delegate error:error_string luaState:luaState functionName:nil fileName:error_file_name lineNumber:line_number];
		}
		else
		{
			output_to_nslog = YES;
		}
	}
	else
	{
		output_to_nslog = YES;
	}
	
	
	if(YES == output_to_nslog)
	{
		NSLog(@"%@", error_string);
	}

	
	[error_string release];
//	self.errorFunctionName = nil;
//	self.errorFileName = nil;
//	self.errorLineNumber = -1;
}
#endif

// Error intending to be used in a non-pcall situation
/*
- (void) errorWithFunctionName:(NSString*)function_name fileName:(NSString*)file_name lineNumber:(NSInteger)line_number formatString:(const char *)fmt, ... 
{
	// Note that that the incoming fmt string is not necessarily the same as the errorString.
//	NSLog(@"errorWithFunctionName:%@, fileName:%@, lineNumber:%d", function_name, file_name, line_number);
    va_list argp;
    va_start(argp, fmt);
	//    vfprintf(stderr, fmt, argp);
    NSString *error_string = [[NSString alloc] initWithFormat: [NSString stringWithUTF8String:fmt] arguments: argp];
    va_end(argp);
//	NSLog(@"error_string:%@", error_string);

	
	// Ugh!!!
	// In a failed require/dofile/loadfile situation from within a Lua script (at least from the root)
	// the error happens in pcall, but doesn't go through my custom error function.
	// So I don't necessarily have the filename and line number.
	// So I need to parse these things myself using the error string.
	// It doesn't help that the error string is modified with user stuff. I may need to rethink the API.
	// Error in runFileAtPath: error loading module 'strict' from file '/Users/ewing/DEVELOPMENT/Sling/Paul/Sling/SlingPlayerEricBranch/build/Debug/AnimationWrapper.app/Contents/Resources/strict.lua':
	// ...ricBranch/build/Debug/AnimationWrapper.app/Contents/Resources/strict.lua:10: '=' expected near 'local'
	if(nil == file_name)
	{
		int new_line_number = -1;
		file_name =  LuaCocoa_ParseForErrorFilenameAndLineNumber(error_string, &new_line_number);
		line_number = new_line_number;
	}
	// The problem I have is that in some cases, the file path is truncated by Lua. In these cases I know about, I supply
	// my own file. However, I still need to parse for a line number. The problem is that the line number I parse for may
	// come from a different file.
	else if(-1 == line_number)
	{
		int new_line_number = -1;
		LuaCocoa_ParseForErrorFilenameAndLineNumber(error_string, &new_line_number);
		line_number = new_line_number;
	}
	// Set to NO if you don't want the output to echo if delegate is set
	BOOL output_to_nslog = NO;
	
	
	NSObject<LuaCocoaErrorDelegate>* the_delegate = errorDelegate;
	if(nil != the_delegate)
	{
		if([the_delegate respondsToSelector:@selector(error:luaState:functionName:fileName:lineNumber:)])
		{
			[the_delegate error:error_string luaState:L functionName:function_name fileName:file_name lineNumber:line_number];
		}
		else
		{
			output_to_nslog = YES;
		}
	}
	else
	{
		output_to_nslog = YES;
	}
	
	
	if(YES == output_to_nslog)
	{
		NSLog(@"%@", error_string);
	}
	
	
	[error_string release];
}
*/

/*
- (void) setErrorDelegate:(id<LuaCocoaErrorDelegate>)error_delegate
{
	// Not retained
	errorDelegate = error_delegate;
}

- (id<LuaCocoaErrorDelegate>) errorDelegate
{
	return errorDelegate;
}

- (void) setLuaErrorFunction:(lua_CFunction)error_function
{
	luaErrorFunction = error_function;
}

- (lua_CFunction)luaErrorFunction
{
	return luaErrorFunction;
}
*/


- (NSString*) pcallLuaFunction:(const char*)lua_function_name withSignature:(const char*)parameter_signature, ...
{
	NSString* ret_string = nil;
	if(NULL == luaState)
	{
		return @"No luaState";
	}
	va_list vl;
	va_start(vl, parameter_signature);
/*	
	ret_string = LuaCocoa_PcallLuaFunctionv(luaState, luaErrorFunction, lua_function_name, parameter_signature, vl);
*/
	ret_string = LuaCocoa_PcallLuaFunctionv(luaState, NULL, lua_function_name, parameter_signature, vl);
	va_end(vl);
	
	return ret_string;
}

- (NSString*) pcallLuaFunction:(const char*)lua_function_name errorFunction:(lua_CFunction)error_function withSignature:(const char*)parameter_signature, ...
{
	NSString* ret_string = nil;
	if(NULL == luaState)
	{
		return @"No luaState";
	}
	va_list vl;
	va_start(vl, parameter_signature);
	ret_string = LuaCocoa_PcallLuaFunctionv(luaState, error_function, lua_function_name, parameter_signature, vl);
	va_end(vl);
	
	return ret_string;
}

@end

// Assumes function exists. Not expecting to be running in Lua at the moment.
// Returns autoreleased string containing filename or nil.
// Returns by reference the line number and last line number of the function.
NSString* LuaCocoa_GetInfoOnFunction(lua_State* L, const char* function_name, int* line_defined, int* last_line_defined)
{
	int stack_size = lua_gettop(L);
	lua_Debug ar;
	NSString* ret_string = nil;
	lua_getglobal(L, function_name);
	lua_getinfo(L, ">S", &ar);
	// currentline is non-existant in the expected usage case
	//	printf("get_info: %d %d %s\n", ar.linedefined, ar.lastlinedefined, ar.source);
	
	if(NULL != line_defined)
	{
		*line_defined = ar.linedefined;		
	}
	if(NULL != last_line_defined)
	{
		*last_line_defined = ar.lastlinedefined;
	}
	
	if(NULL != ar.source)
	{
		NSMutableString* temp_string = [NSString stringWithUTF8String:ar.source];
		// There is an annoying '@' character in front of the string.
		if([temp_string hasPrefix:@"@"])
		{
			ret_string = [temp_string substringFromIndex:1];
		}
		else
		{
			// I think if there is no '@' symbol, there is just source and no file.
			// Return nil?
			ret_string = nil;
		}
	}
	
	lua_settop(L, stack_size);
	return ret_string;
}

// FIXME: Unify with Obj-C method signatures. Perhaps call actual LuaCocoa backend for parsing?
// Adapted from Programming in Lua call_va
// Example:
// [luaCocoa callFunction:@"OnMouseUp" withSignature:"@@idd>bids@@@@", the_layer, layer_name, button_number, x_pos, y_pos,
// 		&bool_val, &int_val, &double_val, &str_val, &ns_str_val, &layer_val, &array_val, &dict_val];
// In this case, we pass in two Obj-C objects followed by an int and two doubles.
// The > marker denotes the return types.
// In this case, we expect the Lua function to return a boolean, int, double, const char* and 4 Obj-C objects.
// The return objects go through the propertylist conversion, so in particular, Lua tables and arrays get passed back as 
// NSDictionary and NSArray.
// Notes: Since I pop the stack at the end of the function (so you don't have to worry about balancing), 
// I can't return a char* because it could get deallocated before I am done. 
// So, the easiest answer seems to be to convert to an NSString. So 's' tokens on the return side get copied
// into NSString, so you must provide that type of variable.
// Also, passing nil to Lua functions and  Lua functions returning nil are not supported well. (nil might work through the property list.)
// Bugs: error handling isn't quite right. luaL_error isn't right because we haven't pcall'ed yet or have returned from pcall.
// I don't think error: has all the correct information. I think I need to write a special error handler the case of
// being outside pcall.
// TODO: Figure out how to support optional return parameters.
NSString* LuaCocoa_PcallLuaFunction(lua_State* lua_state, lua_CFunction lua_error_function, const char* lua_function_name, const char* parameter_signature, ...)
{
//	const char* sig = [the_signature UTF8String];
	va_list vl;

	va_start(vl, parameter_signature);

	NSString* ret_string = LuaCocoa_PcallLuaFunctionv(lua_state, lua_error_function, lua_function_name, parameter_signature, vl);

	va_end(vl);
	return ret_string;
}

// Maybe I should use NSError to differentiate errors, e.g. function does not exist vs. runtime error in script vs. invalid argument specification.
NSString* LuaCocoa_PcallLuaFunctionv(lua_State* lua_state, lua_CFunction lua_error_function, const char* lua_function_name, const char* parameter_signature, va_list vl)
{
	NSString* ret_string = nil;
//	const char* sig = [the_signature UTF8String];
	int narg, nres;  /* number of arguments and results */
    NSMutableString* concat_error_string = [NSMutableString stringWithFormat:@"Error calling function: %s\n", lua_function_name];
	_Bool found_error_beginning = false;
	_Bool found_error_ending = false;

	int stack_size = lua_gettop(lua_state); // Save the stack size to make it easier to restore because the optional error functions requires a check
	
	int error_function_position_offset = 0;
	int final_error_function_position_offset = 0;
	
	if(NULL != lua_error_function)
	{
		lua_pushcfunction(lua_state, lua_error_function);
		error_function_position_offset = -2;
	}
	
	lua_getglobal(lua_state, lua_function_name);  /* get function */
	if(!lua_isfunction(lua_state, -1 ))
	{
		//		NSLog(@"function not found, stack top is: %d", lua_gettop(L));
		ret_string = @"Function does not exist";
		lua_settop(lua_state, stack_size); // will pop the stack to the correct size regardless of whether error function was pushed
		return ret_string;
	}

//	va_start(vl, parameter_signature);

	/* push arguments */
	narg = 0;
	while (*parameter_signature)
	{  /* push arguments */
        switch (*parameter_signature++)
		{
			case 'b':  /* boolean argument */
				lua_pushboolean(lua_state, va_arg(vl, int));
				break;
								
			case 'd':  /* double argument */
				lua_pushnumber(lua_state, va_arg(vl, double));
				break;
				
			case 'i':  /* int argument */
				lua_pushinteger(lua_state, va_arg(vl, int));
				break;
				
			case 's':  /* string argument */
				lua_pushstring(lua_state, va_arg(vl, char *));
				break;

			case '@':  /* Obj-C id argument */
				LuaObjectBridge_Pushid(lua_state, va_arg(vl, id));
				break;
			
			case '#':  /* Obj-C Class argument */
				LuaObjectBridge_PushClass(lua_state, va_arg(vl, Class));
				break;
				
			case 'v':  /* void* argument */
				lua_pushlightuserdata(lua_state, va_arg(vl, void*));
				break;
				
			case '>':
				goto endwhile;
				
			default:
				found_error_beginning = true;
//				luaL_error(lua_state, "invalid option (%c)", *(parameter_signature - 1));
				[concat_error_string appendFormat:@"Invalid parameter option (%c)\n", *(parameter_signature - 1)];
				//[self errorWithFunctionName:function_name fileName:nil lineNumber:-1  formatString:"invalid option (%c)", *(parameter_signature - 1)];
        }
        narg++;
        luaL_checkstack(lua_state, 1, "too many arguments");
	} endwhile:
    
	/* do the call */
	nres = strlen(parameter_signature);  /* number of expected results */
	
	if(NULL != lua_error_function)
	{
		final_error_function_position_offset = error_function_position_offset - narg;
	}
	else
	{
		final_error_function_position_offset = 0;
	}

	
	if (lua_pcall(lua_state, narg, nres, final_error_function_position_offset) != 0)  /* do the call */
	{


//		[self error:"Error running function '%s': %s",
//			  lua_function_name, lua_tostring(lua_state, -1)];
		ret_string = [NSString stringWithUTF8String:lua_tostring(lua_state, -1)];
		lua_pop(lua_state, -1);
		return ret_string;

	}
    
	/* retrieve results */
	const int number_of_results = nres;

	nres = -nres;  /* stack index of first result */
	while (*parameter_signature)
	{  /* get results */
        switch (*parameter_signature++)
		{
			case 'b':  /* boolean result */
				if(!lua_isboolean(lua_state, nres))
				{
					found_error_ending = true;
					[concat_error_string appendFormat:@"Wrong result type: expecting boolean at return position: %d\n", number_of_results + nres + 1];
//					[self errorWithFunctionName:function_name fileName:nil lineNumber:-1  formatString:"wrong result type: expecting boolean at index=%d", nres];
					//[self error:"wrong result type: expecting boolean at index=%d", nres];
					//luaL_error(L, "wrong result type: expecting boolean at index=%d", nres);
				}
				else
				{
					*va_arg(vl, bool *) = lua_toboolean(lua_state, nres);					
				}
				break;
				
			case 'd':  /* double result */
				if(!lua_isnumber(lua_state, nres))
				{
					found_error_ending = true;
					[concat_error_string appendFormat:@"Wrong result type: expecting double at return position: %d\n", number_of_results + nres + 1];
//					[self errorWithFunctionName:function_name fileName:nil lineNumber:-1  formatString:"wrong result type: expecting double at index=%d", nres];
//					[self error:"wrong result type: expecting double at index=%d", nres];
					//luaL_error(L, "wrong result type: expecting double at index=%d", nres);
				}
				else
				{
					*va_arg(vl, double *) = lua_tonumber(lua_state, nres);					
				}
				break;
				
			case 'i':  /* int result */
				if(!lua_isnumber(lua_state, nres))
				{
					found_error_ending = true;
					[concat_error_string appendFormat:@"Wrong result type: expecting number at return position: %d\n", number_of_results + nres + 1];
//					[self errorWithFunctionName:function_name fileName:nil lineNumber:-1  formatString:"wrong result type: expecting int at index=%d", nres];
//					[self error:"wrong result type: expecting int at index=%d", nres];		
//					luaL_error(L, "wrong result type: expecting int at index=%d", nres);
				}
				else
				{
					*va_arg(vl, int *) = (int)lua_tointeger(lua_state, nres);					
				}
				break;
				
			case 's':  /* string result */
				if(!lua_isstring(lua_state, nres))
				{
					found_error_ending = true;
					[concat_error_string appendFormat:@"Wrong result type: expecting string at return position: %d\n", number_of_results + nres + 1];
//					[self errorWithFunctionName:function_name fileName:nil lineNumber:-1  formatString:"wrong result type: expecting string at index=%d", nres];
//					[self error:"wrong result type: expecting string at index=%d", nres];
//					luaL_error(L, "wrong result type: expecting string at index=%d", nres);					
				}
				else
				{
					// Problem: Since I pop the stack at the end of the function, I can't return a char* 
					// because it could get deallocated before you are done. 
					// So, the easiest answer seems to be to copy to an NSString.
//					*va_arg(vl, const char **) = lua_tostring(L, nres);
					*va_arg(vl, NSString**) = [NSString stringWithUTF8String:lua_tostring(lua_state, nres)];
				}
				break;
				
			case '@':  /* Obj-C id result */
				if(!LuaObjectBridge_isidinstance(lua_state, nres) && !(LuaObjectBridge_ispropertylist(lua_state, nres)) )
				{
					found_error_ending = true;
					[concat_error_string appendFormat:@"Wrong result type: expecting id at return position: %d\n", number_of_results + nres + 1];
//					[self errorWithFunctionName:function_name fileName:nil lineNumber:-1  formatString:"wrong result type: expecting id at index=%d", nres];
//					[self error:"wrong result type: expecting id at index=%d", nres];					
//					luaL_error(L, "wrong result type: expecting id at index=%d", nres);					
				}
				else
				{
					if(LuaObjectBridge_ispropertylist(lua_state, nres))
					{
						*va_arg(vl, id *) = LuaObjectBridge_topropertylist(lua_state, nres);
					}
					else
					{
						*va_arg(vl, id *) = LuaObjectBridge_toid(lua_state, nres);					
					}
				}
				break;
				
			case '#':  /* Obj-C Class result */
				if(!LuaObjectBridge_isidclass(lua_state, nres))
				{
					found_error_ending = true;
					[concat_error_string appendFormat:@"Wrong result type: expecting Class at return position: %d\n", number_of_results + nres + 1];
//					[self errorWithFunctionName:function_name fileName:nil lineNumber:-1  formatString:"wrong result type: expecting id at index=%d", nres];
//					[self error:"wrong result type: expecting id at index=%d", nres];					
//					luaL_error(L, "wrong result type: expecting id at index=%d", nres);					
				}
				else
				{
					*va_arg(vl, Class *) = LuaObjectBridge_toid(lua_state, nres);					
				}
				break;
				
			case 'v':  /* void pointer result */
				*va_arg(vl, void **) = lua_touserdata(lua_state, nres);
				break;

			default:
				found_error_ending = true;
				[concat_error_string appendFormat:@"Invalid result type (%c)\n", *(parameter_signature - 1)];
//				[self errorWithFunctionName:function_name fileName:nil lineNumber:-1  formatString:"invalid option (%c)", *(sig - 1)];
//				[self error:"invalid option (%c)", *(sig - 1)];
//				luaL_error(L, "invalid option (%c)", *(sig - 1));

        }
        nres++;
	}
//	va_end(vl);

	
	if(YES == found_error_ending || YES == found_error_beginning)
	{
/*
		int line_defined = 0;
		int last_line_defined = 0;
		NSString* file_name = LuaCocoa_GetInfoOnFunction(lua_state, function_name, &line_defined, &last_line_defined);
		int line_number_to_report = line_defined;
		if(YES == found_error_ending)
		{
			line_number_to_report = last_line_defined;
		}
//		[self errorWithFunctionName:function_name fileName:file_name lineNumber:line_number_to_report  formatString:"%@", concat_error_string];
 */	
		ret_string = concat_error_string;
	}
	lua_settop(lua_state, stack_size); // will pop the stack to the correct size regardless of whether error function was pushed

	return ret_string;
}


id LuaCocoa_CheckInstance(lua_State* lua_state, int stack_index)
{
	id the_instance = LuaObjectBridge_checkid(lua_state, stack_index);
	if(LuaObjectBridge_isidinstance(lua_state, stack_index))
	{
		return the_instance;
	}
	else
	{
		luaL_typerror(lua_state, stack_index, "Obj-C id");  /* else error */
		return nil;  /* to avoid warnings */
	}

}

bool LuaCocoa_IsInstance(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_isidinstance(lua_state, stack_index);
}

id LuaCocoa_ToInstance(lua_State* lua_state, int stack_index)
{
	// FIXME: This will also retrieve Class
	return LuaObjectBridge_toid(lua_state, stack_index);
}

void LuaCocoa_PushInstance(lua_State* lua_state, id the_object)
{
	LuaObjectBridge_Pushid(lua_state, the_object);
}


bool LuaCocoa_IsClass(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_isidclass(lua_state, stack_index);
}

Class LuaCocoa_CheckClass(lua_State* lua_state, int stack_index)
{
	Class the_class = LuaObjectBridge_checkid(lua_state, stack_index);
	if(LuaObjectBridge_isidclass(lua_state, stack_index))
	{
		return the_class;
	}
	else
	{
		luaL_typerror(lua_state, stack_index, "Obj-C Class");  /* else error */
		return nil;  /* to avoid warnings */
	}
}

Class LuaCocoa_ToClass(lua_State* lua_state, int stack_index)
{
	// FIXME: This will also retrieve id
	return (Class)LuaObjectBridge_toid(lua_state, stack_index);
}

void LuaCocoa_PushClass(lua_State* lua_state, Class the_class)
{
	LuaObjectBridge_PushClass(lua_state, the_class);
}


bool LuaCocoa_IsNSNumber(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_isnsnumber(lua_state, stack_index);
}

NSNumber* LuaCocoa_CheckNSNumber(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_checknsnumber(lua_state, stack_index);
}

NSNumber* LuaCocoa_ToNSNumber(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_tonsnumber(lua_state, stack_index);
}

void LuaCocoa_PushUnboxedNSNumber(lua_State* lua_state, NSNumber* the_number)
{
	LuaObjectBridge_pushunboxednsnumber(lua_state, the_number);
}



bool LuaCocoa_IsNSNull(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_isnsnull(lua_state, stack_index);
}

NSNull* LuaCocoa_CheckNSNull(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_checknsnull(lua_state, stack_index);
}

NSNull* LuaCocoa_ToNSNull(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_tonsnull(lua_state, stack_index);
}



bool LuaCocoa_IsNSString(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_isnsstring(lua_state, stack_index);
}

NSString* LuaCocoa_CheckNSString(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_checknsstring(lua_state, stack_index);
}

NSString* LuaCocoa_ToNSString(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_tonsstring(lua_state, stack_index);
}

void LuaCocoa_PushUnboxedNSString(lua_State* lua_state, NSString* the_string)
{
	LuaObjectBridge_pushunboxednsstring(lua_state, the_string);
}

__strong const char* LuaCocoa_ToString(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_tostring(lua_state, stack_index);
}




bool LuaCocoa_IsNSArray(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_isnsarray(lua_state, stack_index);
}

void LuaCocoa_PushUnboxedNSArray(lua_State* lua_state, NSArray* the_array)
{
	LuaObjectBridge_pushunboxednsarray(lua_state, the_array);
}



bool LuaCocoa_IsNSDictionary(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_isnsdictionary(lua_state, stack_index);
}

void LuaCocoa_PushUnboxedNSDictionary(lua_State* lua_state, NSDictionary* the_dictionary)
{
	LuaObjectBridge_pushunboxednsdictionary(lua_state, the_dictionary);
}


bool LuaCocoa_IsPropertyList(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_ispropertylist(lua_state, stack_index);
}

id LuaCocoa_ToPropertyList(lua_State* lua_state, int stack_index)
{
	return LuaObjectBridge_topropertylist(lua_state, stack_index);
}

void LuaCocoa_PushUnboxedPropertyList(lua_State* lua_state, id the_object)
{
	LuaObjectBridge_pushunboxedpropertylist(lua_state, the_object);
}



bool LuaCocoa_IsSelector(lua_State* lua_state, int stack_index)
{
	return LuaSelectorBridge_isselector(lua_state, stack_index);
}

SEL LuaCocoa_CheckSelector(lua_State* lua_state, int stack_index)
{
	return LuaSelectorBridge_checkselector(lua_state, stack_index);
}

SEL LuaCocoa_ToSelector(lua_State* lua_state, int stack_index)
{
	// FIXME: This will also retrieve id
	return LuaSelectorBridge_toselector(lua_state, stack_index);
}

void LuaCocoa_PushSelector(lua_State* lua_state, SEL the_selector)
{
	LuaSelectorBridge_pushselector(lua_state, the_selector);
}



bool LuaCocoa_IsStruct(lua_State* lua_state, int stack_index)
{
	return LuaStructBridge_isstruct(lua_state, stack_index);
}


bool LuaCocoa_IsStructWithName(lua_State* lua_state, int stack_index, const char* key_name)
{
	const char* ret_string = LuaStructBridge_GetBridgeKeyNameFromMetatableAsString(lua_state, stack_index);
	if(strcmp(ret_string, key_name))
	{
		return false;
	}
	else
	{
		return true;
	}
}


const char* LuaCocoa_GetStructName(lua_State* lua_state, int stack_index)
{
	return LuaStructBridge_GetBridgeKeyNameFromMetatableAsString(lua_state, stack_index);	
}


void* LuaCocoa_CheckStruct(lua_State* lua_state, int stack_index, const char* key_name)
{
	const char* ret_string = LuaStructBridge_GetBridgeKeyNameFromMetatableAsString(lua_state, stack_index);
	if(strcmp(ret_string, key_name))
	{
		luaL_typerror(lua_state, stack_index, key_name); /* else error */
		return NULL; /* keep compiler happy */
	}
	else
	{
		return lua_touserdata(lua_state, stack_index);
	}
}


bool LuaCocoa_PushStruct(lua_State* lua_state, void* the_struct, const char* key_name)
{
	NSString* ns_key_name = [NSString stringWithUTF8String:key_name];
	
	ParseSupportStruct* parse_support_struct = [ParseSupportStruct parseSupportStructFromKeyName:ns_key_name];
	if(nil == parse_support_struct)
	{
		return false;
	}
	size_t size_of_return_struct = parse_support_struct.sizeOfStruct;
	if(0 == size_of_return_struct)
	{
		return false;
	}
	void* return_struct_userdata = lua_newuserdata(lua_state, size_of_return_struct);
	memcpy(return_struct_userdata, the_struct, size_of_return_struct);	
	LuaStructBridge_SetStructMetatableOnUserdata(lua_state, -1, ns_key_name, parse_support_struct.structName);
	return true;
}


