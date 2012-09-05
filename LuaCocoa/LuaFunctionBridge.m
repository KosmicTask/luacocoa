//
//  LuaFunctionBridge.m
//  LuaCocoa
//
//  Created by Eric Wing on 11/9/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "LuaFunctionBridge.h"

//#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <objc/runtime.h>
// #import <objc/message.h>
#include <ffi/ffi.h>

#include "lua.h"
#include "lauxlib.h"
#include "LuaCUtils.h"
#include "LuaStructBridge.h"
#import "LuaObjectBridge.h"
#import "LuaSelectorBridge.h"

#import "ParseSupport.h"
#import "ParseSupportStruct.h"
#import "ParseSupportFunction.h"

#import "LuaFFISupport.h"

#import "NSStringHelperFunctions.h"



const char* LUACOCOA_FFI_CIF = "LuaCocoa.ffi_cif";
const char* LUACOCOA_BRIDGESUPPORT_EXTRA_DATA = "LuaCocoa.BridgeSupport_ExtraData";



static int GarbageCollectForBridgeSupportExtraData(lua_State* lua_state)
{
	//	fprintf(stderr, "In GarbageCollect\n");
	LuaUserDataContainerForObject* ret_val = luaL_checkudata(lua_state, -1, LUACOCOA_BRIDGESUPPORT_EXTRA_DATA);
	if(NULL == ret_val)
	{
		NSLog(@"Unexpected no value");
		return 0;
	}
	//	NSLog(@"CFRelease");
	CFRelease(ret_val->theObject);
	return 0;
}

static int ConvertBridgeSupportExtraDataToString(lua_State* lua_state)
{
	
	LuaUserDataContainerForObject* ret_val = luaL_checkudata(lua_state, -1, LUACOCOA_BRIDGESUPPORT_EXTRA_DATA);
	if(NULL == ret_val)
	{
		NSLog(@"Unexpected no value");
		return 0;
	}
	
	//	fprintf(stderr, "ConvertCFTypeRefToString called: %s\n", [[(NSObject*)the_object description]  UTF8String]);
	lua_pushstring(lua_state, [[(NSObject*)ret_val->theObject description]  UTF8String]);
	//	fprintf(stderr, "ConvertCFTypeRefToString called\n");
	//	lua_pushstring(lua_state, "ConvertCFTypeRefToString");
	
	return 1;
}


static const struct luaL_reg methods_for_BridgeSupportExtraData[] =
{
	{"__gc", GarbageCollectForBridgeSupportExtraData},
	{"__tostring", ConvertBridgeSupportExtraDataToString},
	{NULL,NULL},
};


// Argument 1: XML string
// Return 1: userdata (cif)
// Return 2: userdata (bridge support extra data)
// The idea of returning a cif came from luaffi and/or lua alien,
// where ffi was exposed to Lua. In principle, these 
// functions are public unless I later decide to hide them.
// However, maybe they could/should be public because they might be useful?
// So I return a ffi_cif userdata which can be used directly.
// I also wanted additional bridge metadata in userdata for performance
// so I didn't have to re-parse a bunch of information at call time.
// As an after thought, maybe I should have hidden it using upvalues?
int LuaFunctionBridge_FFIPrepCif(lua_State* lua_state)
{
	const int NUMBER_OF_SUPPORT_ARGS = 1; // To denote that the first argument is not for a function parameter so things must be shifted

	//	NSLog(@"in lua_ffi_prep_cif");
	ffi_cif* cif_ptr;
	int number_of_lua_args = lua_gettop(lua_state);
	//	NSLog(@"in lua_ffi_prep_cif number_of_lua_args=%d", number_of_lua_args);
	//    ffi_type** arg_types;
	//	ffi_type* arg_types[2];
	
	if(number_of_lua_args < 1)
	{
		return 0;
	}
	
	
	
	/* Variations:
	 - Does signature info come from BridgeSupport, Obj-C runtime, or Lua?
	 - Is this a function, method, or something else
	 Functions must have BridgeSupport
	 Methods
	 
	 1) Compute the size of the arrays
	 If BridgeSupport:
	 Parse through the XML to find what the size of all the arguments and return values are. 
	 This includes flattening structs.
	 If Obj-C runtime (no functions):
	 Information may be imperfect for things like BOOL vs _Bool.
	 Structs will not be able to be flattened. Not sure what to do...different calling path?
	 
	 If the function is variadic, we may need information from Lua to get types and number of arguments.
	 And if we have BridgeSupport, we should find out if the API is a printf style and parse the format string.
	 
	 */
	
	const char* xml_cstring = luaL_checkstring(lua_state, 1); // absolute position because of varadic

	// Load up the XML into an object we can more easily use
	ParseSupportFunction* parse_support = [[[ParseSupportFunction alloc] initWithXMLString:[NSString stringWithUTF8String:xml_cstring]] autorelease];
	
	// If there are variadic arguments, add them to the parse support information.
	// Note that if there are variadic arguments, this parse_support instance cannot be reused/cached for different function calls
	LuaFFISupport_ParseVariadicArguments(lua_state, parse_support, NUMBER_OF_SUPPORT_ARGS);

#if 0
	if([parse_support.keyName isEqualToString:@"NSFileTypeForHFSTypeCode"])
	{
		NSLog(@"NSFileTypeForHFSTypeCode");
	}
	else if([parse_support.keyName isEqualToString:@"NSMapInsertKnownAbsent"])
	{
		NSLog(@"NSMapInsertKnownAbsent");
	}
	else if([parse_support.keyName isEqualToString:@"NSIntersectionRange"])
	{
		NSLog(@"NSIntersectionRange");
	}
	else if([parse_support.keyName isEqualToString:@"NSConvertHostDouble"])
	{
		NSLog(@"NSConvertHostDouble");
	}
	else if([parse_support.keyName isEqualToString:@"NSCreateMapTable"])
	{
		NSLog(@"NSCreateMapTable");
	}
	else if([parse_support.keyName isEqualToString:@"NSLog"])
	{
		NSLog(@"NSLog");
	}
	else if([parse_support.keyName isEqualToString:@"NSContainsRect"])
	{
		NSLog(@"NSContainsRect");
	}
	else if([parse_support.keyName isEqualToString:@"NSDivideRect"])
	{
		NSLog(@"NSDivideRect");
	}
	else if([parse_support.keyName isEqualToString:@"CFStringFindAndReplace"])
	{
		NSLog(@"CFStringFindAndReplace");
	}
#endif
	// Currently used to escape unimplemented functionality.
	if([parse_support internalError])
	{
		//		NSLog(@"Escape on internalError hack");
		return 0;
	}
	

	
	/* Creating a block of memory is a bit tricky.
	 We actually need separate blocks of memory:
	 1) Memory for the ffi_cif
	 2) Memory to describe the normal arguments
	 3) Memory to hold custom ffi_type(s) (as in the case that an argument is a struct)
	 4) Memory to describe the flattened arguments (i.e. if #2 is a struct, this contains memory for each individial element in the struct)
	 5) Memory to describe the return argument
	 6) Memory to hold custom ffi_type (as in the case that the return argument is a struct)
	 7) Memory to describe the flattened return argument
	 When using Lua userdata, it is easiest to treat this a single block of memory 
	 since we want garbage collection to clean it up at the same time.
	 But because the memory is for distinct things, we need to keep our pointers straight
	 and not clobber each section's memory.
	 All the structures also need their internal pointers set correctly to find the correct blocks of memory.
	 
	 Userdata is:
	 1) sizeof(cif)
	 2) sizeof(ffi_type*) * number_of_real_function_arguments // don't forget to count varadic
	 3) sizeof(ffi_type) * number_of_real_arguments_that_need_to_be_flattened
	 4) sizeof(ffi_type*) * number_of_flattened_function_arguments // don't forget to count NULL terminators
	 5) sizeof(ffi_type*)
	 6) sizeof(ffi_type) * number_of_return_arguments_that_need_to_be_flattened
	 7) sizeof(ffi_type*) * number_of_flattened_function_arguments // don't forget to count NULL terminators
	 
	 */
	size_t size_of_cif = sizeof(ffi_cif);
	size_t size_of_real_args = sizeof(ffi_type*) * parse_support.numberOfRealArguments;
	size_t size_of_flattened_args = sizeof(ffi_type*) * parse_support.numberOfFlattenedArguments;
	size_t size_of_custom_type_args = sizeof(ffi_type) * parse_support.numberOfRealArgumentsThatNeedToBeFlattened;
//	size_t size_of_real_return = sizeof(ffi_type*);
	size_t size_of_flattened_return = sizeof(ffi_type*) * parse_support.numberOfFlattenedReturnValues;
	size_t size_of_custom_type_return;
	if(0 == size_of_flattened_return)
	{
		size_of_custom_type_return = 0;
	}
	else
	{
		size_of_custom_type_return = sizeof(ffi_type);
	}
	
	
	cif_ptr = lua_newuserdata(lua_state, 
							  size_of_cif
							  + size_of_real_args
							  + size_of_flattened_args
							  + size_of_custom_type_args
//							  + size_of_real_return  // I think this gets removed due to the bug found by Fjolnir
							  + size_of_flattened_return
							  + size_of_custom_type_return
							  );
	
	// Tricky pointer math:
	// Since the userdata was created with extra memory padding at the end of the ffi_cif,
	// the +1 increments the memory address like an array index.
	// So the pointer moves to the end of the cif.
	// We will store ffi argument types at the end of this memory buffer.	
	ffi_type** real_args_ptr = (ffi_type**)(cif_ptr + 1);
	
	// Typecast this pointer to byte sizes so we can just add bytes to move the pointer
	int8_t* address_ptr = (int8_t*)(cif_ptr + 1);
	
	// 3
	ffi_type* custom_type_args_ptr = (ffi_type*)(address_ptr + size_of_real_args);
	address_ptr = (int8_t*)(address_ptr + size_of_real_args);
	
	// 4 
	ffi_type** flattened_args_ptr = (ffi_type**)(address_ptr + size_of_custom_type_args);
	address_ptr = (int8_t*)(address_ptr + size_of_custom_type_args);
	
	// 5
	// Based on the bug found by Fjolnir, I think this is wrong too.
	// I think the pointer should be NULL to be set by FFISupport_ParseSupportFunctionReturnValueToFFIType.
	// But this will impact the memory address offsets and size of the structure.
	// For a struct return, I think the custom_type_return_ptr gets uses as the address for real_return_ptr, so these are the same thing.
	// So I think I can skip the address increment and remove this from the sizeof caluculation above. 
//	ffi_type* real_return_ptr = (ffi_type*)(address_ptr + size_of_flattened_args);
//	address_ptr = (int8_t*)(address_ptr + size_of_flattened_args);
	ffi_type* real_return_ptr = NULL;

	
	// 6
	// This address changes to +size_of_flattened_args because of the above bug fix.
//	ffi_type* custom_type_return_ptr = (ffi_type*)(address_ptr + size_of_real_return);
//	address_ptr = (int8_t*)(address_ptr + size_of_real_return);
	ffi_type* custom_type_return_ptr = (ffi_type*)(address_ptr + size_of_flattened_args);
	address_ptr = (int8_t*)(address_ptr + size_of_flattened_args);
	
	// 7
	ffi_type** flattened_return_ptr = (ffi_type**)(address_ptr + size_of_custom_type_return);
	//	address_ptr = (int8_t*)(address_ptr + size_of_custom_type_return)
	
	
	
	
	
    luaL_getmetatable(lua_state, LUACOCOA_FFI_CIF);
    lua_setmetatable(lua_state, -2);
	
	
	FFISupport_ParseSupportFunctionArgumentsToFFIType(parse_support, custom_type_args_ptr, &real_args_ptr, flattened_args_ptr);
	
	FFISupport_ParseSupportFunctionReturnValueToFFIType(parse_support, custom_type_return_ptr, &real_return_ptr, flattened_return_ptr);
	
	
	LuaUserDataContainerForObject* bridge_support_data_container = lua_newuserdata(lua_state, sizeof(LuaUserDataContainerForObject));
	// Trickery to deal with Garbage Collection and non-garbage collection
	CFRetain(parse_support);
	bridge_support_data_container->theObject = parse_support;
	
	
    luaL_getmetatable(lua_state, LUACOCOA_BRIDGESUPPORT_EXTRA_DATA);
    lua_setmetatable(lua_state, -2);
	
	
	
	void* function_address = dlsym(RTLD_DEFAULT, [parse_support.keyName UTF8String]);
	parse_support.dlsymFunctionPointer = function_address;

#if 0
/*			
	if([parse_support.keyName isEqualToString:@"NSFileTypeForHFSTypeCode"])
	{
		NSLog(@"real_return_ptr.size: %d", real_return_ptr->size);
		NSLog(@"real_return_ptr.type: %d", real_return_ptr->type);
		
		NSLog(@"real_args_ptr[0].size: %d", real_args_ptr[0]->size);
		NSLog(@"real_return_ptr[0].type: %d", real_args_ptr[0]->type);
		
		assert(real_return_ptr == &ffi_type_pointer);
		assert(real_args_ptr[0] == &ffi_type_uint32);
		
	}
	else if([parse_support.keyName isEqualToString:@"NSMapInsertIfAbsent"])
	{
		NSLog(@"NSMapInsertIfAbsent");
	}
	else if([parse_support.keyName isEqualToString:@"NSIntersectionRange"])
	{
		NSLog(@"NSIntersectionRange");
		
		//		NSLog(@"real_return_ptr.size: %d", real_return_ptr->size);
		NSLog(@"real_return_ptr.type: %d", real_return_ptr->type);
		NSLog(@"real_return_ptr->elements[0]->size: %d", real_return_ptr->elements[0]->size);
		NSLog(@"real_return_ptr->elements[0]->type: %d", real_return_ptr->elements[0]->type);
		NSLog(@"real_return_ptr->elements[1]->size: %d", real_return_ptr->elements[1]->size);
		NSLog(@"real_return_ptr->elements[1]->type: %d", real_return_ptr->elements[1]->type);
		
		//		NSLog(@"real_args_ptr[0].size: %d", real_args_ptr[0]->size);
		NSLog(@"real_args_ptr[0].type: %d", real_args_ptr[0]->type);
		NSLog(@"real_args_ptr[0]->elements[0]->size: %d", real_args_ptr[0]->elements[0]->size);
		NSLog(@"real_args_ptr[0]->elements[0]->type: %d", real_args_ptr[0]->elements[0]->type);
		NSLog(@"real_args_ptr[0]->elements[1]->size: %d", real_args_ptr[0]->elements[1]->size);
		NSLog(@"real_args_ptr[0]->elements[1]->type: %d", real_args_ptr[0]->elements[1]->type);
		
		NSLog(@"real_args_ptr[1].type: %d", real_args_ptr[1]->type);
		NSLog(@"real_args_ptr[1]->elements[0]->size: %d", real_args_ptr[1]->elements[0]->size);
		NSLog(@"real_args_ptr[1]->elements[0]->type: %d", real_args_ptr[1]->elements[0]->type);
		NSLog(@"real_args_ptr[1]->elements[1]->size: %d", real_args_ptr[1]->elements[1]->size);
		NSLog(@"real_args_ptr[1]->elements[1]->type: %d", real_args_ptr[1]->elements[1]->type);
		
		
	}
	else if([parse_support.keyName isEqualToString:@"NSConvertHostDouble"])
	{
		NSLog(@"NSConvertHostDouble");
		
		//		NSLog(@"real_return_ptr.size: %d", real_return_ptr->size);
		NSLog(@"real_return_ptr.type: %d", real_return_ptr->type);
		
		//		NSLog(@"real_args_ptr[0].size: %d", real_args_ptr[0]->size);
		NSLog(@"real_args_ptr[0].type: %d", real_args_ptr[0]->type);
		NSLog(@"real_args_ptr[0]->elements[0]->size: %d", real_args_ptr[0]->elements[0]->size);
		NSLog(@"real_args_ptr[0]->elements[0]->type: %d", real_args_ptr[0]->elements[0]->type);
		
		
		
	}
	else if([parse_support.keyName isEqualToString:@"NSCreateMapTable"])
	{
		
	}
*/
#endif
	// Prepare the ffi_cif structure.
	ffi_status error_status;
	error_status = ffi_prep_cif(cif_ptr, FFI_DEFAULT_ABI, parse_support.numberOfRealArguments, real_return_ptr, real_args_ptr);
	if(FFI_OK != error_status)
	{
		// Handle the ffi_status error.
		if(FFI_BAD_TYPEDEF == error_status)
		{
			NSLog(@"ffi_prep_cif failed with FFI_BAD_TYPEDEF for function: %@", parse_support.keyName);			
		}
		else if(FFI_BAD_ABI == error_status)
		{
			NSLog(@"ffi_prep_cif failed with FFI_BAD_ABI for function: %@", parse_support.keyName);			
			
		}
		else
		{
			NSLog(@"ffi_prep_cif failed with unknown error for function: %@", parse_support.keyName);			
			
		}
		return 0;
	}
	// for Lua cif and BridgeSupportExtraUserData
	return 2;
	
}

// Argument 1: cif
// Argument 2: bridgesupport extra data
int LuaFunctionBridge_FFICall(lua_State* lua_state)
{
//	NSLog(@"in lua_ffi_call");
	ffi_cif* cif_ptr;
	LuaUserDataContainerForObject* bridge_support_data_container;
	
	const int NUMBER_OF_SUPPORT_ARGS = 2; // To denote that the first 2 arguments are not parameters so things must be shifted
	int number_of_lua_args = lua_gettop(lua_state);
	int number_of_lua_args_for_function = number_of_lua_args - NUMBER_OF_SUPPORT_ARGS;
	//    ffi_type** arg_types;
	//	ffi_type* arg_types[2];
	
	if(number_of_lua_args < NUMBER_OF_SUPPORT_ARGS)
	{
		NSLog(@"Invalid number of arguments for function");
		// lua error? throw exception?
		
		return 0;
	}
	
	// Commented out for performance since function calls may be invoked frequently.
	// I don't really expect the public to use these ffi functions directly.
	//cif_ptr = luaL_checkudata(L, 1, LUACOCOA_FFI_CIF);
	
	cif_ptr = (ffi_cif*)lua_touserdata(lua_state, 1);
	bridge_support_data_container = (LuaUserDataContainerForObject*)lua_touserdata(lua_state, 2);
	ParseSupportFunction* parse_support = bridge_support_data_container->theObject;
	unsigned int number_of_function_args = cif_ptr->nargs;
	
	if(number_of_lua_args_for_function != number_of_function_args)
	{
		NSLog(@"Invalid number of arguments for function");
		// lua error? throw exception?
		return 0;
	}
	
//	NSLog(@"BridgeSupport: name:%@, args:%d", [bridge_support_data_container->theObject itemName], [bridge_support_data_container->theObject numberOfArguments]);
	
	
	
	
// START COPY AND PASTE HERE	
	void* current_arg;
	int i, j;
	
	//	void** array_for_ffi_arguments = alloca(sizeof(void *) * number_of_function_args);
	void* array_for_ffi_arguments[number_of_function_args];
	
	// for out-arguments
	//	void** array_for_ffi_ref_arguments = array_for_ffi_ref_arguments = alloca(sizeof(void *) * number_of_function_args);
	void* array_for_ffi_ref_arguments[number_of_function_args];
// END COPY AND PASTE HERE
	
	
    for (i = 0, j = 1 + NUMBER_OF_SUPPORT_ARGS; i < number_of_function_args; i++, j++)
	{
// START COPY AND PASTE HERE
		unsigned short current_ffi_type = cif_ptr->arg_types[i]->type;
		ParseSupportArgument* current_parse_support_argument = [parse_support.argumentArray objectAtIndex:i];
		
#define putarg(type, val) ((array_for_ffi_arguments[i] = current_arg = alloca(sizeof(type))), *(type *)current_arg = (val))
		switch(current_ffi_type)
		{
			case FFI_TYPE_INT:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(int, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(int, lua_tointeger(lua_state, j));
				}
				break;
			}
			case FFI_TYPE_SINT8:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(int8_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(int8_t, lua_tointeger(lua_state, j));
				}
				break;
			}
			case FFI_TYPE_SINT16:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(int16_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(int16_t, lua_tointeger(lua_state, j));
				}
				break;
			}
			case FFI_TYPE_SINT32:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(int32_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(int32_t, lua_tointeger(lua_state, j));
				}
				break;
			}
			case FFI_TYPE_SINT64:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(int64_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(int64_t, lua_tointeger(lua_state, j));
				}
				break;	
			}
			case FFI_TYPE_UINT8:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(uint8_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(uint8_t, lua_tointeger(lua_state, j));
				}
				break;	
			}
			case FFI_TYPE_UINT16:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(uint16_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(uint16_t, lua_tointeger(lua_state, j));
				}
				break;	
			}
			case FFI_TYPE_UINT32:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(uint32_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(uint32_t, lua_tointeger(lua_state, j));
				}
				break;	
			}
			case FFI_TYPE_UINT64:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(uint64_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(uint64_t, lua_tointeger(lua_state, j));
				}
				break;	
			}
#if FFI_TYPE_LONGDOUBLE != FFI_TYPE_DOUBLE
			case FFI_TYPE_LONGDOUBLE:
				putarg(long double, lua_tonumber(lua_state, j));
				break;
#endif
				
			case FFI_TYPE_DOUBLE:
				putarg(double, lua_tonumber(lua_state, j));
				break;
				
			case FFI_TYPE_FLOAT:
				putarg(float, lua_tonumber(lua_state, j));
				break;
				
			case FFI_TYPE_STRUCT:
				array_for_ffi_arguments[i] = lua_touserdata(lua_state, j);
				break;
				
			case FFI_TYPE_POINTER:
			{
				//			ParseSupportArgument* current_parse_support_argument = [parse_support.argumentArray objectAtIndex:i];
				//			NSLog(@"current_arg.declaredType=%@ objcEncodingType=%@, inOutTypeModifier=%@", current_parse_support_argument.declaredType, current_parse_support_argument.objcEncodingType, current_parse_support_argument.inOutTypeModifier);
				if([current_parse_support_argument.inOutTypeModifier isEqualToString:@"o"] || [current_parse_support_argument.inOutTypeModifier isEqualToString:@"N"] || [current_parse_support_argument.inOutTypeModifier isEqualToString:@"n"])
				{
					
					
					char objc_encoding_type = [current_parse_support_argument.objcEncodingType UTF8String][1];
					
					switch(objc_encoding_type)
					{
						case _C_BOOL:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(int8_t*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(int8_t));
								*((int8_t*)(array_for_ffi_ref_arguments[i])) = lua_toboolean(lua_state, j);
								putarg(int8_t*, (int8_t*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_CHR:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(int8_t*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(int8_t));
								if(lua_isboolean(lua_state, j))
								{
									*((int8_t*)(array_for_ffi_ref_arguments[i])) = lua_toboolean(lua_state, j);
								}
								else
								{
									*((int8_t*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								}
								putarg(int8_t*, (int8_t*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_SHT:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(int16_t*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(int16_t));
								*((int16_t*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(int16_t*, (int16_t*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_INT:
						{    
							if(lua_isnil(lua_state, j))
							{
								putarg(int*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(int));
								if(lua_isboolean(lua_state, j))
								{
									*((int*)(array_for_ffi_ref_arguments[i])) = lua_toboolean(lua_state, j);
								}
								else
								{
									*((int*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								}
								putarg(int*, (int*)&(array_for_ffi_ref_arguments[i]));
							}
							break;			
						}
						case _C_LNG:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(long*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(long));
								if(lua_isboolean(lua_state, j))
								{
									*((long*)(array_for_ffi_ref_arguments[i])) = lua_toboolean(lua_state, j);
								}
								else
								{
									*((long*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								}
								putarg(long*, (long*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_LNG_LNG:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(long long*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(long long));
								*((long long*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(long long*, (long long*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_UCHR:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(uint8_t*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(uint8_t));
								*((uint8_t*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(uint8_t*, (uint8_t*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_USHT:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(uint16_t*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(uint16_t));
								*((uint16_t*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(uint16_t*, (uint16_t*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_UINT:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(unsigned int*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(unsigned int));
								*((unsigned int*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(unsigned int*, (unsigned int*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_ULNG:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(unsigned long*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(unsigned long));
								*((unsigned long*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(unsigned long*, (unsigned long*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_ULNG_LNG:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(unsigned long long*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(unsigned long long));
								*((unsigned long long*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(unsigned long long*, (unsigned long long*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_DBL:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(double*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(double));
								*((double*)(array_for_ffi_ref_arguments[i])) = lua_tonumber(lua_state, j);
								putarg(double*, (double*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_FLT:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(float*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(float));
								*((float*)(array_for_ffi_ref_arguments[i])) = lua_tonumber(lua_state, j);
								putarg(float*, (float*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
							
						case _C_STRUCT_B:
						{
							// Array goes here too
							array_for_ffi_ref_arguments[i] = lua_touserdata(lua_state, j);
							//							array_for_ffi_arguments[i] = lua_touserdata(lua_state, j);
							array_for_ffi_arguments[i] = &array_for_ffi_ref_arguments[i];
							break;
						}
							
						case _C_ID:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(id, nil);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(id));
								if(LuaObjectBridge_isid(lua_state, j))
								{
									// Considering topropertylist, but I don't think the return-by-reference is going to work right
									array_for_ffi_ref_arguments[i] = LuaObjectBridge_toid(lua_state, j);
								}
								else
								{
									array_for_ffi_ref_arguments[i] = nil;
								}
								putarg(id*, (id*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_CLASS:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(id, nil);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(id));
								if(LuaObjectBridge_isid(lua_state, j))
								{
									array_for_ffi_ref_arguments[i] = LuaObjectBridge_toid(lua_state, j);
								}
								else
								{
									array_for_ffi_ref_arguments[i] = nil;
								}
								putarg(id*, (id*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_CHARPTR:
						{
							// I don't expect this to work at all
							if(lua_isnil(lua_state, j))
							{
								putarg(id, nil);
							}
							else
							{
								const char* the_string = lua_tostring(lua_state, j);
								size_t length_of_string = strlen(the_string) + 1; // add one for \0
								
								array_for_ffi_ref_arguments[i] = alloca(sizeof(length_of_string));
								strlcpy(array_for_ffi_ref_arguments[i], the_string, length_of_string);
								putarg(char*, (char*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_SEL:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(SEL, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(SEL));
								if(LuaSelectorBridge_isselector(lua_state, j))
								{
									array_for_ffi_ref_arguments[i] = LuaSelectorBridge_toselector(lua_state, j);
								}
								else
								{
									array_for_ffi_ref_arguments[i] = nil;
								}
								putarg(SEL*, (SEL*)&(array_for_ffi_ref_arguments[i]));						
							}
							break;
						}
							
						case _C_PTR:
						default:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(id, nil);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(void*));
								if(LuaSelectorBridge_isselector(lua_state, j))
								{
									array_for_ffi_ref_arguments[i] = lua_touserdata(lua_state, j);
								}
								else
								{
									array_for_ffi_ref_arguments[i] = nil;
								}
								putarg(void**, (void**)&(array_for_ffi_ref_arguments[i]));						
							}
							break;
						}
					}
					
				}
				else
				{
					char objc_encoding_type = [current_parse_support_argument.objcEncodingType UTF8String][0];
					
					switch(objc_encoding_type)
					{
						case _C_ID:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(id, nil);
							}
							else
							{
								// Will auto-coerce numbers, strings, tables to Cocoa objects
								id the_object = LuaObjectBridge_topropertylist(lua_state, j);			
								putarg(id, the_object);
							}
							break;
						}
						case _C_CLASS:
						{
							Class the_object = LuaObjectBridge_toid(lua_state, j);			
							putarg(Class, the_object);
							break;
						}
						case _C_CHARPTR:
						{
							if(lua_isstring(lua_state, j))
							{
								putarg(const char*, lua_tostring(lua_state, j));
							}
							else if(LuaObjectBridge_isnsstring(lua_state, j))
							{
								putarg(const char*, [LuaObjectBridge_tonsstring(lua_state, j) UTF8String]);								
							}
							else
							{
								putarg(const char*, NULL);
							}
							break;
						}
						case _C_SEL:
						{
							putarg(SEL, LuaSelectorBridge_toselector(lua_state, j));
							break;
						}
						
						case _C_PTR:
						default:
						{
							putarg(void*, lua_touserdata(lua_state, j));
						}
					}
				}
				break;
			}
		}
#       undef putarg
		// END COPY AND PASTE HERE
    }
	
	bool is_void_return = false;
	if(FFI_TYPE_VOID == cif_ptr->rtype->type)
	{
		is_void_return = true;
	}
	
	// if needed
	int stack_index_for_struct_return_value = 0;
	void* return_value = NULL;
	if(false == is_void_return)
	{
		if(FFI_TYPE_STRUCT == cif_ptr->rtype->type)
		{
			return_value = lua_newuserdata(lua_state, cif_ptr->rtype->size);
			stack_index_for_struct_return_value = lua_gettop(lua_state);
			
			// set correct struct metatable on new userdata
			NSString* return_struct_type_name = parse_support.returnValue.objcEncodingType;
			
			// set correct struct metatable on new userdata
			
			NSString* struct_struct_name = ParseSupport_StructureReturnNameFromReturnTypeEncoding(return_struct_type_name);
			
			NSString* struct_keyname = [ParseSupportStruct keyNameFromStructName:struct_struct_name];
			LuaStructBridge_SetStructMetatableOnUserdata(lua_state, stack_index_for_struct_return_value, struct_keyname, struct_struct_name);
		}
		else
		{
			// rvalue must point to storage that is sizeof(long) or larger. For smaller return value sizes, 
			// the ffi_arg or ffi_sarg integral type must be used to hold the return value.
			// But as far as I can tell, cif_ptr->rtype->size already has the correct size for this case.
			return_value = alloca(cif_ptr->rtype->size);
		}
	}	

	// Call the function
	ffi_call(cif_ptr, FFI_FN([parse_support dlsymFunctionPointer]), return_value, array_for_ffi_arguments);

	int number_of_return_values = 0;
	
	
	if(false == is_void_return)
	{
		if(parse_support.returnValue.isAlreadyRetained)
		{
			// We likely called a function like CF*Create().
			// Push, but don't increment the retain count. 
			// We must release the retain count by one
			// I assume the function used a CFRetain() to hold the object.
			// (I only see the already_retained marker in the CoreFoundation XML.)
			// Tell the push function not to retain. We will use this retain towards our bridge count
			number_of_return_values += LuaFFISupport_PushReturnValue(lua_state, return_value, cif_ptr->rtype, parse_support.returnValue, stack_index_for_struct_return_value, false, false);
			LuaUserDataContainerForObject* the_container = lua_touserdata(lua_state, -1);
			the_container->needsRelease = true;
		}
		else
		{
			number_of_return_values += LuaFFISupport_PushReturnValue(lua_state, return_value, cif_ptr->rtype, parse_support.returnValue, stack_index_for_struct_return_value, true, false);			
		}
	}
	
	// Now traverse out arguments and see which we need to return
	size_t argument_index = 0;
	for(ParseSupportArgument* current_parse_support_argument in parse_support.argumentArray)
	{
		// check for out or inout arguments
		if([current_parse_support_argument.inOutTypeModifier isEqualToString:@"o"] || [current_parse_support_argument.inOutTypeModifier isEqualToString:@"N"])
		{
			int stack_index_for_argument = argument_index + NUMBER_OF_SUPPORT_ARGS + 1; // shift for support arguments, add 1 for lua index starts at 0
			number_of_return_values += LuaFFISupport_PushReturnValue(lua_state, array_for_ffi_arguments[argument_index], cif_ptr->arg_types[argument_index], current_parse_support_argument, stack_index_for_argument, true, true);
		}
		argument_index++;
	}
	
	return number_of_return_values;
}



static const luaL_reg LuaFunctionBridge_LuaFunctions[] = 
{
	{"ffi_prep_cif", LuaFunctionBridge_FFIPrepCif},
	{"ffi_call", LuaFunctionBridge_FFICall},

	{NULL,NULL},
};

int luaopen_LuaFunctionBridge(lua_State* state)
{
	luaL_newmetatable(state, LUACOCOA_FFI_CIF);
	//	lua_pushvalue(state, -1);
	//	lua_setfield(state, -2, "__index");
	//	luaL_register(state, NULL, methods_for_cgpoint);
	
	luaL_newmetatable(state, LUACOCOA_BRIDGESUPPORT_EXTRA_DATA);
	luaL_register(state, NULL, methods_for_BridgeSupportExtraData);
	
    luaL_register(state, "LuaCocoa", LuaFunctionBridge_LuaFunctions);
	return 1;
}

