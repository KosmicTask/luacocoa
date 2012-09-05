//
//  LuaObjectBridge.m
//  LuaCocoa
//
//  Created by Eric Wing on 10/22/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "LuaObjectBridge.h"
#import <objc/objc.h>
#import <objc/runtime.h>
#import <objc/message.h>

#include "lua.h"
#include "lauxlib.h"
#include <ffi/ffi.h>
#include "LuaFFISupport.h"
#import "ObjectSupport.h"
#import "ParseSupport.h"
#import "ParseSupportMethod.h"
#import "ParseSupportStruct.h"
#import "LuaStructBridge.h"
#import "LuaSelectorBridge.h"
#import "LuaSubclassBridge.h" // special hack for init 
#import "LuaBlockBridge.h"
#import "NSStringHelperFunctions.h"
#include "LuaCocoaWeakTable.h"
#include "LuaCocoaStrongTable.h"



// Experiment to try to create new intermediate containers to pass along superClass informatation
// This violates my 1 to 1 assumption (even more than before) about ids to userdata.
// There also may be other complicated side effects including memory management.
// This also might just not work. (I'm worried the information could become stale/wrong).
// Basically it works by progating a ->superClass on detection of a super() call.
// As it stands, after a super call, I must tear down the super status if I am about to call a lua defined super method.
// At this point, this hack copies the superClass as additional information even though the super status is no longer true.
// Update: Right now, this code path is actually better tested and trusted than with it disabled.
// The ideas have been blurred between the two paths from the original concept because neither worked particularly well.
// Both paths now have a ->superClass variable that gets passed around.
#define LUA_COCOA_USE_INTERMEDIATE_OBJECTS_TO_HOLD_SUPERCLASS

const char* LUACOCOA_OBJECT_METATABLE_ID = "LuaCocoa.Object";

// Forward declarations
static int LuaObjectBridge_InvokeMethod(lua_State* lua_state);
static void LuaObjectBridge_CreateUserData(lua_State* lua_state, id the_object, bool should_retain, bool is_instance, bool is_super);
static void LuaObjectBridge_PushOrCreateUserData(lua_State* lua_state, id the_object, bool should_retain, bool is_instance, bool is_super);


// returns pointer if LuaCocoa.Object, lua_error otherwise
LuaUserDataContainerForObject* LuaObjectBridge_LuaCheckClass(lua_State* lua_state, int stack_index)
{
	return luaL_checkudata(lua_state, stack_index, LUACOCOA_OBJECT_METATABLE_ID);
}


// returns pointer if a LuaCocoa.Object, null otherwise
static LuaUserDataContainerForObject* LuaObjectBridge_LuaIsClass(lua_State *L, int stack_index)
{
	void *p = lua_touserdata(L, stack_index);
	if (p != NULL) {  /* value is a userdata? */
		if (lua_getmetatable(L, stack_index))
		{  /* does it have a metatable? */
			lua_getfield(L, LUA_REGISTRYINDEX, LUACOCOA_OBJECT_METATABLE_ID);  /* get correct metatable */
			if (lua_rawequal(L, -1, -2)) {  /* does it have the correct mt? */
				lua_pop(L, 2);  /* remove both metatables */
				return p;
			}
			else
			{
				lua_pop(L, 1); /* pop getfield */
			}
		}
		lua_pop(L, 1); /* pop metatable */
	}
	return NULL;  /* to avoid warnings */
}

bool LuaObjectBridge_IsInstance(LuaUserDataContainerForObject* object_container)
{
	return object_container->isInstance;
}

bool LuaObjectBridge_IsClass(LuaUserDataContainerForObject* object_container)
{
	return !object_container->isInstance;
}

bool LuaObjectBridge_IsLuaSubclass(LuaUserDataContainerForObject* object_container)
{
//	return object_container->isLuaSubclass;
	if(LuaObjectBridge_IsInstance(object_container))
	{
		return LuaSubclassBridge_IsObjectSubclassInLua(object_container->theObject);
	}
	else
	{
		return LuaSubclassBridge_IsClassSubclassInLua(object_container->theObject);
	}
}

bool LuaObjectBridge_IsSuper(LuaUserDataContainerForObject* object_container)
{
	return object_container->isSuper;
}

// Will return super class if marked as super
Class LuaObjectBridge_GetClass(LuaUserDataContainerForObject* object_container)
{
	Class the_class;
	if(LuaObjectBridge_IsSuper(object_container))
	{
		if(NULL == object_container->superClass)
		{
			if(LuaObjectBridge_IsInstance(object_container))
			{
				the_class = ObjectSupport_GetSuperClassFromObject(object_container->theObject);
			}
			else
			{
				the_class = ObjectSupport_GetSuperClassFromClass(object_container->theObject);			
			}
		}
		else
		{
			the_class = object_container->superClass;
		}

	}
	else
	{
#if !defined(LUA_COCOA_USE_INTERMEDIATE_OBJECTS_TO_HOLD_SUPERCLASS)
		// FIXME: Not sure this is correct any more with all the changes involving super.
		// Might need to look more like the else case which checks for ->superClass and isSuperClass
		if(LuaObjectBridge_IsInstance(object_container))
		{
			the_class = ObjectSupport_GetClassFromObject(object_container->theObject);
		}
		else
		{
			the_class = ObjectSupport_GetClassFromClass(object_container->theObject);			
		}
#else // experiment to try to create new intermediate containers to pass along superClass informatation

		if(NULL == object_container->superClass)
		{
			if(LuaObjectBridge_IsInstance(object_container))
			{
				the_class = ObjectSupport_GetClassFromObject(object_container->theObject);
			}
			else
			{
				the_class = ObjectSupport_GetClassFromClass(object_container->theObject);			
			}
		}
		else
		{
			the_class = object_container->superClass;
		}
#endif
	}
	return the_class;
}

id LuaObjectBridge_checkid(lua_State* lua_state, int stack_index)
{
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaCheckClass(lua_state, stack_index);
	return the_container->theObject;
}

bool LuaObjectBridge_isid(lua_State* lua_state, int stack_index)
{
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		return false;
	}
	else
	{
		return true;
	}
}

bool LuaObjectBridge_isidclass(lua_State* lua_state, int stack_index)
{
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		return false;
	}
	return LuaObjectBridge_IsClass(the_container);
}

bool LuaObjectBridge_isidinstance(lua_State* lua_state, int stack_index)
{
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		return false;
	}
	return LuaObjectBridge_IsInstance(the_container);
}


id LuaObjectBridge_toid(lua_State* lua_state, int stack_index)
{
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		return nil;
	}
	return the_container->theObject;
}

// will return true for integers, floats, booleans, and NSNumbers
bool LuaObjectBridge_isnsnumber(lua_State* lua_state, int stack_index)
{
	if(lua_isboolean(lua_state, stack_index))
	{
		return true;
	}
	else if(lua_isnumber(lua_state, stack_index))
	{
		return true;
	}
	// Fall through. Last resort is a userdata NSNumber
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		return false;
	}
	if(!LuaObjectBridge_IsInstance(the_container))
	{
		return false;
	}
	if([the_container->theObject isKindOfClass:[NSNumber class]])
	{
		return true;
	}
	return false;
}

NSNumber* LuaObjectBridge_checknsnumber(lua_State* lua_state, int stack_index)
{
	if(lua_isboolean(lua_state, stack_index))
	{
		return [NSNumber numberWithBool:lua_toboolean(lua_state, stack_index)];
	}
	else if(lua_isinteger(lua_state, stack_index))
	{
		return [NSNumber numberWithInteger:lua_tointeger(lua_state, stack_index)];
	}
	else if(lua_isnumber(lua_state, stack_index))
	{
		return [NSNumber numberWithDouble:lua_tonumber(lua_state, stack_index)];
	}
	// Fall through. Last resort is a userdata NSNumber
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		luaL_typerror(lua_state, stack_index, LUACOCOA_OBJECT_METATABLE_ID);
		return nil; // make compiler happy
	}
	if(!LuaObjectBridge_IsInstance(the_container))
	{
		luaL_error(lua_state, "Not an instance type");
		return nil; // make compiler happy
	}

	if([the_container->theObject isKindOfClass:[NSNumber class]])
	{
		return [[the_container->theObject retain] autorelease];
	}
	else
	{
		luaL_error(lua_state, "Object is not a NSNumber class");		
		return nil; // make compiler happy
	}
	return nil; // make compiler happy
}

NSNumber* LuaObjectBridge_tonsnumber(lua_State* lua_state, int stack_index)
{
	if(lua_isboolean(lua_state, stack_index))
	{
		return [NSNumber numberWithBool:lua_toboolean(lua_state, stack_index)];
	}
	else if(lua_isinteger(lua_state, stack_index))
	{
		return [NSNumber numberWithInteger:lua_tointeger(lua_state, stack_index)];
	}
	else if(lua_isnumber(lua_state, stack_index))
	{
		return [NSNumber numberWithDouble:lua_tonumber(lua_state, stack_index)];
	}
	// Fall through. Last resort is a userdata NSNumber
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		return nil;
	}
	if(!LuaObjectBridge_IsInstance(the_container))
	{
		return nil;
	}
	
	if([the_container->theObject isKindOfClass:[NSNumber class]])
	{
		return [[the_container->theObject retain] autorelease];
	}
	else
	{
		return nil;
	}
}

// Pushes a Lua number converted from an NSNumber onto the stack.
// Note that if the NSNumber is a boolean, it will push a Lua boolean instead.
// On failure, nil is pushed.
void LuaObjectBridge_pushunboxednsnumber(lua_State* lua_state, NSNumber* the_number)
{
	lua_checkstack(lua_state, 1);
	if(nil == the_number)
	{
		lua_pushnil(lua_state);
	}
	const char* objc_type = [the_number objCType];
	switch(objc_type[0])
	{
		case _C_BOOL:
		{
			lua_pushboolean(lua_state, [the_number boolValue]);		
			break;
		}
		case _C_CHR:
		case _C_UCHR:
		{
			// booleans in NSNumber are returning 'c' as the type and not 'B'.
			// The class type is NSCFBoolean, but I've read it is a private class so I don't want to reference it directly.
			// So I'll create an instance of it and compare to it.
			// (I've read it is a singleton.)
			if([[NSNumber numberWithBool:YES] class] == [the_number class])
			{
				lua_pushboolean(lua_state, [the_number boolValue]);		
			}
			else
			{
				lua_pushinteger(lua_state, (lua_Integer)[the_number integerValue]);		
			}
			break;
		}
		case _C_SHT:
		case _C_USHT:
		case _C_INT:
		case _C_UINT:
		case _C_LNG:
		case _C_ULNG:
		case _C_LNG_LNG:
		case _C_ULNG_LNG:
		{
			lua_pushinteger(lua_state, (lua_Integer)[the_number integerValue]);		
			break;
		}
		case _C_FLT:
		case _C_DBL:
		default:
		{
			lua_pushinteger(lua_state, (lua_Number)[the_number doubleValue]);		
			break;			
		}
	}
}


// will return true for nil, NSNull
bool LuaObjectBridge_isnsnull(lua_State* lua_state, int stack_index)
{
	if(lua_isnil(lua_state, stack_index))
	{
		return true;
	}
	// Fall through. Last resort is a userdata NSNull
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		return false;
	}
	if(!LuaObjectBridge_IsInstance(the_container))
	{
		return false;
	}
	if([the_container->theObject isKindOfClass:[NSNull class]])
	{
		return true;
	}
	return false;
}

NSNull* LuaObjectBridge_checknsnull(lua_State* lua_state, int stack_index)
{
	if(lua_isnil(lua_state, stack_index))
	{
		return [NSNull null];
	}

	// Fall through. Last resort is a userdata NSNull
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		luaL_typerror(lua_state, stack_index, LUACOCOA_OBJECT_METATABLE_ID);
		return nil; // make compiler happy
	}
	if(!LuaObjectBridge_IsInstance(the_container))
	{
		luaL_error(lua_state, "Not an instance type");
		return nil; // make compiler happy
	}
	
	if([the_container->theObject isKindOfClass:[NSNull class]])
	{
		return the_container->theObject;
	}
	else
	{
		luaL_error(lua_state, "Object is not a NSNull class");		
		return nil; // make compiler happy
	}
}

NSNull* LuaObjectBridge_tonsnull(lua_State* lua_state, int stack_index)
{
	if(lua_isnil(lua_state, stack_index))
	{
		return [NSNull null];
	}

	// Fall through. Last resort is a userdata NSNull
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		return nil;
	}
	if(!LuaObjectBridge_IsInstance(the_container))
	{
		return nil;
	}
	
	if([the_container->theObject isKindOfClass:[NSNull class]])
	{
		return the_container->theObject;
	}
	else
	{
		return nil;
	}
}

// will return true for strings, numbers (which is always convertible to a string) and NSString
bool LuaObjectBridge_isnsstring(lua_State* lua_state, int stack_index)
{
	if(lua_isstring(lua_state, stack_index))
	{
		return true;
	}

	// Fall through. Last resort is a userdata NSString
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		return false;
	}
	if(!LuaObjectBridge_IsInstance(the_container))
	{
		return false;
	}
	if([the_container->theObject isKindOfClass:[NSString class]])
	{
		return true;
	}
	return false;
}

// Does not copy string
NSString* LuaObjectBridge_checknsstring(lua_State* lua_state, int stack_index)
{
	if(lua_isstring(lua_state, stack_index))
	{
		return [NSString stringWithUTF8String:lua_tostring(lua_state, stack_index)];
	}

	// Fall through. Last resort is a userdata NSString
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		luaL_typerror(lua_state, stack_index, LUACOCOA_OBJECT_METATABLE_ID);
		return nil; // make compiler happy
	}
	if(!LuaObjectBridge_IsInstance(the_container))
	{
		luaL_error(lua_state, "Not an instance type");
		return nil; // make compiler happy
	}
	
	if([the_container->theObject isKindOfClass:[NSString class]])
	{
		// should I copy?
		return [[the_container->theObject retain] autorelease];
	}
	else
	{
		luaL_error(lua_state, "Object is not a NSString class");		
		return nil; // make compiler happy
	}
	return nil; // make compiler happy
}
// Does not copy string
NSString* LuaObjectBridge_tonsstring(lua_State* lua_state, int stack_index)
{
	if(lua_isstring(lua_state, stack_index))
	{
		return [NSString stringWithUTF8String:lua_tostring(lua_state, stack_index)];
	}
	
	// Fall through. Last resort is a userdata NSString
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		return nil;
	}
	if(!LuaObjectBridge_IsInstance(the_container))
	{
		return nil;
	}
	
	if([the_container->theObject isKindOfClass:[NSString class]])
	{
		// should I copy?
		return [[the_container->theObject retain] autorelease];
	}
	else
	{
		return nil;
	}
}

void LuaObjectBridge_pushunboxednsstring(lua_State* lua_state, NSString* the_string)
{
	lua_checkstack(lua_state, 1);
	if(nil == the_string)
	{
		lua_pushnil(lua_state);
	}
	else if([the_string length] == 0)
	{
		lua_pushnil(lua_state);		
	}
	else
	{
		lua_pushstring(lua_state, [the_string UTF8String]);
	}
}

// If NSString, returns C-string. Does not copy string
// If string, returns string
__strong const char* LuaObjectBridge_tostring(lua_State* lua_state, int stack_index)
{
	if(lua_isstring(lua_state, stack_index))
	{
		return lua_tostring(lua_state, stack_index);
	}
	
	// Fall through. Last resort is a userdata NSString
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		return nil;
	}
	if(!LuaObjectBridge_IsInstance(the_container))
	{
		return nil;
	}
	
	if([the_container->theObject isKindOfClass:[NSString class]])
	{
		// should I copy?
		return [(NSString*)the_container->theObject UTF8String];
	}
	else
	{
		return NULL;
	}
}



// will return true for tables, NSArray
bool LuaObjectBridge_isnsarray(lua_State* lua_state, int stack_index)
{
	if(lua_istable(lua_state, stack_index))
	{
		bool is_array = true;
		size_t item_count = 0;
		lua_pushnil(lua_state);  /* first key */
		while (lua_next(lua_state, stack_index) != 0)
		{
			item_count++;
			if(LUA_TNUMBER == lua_type(lua_state, -2) && (lua_tointeger(lua_state, -2) == item_count))
			{
				lua_pop(lua_state, 1);
			}
			else
			{
				is_array = false;
				lua_pop(lua_state, 2); // need to pop 1 extra because I won't be calling lua_next again which pops 1
				break;
			}
		}
		return is_array;
	}

	// Fall through. Last resort is a userdata NSArray
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		return false;
	}
	if(!LuaObjectBridge_IsInstance(the_container))
	{
		return false;
	}
	if([the_container->theObject isKindOfClass:[NSArray class]])
	{
		return true;
	}
	return false;
}

#if 0
NSNumber* LuaObjectBridge_checknsarray(lua_State* lua_state, int stack_index)
{
	if(lua_istable(lua_state, stack_index))
	{
		bool is_array = true;
		size_t item_count = 0;
		lua_pushnil(lua_state);  /* first key */
		while (lua_next(lua_state, stack_index) != 0)
		{
			item_count++;
			if(LUA_TNUMBER == lua_type(lua_state, -2) && (lua_tointeger(lua_state, -2) == item_count))
			{
				lua_pop(lua_state, 1);
			}
			else
			{
				is_array = false;
				lua_pop(lua_state, 2); // need to pop 1 extra because I won't be calling lua_next again which pops 1
				break;
			}
		}
		return is_array;

	}

	// Fall through. Last resort is a userdata NSArray
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		return luaL_typerror(lua_state, stack_index,, LUACOCOA_OBJECT_METATABLE_ID);
	}
	if(!LuaObjectBridge_IsInstance(the_container))
	{
		return luaL_error(lua_state, "Not an instance type");
	}
	
	if([the_container->theObject isKindOfClass:[NSArray class]])
	{
		return [[the_container->theObject retain] autorelease];
	}
	else
	{
		return luaL_error(lua_state, "Object is not a NSArray class");		
	}
}

NSArray* LuaObjectBridge_tonsarray(lua_State* lua_state, int stack_index)
{
	if(lua_isboolean(lua_state, stack_index))
	{
		return [NSNumber numberWithBool:lua_toboolean(lua_state, stack_index)];
	}
	else if(lua_isinteger(lua_state, stack_index))
	{
		return [NSNumber numberWithInteger:lua_tointeger(lua_state, stack_index)];
	}
	else if(lua_isnumber(lua_state, stack_index))
	{
		return [NSNumber numberWithDouble:lua_tonumber(lua_state, stack_index)];
	}
	// Fall through. Last resort is a userdata NSArray
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		return nil;
	}
	if(!LuaObjectBridge_IsInstance(the_container))
	{
		return nil;
	}
	
	if([the_container->theObject isKindOfClass:[NSArray class]])
	{
		return [[the_container->theObject retain] autorelease];
	}
	else
	{
		return nil;
	}
}
#endif

void LuaObjectBridge_pushunboxednsarray(lua_State* lua_state, NSArray* the_array)
{
	if([the_array isKindOfClass:[NSArray class]])
	{
		lua_checkstack(lua_state, 3); // is it really 3? table+key+value?
		lua_newtable(lua_state);
		int table_index = lua_gettop(lua_state);
		int current_lua_array_index = 1;
		for(id an_element in the_array)
		{
			// recursively add elements
			LuaObjectBridge_pushunboxedpropertylist(lua_state, an_element);
			lua_rawseti(lua_state, table_index, current_lua_array_index);
			current_lua_array_index++;
		}
	}
	else
	{
		lua_checkstack(lua_state, 1);
		lua_pushnil(lua_state);
	}
	
}

// will return true for tables, NSDictionary
bool LuaObjectBridge_isnsdictionary(lua_State* lua_state, int stack_index)
{
	if(lua_istable(lua_state, stack_index))
	{
		return true;
	}
	
	// Fall through. Last resort is a userdata NSDictionary
	LuaUserDataContainerForObject* the_container = LuaObjectBridge_LuaIsClass(lua_state, stack_index);
	if(NULL == the_container)
	{
		return false;
	}
	if(!LuaObjectBridge_IsInstance(the_container))
	{
		return false;
	}
	if([the_container->theObject isKindOfClass:[NSDictionary class]])
	{
		return true;
	}
	return false;
}



void LuaObjectBridge_pushunboxednsdictionary(lua_State* lua_state, NSDictionary* the_dictionary)
{
	if([the_dictionary isKindOfClass:[NSDictionary class]])
	{
		lua_checkstack(lua_state, 3); // is it really 3? table+key+value?
		lua_newtable(lua_state);
		int table_index = lua_gettop(lua_state);
		for(id a_key in the_dictionary)
		{
			// recursively add elements
			LuaObjectBridge_pushunboxedpropertylist(lua_state, a_key); // push key
			LuaObjectBridge_pushunboxedpropertylist(lua_state, [the_dictionary valueForKey:a_key]); // push value
			lua_rawset(lua_state, table_index);
		}
	}
	else
	{
		lua_checkstack(lua_state, 1);
		lua_pushnil(lua_state);
	}
	
}


bool LuaObjectBridge_ispropertylist(lua_State* lua_state, int stack_index)
{
	if(LuaObjectBridge_isnsnumber(lua_state, stack_index))
	{
		return true;
	}
	else if(LuaObjectBridge_isnsnull(lua_state, stack_index))
	{
		return true;
	}
	else if(LuaObjectBridge_isnsstring(lua_state, stack_index))
	{
		return true;
	}
	else if(LuaObjectBridge_isnsdictionary(lua_state, stack_index))
	{
		return true;
	}
	// do array last since it is the most expensive to detect
	else if(LuaObjectBridge_isnsarray(lua_state, stack_index))
	{
		return true;
	}
	else
	{
		return false;
	}
}

// Will never return nil. Instead, returns NSNull for unhandled object.
id LuaObjectBridge_topropertylistornsnull(lua_State* lua_state, int stack_index)
{
	id return_id = LuaObjectBridge_topropertylist(lua_state, stack_index);
	if(nil == return_id)
	{
		return [NSNull null];
	}
	else
	{
		return return_id;
	}
}


// This will allow recursion to work for nested arrays and dictionaries.
id LuaObjectBridge_topropertylist(lua_State* lua_state, int stack_index)
{
	if(stack_index < 0)
	{
		// convert stack index to absolute position
		stack_index = lua_gettop(lua_state)+(stack_index+1);
	}
	
	switch(lua_type(lua_state, stack_index))
	{
		case LUA_TUSERDATA:
		{
			NSString* key_name = nil;
			if(LuaObjectBridge_isid(lua_state, stack_index))
			{
				return LuaObjectBridge_toid(lua_state, stack_index);				
			}
			// do this after id check because NSString should be left as a string
			else if(LuaSelectorBridge_isselector(lua_state, stack_index))
			{
				// Need to box selector into NSValue
				SEL the_selector = LuaSelectorBridge_toselector(lua_state, stack_index);
				NSValue* selector_value_box = [NSValue valueWithBytes:&the_selector objCType:@encode(SEL)];
				return selector_value_box;
			}
//			else if(LuaStructBridge_isstruct(lua_state, stack_index))
			else if((key_name = LuaStructBridge_GetBridgeKeyNameFromMetatable(lua_state, stack_index)))
			{
				NSString* objc_type = ParseSupport_ObjcTypeFromKeyName(key_name);

				// Need to box selector into NSValue
				void* the_struct = lua_touserdata(lua_state, stack_index);
				NSValue* struct_value_box = [NSValue valueWithBytes:the_struct objCType:[NSStringHelperFunctions_StripQuotedCharacters(objc_type) UTF8String]];
				return struct_value_box;
			}
			else
			{
				NSLog(@"Unknown LUA_TUSERDATA in LuaObjectBridge_topropertylist");
				return nil;	
			}
		}
		case LUA_TBOOLEAN:
		case LUA_TNUMBER:
		{
			return LuaObjectBridge_tonsnumber(lua_state, stack_index);
		}
		case LUA_TSTRING:
		{
			return LuaObjectBridge_tonsstring(lua_state, stack_index);
		}
		case LUA_TTABLE:
		{
			bool is_array = true;
			NSMutableArray* array_of_keys = [NSMutableArray array];
			NSMutableArray* array_of_values = [NSMutableArray array];
			NSUInteger item_count = 0;

			lua_pushnil(lua_state);  /* first key */
			// notice that stack_index may need to be absolute since it pushes new values
			while(lua_next(lua_state, stack_index) != 0)
			{
//				int top0 = lua_gettop(lua_state);

				item_count++;
				if(true == is_array)
				{
					if(LUA_TNUMBER == lua_type(lua_state, -2) && (lua_tointeger(lua_state, -2) == item_count))
					{
						// still an array
					}
					else
					{
						is_array = false;
					}
				}
//				int top2 = lua_gettop(lua_state);

				// Add keys and values to intermediate storage arrays so we can assemble the final return value later
				[array_of_keys addObject:LuaObjectBridge_topropertylistornsnull(lua_state, -2)];
//				int top3 = lua_gettop(lua_state);

				[array_of_values addObject:LuaObjectBridge_topropertylistornsnull(lua_state, -1)];
//				int top1 = lua_gettop(lua_state);
//				assert(top0 == top1);

				lua_pop(lua_state, 1);
			}

			if(true == is_array)
			{
				return array_of_values;
			}
			else
			{
				return [NSMutableDictionary dictionaryWithObjects:array_of_values forKeys:array_of_keys];
			}
		}
		case LUA_TNIL:
		{
			return [NSNull null];
//			return nil;
		}
		// can we improve these?
		case LUA_TFUNCTION:
		{
#if NS_BLOCKS_AVAILABLE
			// Blocks!
			// In this case, we have a raw Lua function that is not already boxed in a id/block.
			// We need to create a block to wrap the the Lua function.
			// Things to be aware of:
			// We must keep a reference to the Lua function so it doesn't get collected.
			// I'm not sure if the block should be copied. For safety, copying will avoid potential problems at the trade off of speed.
			
#else
			return nil;
#endif
			
		}
		case LUA_TTHREAD:
		case LUA_TLIGHTUSERDATA:
		default:
		{
			return nil;
		}
	}
}

void LuaObjectBridge_pushunboxedpropertylist(lua_State* lua_state, id the_object)
{
	if(nil == the_object)
	{
		lua_checkstack(lua_state, 1);
		lua_pushnil(lua_state);
	}
	if([the_object isKindOfClass:[NSNull class]])
	{
		lua_checkstack(lua_state, 1);
		lua_pushnil(lua_state);
	}
	else if([the_object isKindOfClass:[NSNumber class]])
	{
		LuaObjectBridge_pushunboxednsnumber(lua_state, the_object);
	}
	else if([the_object isKindOfClass:[NSString class]])
	{
		LuaObjectBridge_pushunboxednsstring(lua_state, the_object);
	}
	else if([the_object isKindOfClass:[NSArray class]])
	{
		LuaObjectBridge_pushunboxednsarray(lua_state, the_object);
	}
	else if([the_object isKindOfClass:[NSDictionary class]])
	{
		LuaObjectBridge_pushunboxednsdictionary(lua_state, the_object);
	}
	else if([the_object isKindOfClass:[NSValue class]] && ObjectSupport_IsInstance(the_object) && !strcmp([the_object objCType], @encode(SEL)))
	{
		SEL return_selector;
		[the_object getValue:&return_selector];
		lua_pushstring(lua_state, [NSStringFromSelector(return_selector) UTF8String]);
	}
	else if([the_object isKindOfClass:NSClassFromString(@"NSBlock")])
	{
		// If the block was created from Lua, we can return the original Lua function.
		// This function will either push the Lua function on the stack or push nil.
		LuaCocoaWeakTable_GetLuaFunctionForBlockInGlobalWeakTable(lua_state, the_object);
	}
	else
	{
		lua_checkstack(lua_state, 1);
		lua_pushnil(lua_state);
	}
}

static int LuaObjectBridge_ToString(lua_State* lua_state)
{
	LuaUserDataContainerForObject* lua_class_container = LuaObjectBridge_LuaCheckClass(lua_state, -1);
	// Special exception for NSString. Just return its string.

	if(LuaObjectBridge_IsClass(lua_class_container))
	{
//		NSLog(@"found a class");
		NSString* output_string = [NSString stringWithFormat:@"Class: %s <0x%x>", object_getClassName(lua_class_container->theObject), lua_class_container->theObject];
		lua_pushstring(lua_state, [output_string UTF8String]);		

	}
	// NSPlaceholderString is giving me a lot of problems with debugging so I'm adding this case here.
	// Once things are stable, we can remove this case.
	else if([lua_class_container->theObject isKindOfClass:NSClassFromString(@"NSPlaceholderString")])
	{
//		NSLog(@"isKindOfClass:NSPlaceholderString");
		lua_pushstring(lua_state, [[NSString stringWithFormat:@"NSPlaceholderString: <0x%x>", lua_class_container->theObject] UTF8String]);

	}
	else if([lua_class_container->theObject isKindOfClass:[NSString class]])
	{
//		NSLog(@"isKindOfClass:NSString");
		lua_pushstring(lua_state, [(NSString*)lua_class_container->theObject UTF8String]);
	}
	else
	{
//		NSLog(@"found an instance");
//		NSLog(@"printing description");
		
//		NSString* output_string = [NSString stringWithFormat:@"Class: %s <0x%x>", object_getClassName(lua_class_container->theObject), lua_class_container];
		NSString* output_string = [lua_class_container->theObject description];
		lua_pushstring(lua_state, [output_string UTF8String]);		
	}


	// Lua's fstring doesn't handle %x
//	lua_pushfstring(lua_state, "Class: %s <0x%x>", object_getClassName(lua_class_container->theClass), lua_class_container);
	return 1;
}


static int LuaObjectBridge_ToNumber(lua_State* lua_state)
{
	// NSObject provides respondsToSelector
	LuaUserDataContainerForObject* lua_class_container = LuaObjectBridge_LuaCheckClass(lua_state, -1);

	id the_object = lua_class_container->theObject;

	if(LuaObjectBridge_IsInstance(lua_class_container))
	{
		if([the_object isKindOfClass:[NSNumber class]])
		{
			lua_pushnumber(lua_state, [(NSNumber*)the_object doubleValue]);
		}
		else if([the_object isKindOfClass:[NSString class]])
		{
			lua_pushnumber(lua_state, [(NSString*)the_object doubleValue]);
		}
		/* I'm not sure if I want to support this. It is also causing compiler errors with Clang because
		 * obj-c assumes an id return, not double, and doesn't want to cast a pointer to double.
		else if([the_object respondsToSelector:@selector(doubleValue)])
		{
			lua_pushnumber(lua_state, (lua_Number)[the_object doubleValue]);			
		}
		*/
	}
	else
	{
		lua_pushnil(lua_state);
	}

	return 1;
}


static int LuaObjectBridge_IsEqual(lua_State* lua_state)
{
	// FIXME: Should we auto-coerce by using topropertylist?
	id the_object1 = LuaObjectBridge_checkid(lua_state, 1);
	id the_object2 = LuaObjectBridge_checkid(lua_state, 2);
	
	// FIXME: The proper way to do this is use BridgeSupport to look up the classes and see
	// if they have a method named isEqualTo<ClassName>: and run it if they have it.
	// One complication is if the classes are not the same type. Another complication is
	// if one class is a subclass of another (I'll have to figure out order.)
	if(ObjectSupport_IsInstance(the_object1) && ObjectSupport_IsInstance(the_object2))
	{
		if([the_object1 isKindOfClass:[NSNumber class]] && [the_object2 isKindOfClass:[NSNumber class]])
		{
			lua_pushboolean(lua_state, [the_object1 isEqualToNumber:the_object2]);
		}
		else if([the_object1 isKindOfClass:[NSValue class]] && [the_object2 isKindOfClass:[NSValue class]])
		{
			lua_pushboolean(lua_state, [the_object1 isEqualToValue:the_object2]);
		}
		else if([the_object1 isKindOfClass:[NSString class]] && [the_object2 isKindOfClass:[NSString class]])
		{
			lua_pushboolean(lua_state, [the_object1 isEqualToString:the_object2]);
		}
		else if([the_object1 isKindOfClass:[NSDictionary class]] && [the_object2 isKindOfClass:[NSDictionary class]])
		{
			lua_pushboolean(lua_state, [the_object1 isEqualToDictionary:the_object2]);
		}
		else if([the_object1 isKindOfClass:[NSArray class]] && [the_object2 isKindOfClass:[NSArray class]])
		{
			lua_pushboolean(lua_state, [the_object1 isEqualToArray:the_object2]);
		}
		else if([the_object1 isKindOfClass:[NSSet class]] && [the_object2 isKindOfClass:[NSSet class]])
		{
			lua_pushboolean(lua_state, [the_object1 isEqualToSet:the_object2]);
		}
		else if([the_object1 isKindOfClass:[NSDate class]] && [the_object2 isKindOfClass:[NSDate class]])
		{
			lua_pushboolean(lua_state, [the_object1 isEqualToDate:the_object2]);
		}
		else if([the_object1 isKindOfClass:[NSData class]] && [the_object2 isKindOfClass:[NSData class]])
		{
			lua_pushboolean(lua_state, [the_object1 isEqualToData:the_object2]);
		}
		else
		{
			lua_pushboolean(lua_state, [the_object1 isEqual:the_object2]);
		}

	}
	else
	{
		lua_pushboolean(lua_state, (the_object1 == the_object2));
	}
	
	
	return 1;
}

static int LuaObjectBridge_GetLength(lua_State* lua_state)
{
	LuaUserDataContainerForObject* lua_class_container = LuaObjectBridge_LuaCheckClass(lua_state, 1);
	id the_object = lua_class_container->theObject;
	
	if(LuaObjectBridge_IsInstance(lua_class_container))
	{
		if([the_object respondsToSelector:@selector(count)])
		{
			lua_pushinteger(lua_state, [the_object count]);
			return 1;
		}
		else if([the_object respondsToSelector:@selector(length)])
		{
			lua_pushinteger(lua_state, [the_object length]);			
			return 1;
		}
		else
		{
			return luaL_error(lua_state, "Object instance does not respond to count or length for #");
		}
	}
	else
	{
		return luaL_error(lua_state, "Object is not an instance and does not respond to count or length for #");
	}
}


static int LuaObjectBridge_Concat(lua_State* lua_state)
{
	id the_object1 = LuaObjectBridge_checknsstring(lua_state, 1);
	id the_object2 = LuaObjectBridge_checknsstring(lua_state, 2);
	
	// FIXME: The proper way to do this is use BridgeSupport to look up the classes and see
	// if they have a method named isEqualTo<ClassName>: and run it if they have it.
	// One complication is if the classes are not the same type. Another complication is
	// if one class is a subclass of another (I'll have to figure out order.)
	if(ObjectSupport_IsInstance(the_object1) && ObjectSupport_IsInstance(the_object2))
	{
		if([the_object1 isKindOfClass:[NSString class]] && [the_object2 isKindOfClass:[NSString class]])
		{
			LuaObjectBridge_Pushid(lua_state, [the_object1 stringByAppendingString:the_object2]);
			return 1;
		}
		else
		{
			return luaL_error(lua_state, "Objects do not support __concat operation");
		}		
	}
	else
	{
		return luaL_error(lua_state, "Non-instance objects do not support __concat operation");
	}		
}	


static int LuaObjectBridge_Call(lua_State* lua_state)
{
	// HELP! I don't think I'm setting up __index and the metatable correctly.
	// ca_layer:name() returns two objects here (listed as a bool type and a userdata)
	// I'm not sure why this is a bool type.
	// ca_layer.name(ca_layer) does the same thing.
	// Only ca_layer.name() does what I am expecting: a single userdata argument
	
	//	NSLog(@"In LuaObjectBridge_Call");
	int number_of_arguments = lua_gettop(lua_state);
	//	NSLog(@"number_of_arguments=%d", number_of_arguments);
	
#if NS_BLOCKS_AVAILABLE
	
	
	// Blocks!
	// In this case, we have a raw Lua function that is not already boxed in a id/block.
	// We need to create a block to wrap the the Lua function.
	// Things to be aware of:
	// We must keep a reference to the Lua function so it doesn't get collected.
	// I'm not sure if the block should be copied. For safety, copying will avoid potential problems at the trade off of speed.
	LuaUserDataContainerForObject* lua_class_container = LuaObjectBridge_LuaCheckClass(lua_state, 1);
	id the_object = lua_class_container->theObject;
	
	if(LuaObjectBridge_IsInstance(lua_class_container))
	{
		if([the_object isKindOfClass:NSClassFromString(@"NSBlock")])
		{
			// We specify '2' to denote the arguments start after the block object at position 1
			return LuaBlockBridge_CallBlock(lua_state, the_object, 2);
		}
	}
#endif
	
	
#if LUAOBJECTBRIDGE_ENABLE_GETTER_DOT_NOTATION
	if(number_of_arguments == 1)
	{
		return 1;
	}
	else if(2 == number_of_arguments)
	{
		// the parameter I want seems to be the first parameter (index 1).
//		NSLog(@"1: %s, 2: %s", lua_typename(lua_state, 1), lua_typename(lua_state, 2));
//		id the_object2 = LuaObjectBridge_checkid(lua_state, 2);
//		NSLog(@"the_object2: %@", the_object2);
//		id the_object1 = LuaObjectBridge_checkid(lua_state, 1);
//		NSLog(@"the_object1: %@", the_object1);
		lua_pop(lua_state, 1);
		return 1; // return the userdata on top of the stack
	}
	else
	{
		luaL_error(lua_state, "Assertion failure. If your code is correct and you are seeing this, you may need to disable LUAOBJECTBRIDGE_ENABLE_GETTER_DOT_NOTATION because it is misinterpretting a method call as a property getter. Sorry.");
	}

	return 1;
#else
	return number_of_arguments;
#endif
}

// 1 or -3 for userdata object
// 2 or -2 for index or key
// 3 or -1 for new value
static int LuaObjectBridge_SetIndexOnClass(lua_State* lua_state)
{
//	NSLog(@"In LuaObjectBridge_SetIndexOnClass");
//	int number_of_arguments = lua_gettop(lua_state);
//	NSLog(@"number_of_arguments=%d", number_of_arguments);
	LuaUserDataContainerForObject* lua_class_container = LuaObjectBridge_LuaCheckClass(lua_state, 1);

	if(0 == strcmp(LuaObjectBridge_tostring(lua_state, -2), "__ivars") && LuaObjectBridge_IsLuaSubclass(lua_class_container))
	{
		if(!lua_istable(lua_state, -1))
		{
			return luaL_error(lua_state, "LuaCocoa requires that the rvalue assigning to __ivars must be a table");
		}
		
		bool table_exists = LuaCocoaStrongTable_GetLuaSubclassEnvironmentTableInGlobalStrongTable(lua_state, lua_class_container->theObject);
#pragma unused(table_exists)		
		lua_setfield(lua_state, -2, "__ivars"); // [__methods env_table key userdata] 
		return 0;
	}
	
	// New methods on Lua subclasses and categories on existing classes are very similar, but different due to the way I implemented things. Bleh.
	if(LuaObjectBridge_IsClass(lua_class_container))
	{
		bool ret_flag;
		if(LuaObjectBridge_IsLuaSubclass(lua_class_container))
		{
			if(lua_istable(lua_state, 3))
			{
				ret_flag = LuaSubclassBridge_SetNewMethodAndSignature(lua_state);
			}
			else
			{
				// Assumption: This is a Lua-only method.
				// I might be able to guess, but there is an ambiguity between class and instance methods
				// if both exist which I don't really want to deal with.
				ret_flag = LuaSubclassBridge_SetNewMethod(lua_state);
			}
		}
		else // for categories
		{
			if(lua_istable(lua_state, 3))
			{
				ret_flag = LuaCategoryBridge_SetCategoryWithMethodAndSignature(lua_state);
			}
			else
			{
				// Assumption: This is a Lua-only method.
				// I might be able to guess, but there is an ambiguity between class and instance methods
				// if both exist which I don't really want to deal with.
				ret_flag = LuaSubclassBridge_SetNewMethod(lua_state);
			}
		}
		if(true == ret_flag)
		{
			return 0;
		}
		
	}
	
	
	if(lua_isnumber(lua_state, 2))
	{
		int the_index = lua_tointeger(lua_state, 2);
			
		// Question: Do I adjust indices for counting at 1 instead of 0?
		// adjust index (lua starts at 1, so subtract 1 going to Obj-C)
		the_index = the_index-1;
		
		if(the_index < 0)
		{
			luaL_error(lua_state, "Illegal index value of %d for NSArray in __newindex", the_index);
		}
//		NSLog(@"Got number in SetIndex: %d", the_index);
		// I am assuming users are not using numbers for method names
		if(LuaObjectBridge_IsInstance(lua_class_container) && [lua_class_container->theObject isKindOfClass:[NSMutableArray class]])
		{
			id new_object = LuaObjectBridge_topropertylist(lua_state, 3);
			NSUInteger number_of_elements_in_array = [(NSMutableArray*)lua_class_container->theObject count];
			if(lua_isnil(lua_state, 3))
			{
				// Special case for nil assignment. Allow removal of the object in the array
				[(NSMutableArray*)lua_class_container->theObject removeObjectAtIndex:the_index];
			}
			else if(nil != new_object)
			{

				if(the_index < number_of_elements_in_array)
				{
					[(NSMutableArray*)lua_class_container->theObject replaceObjectAtIndex:the_index withObject:new_object];
				}
				else if(number_of_elements_in_array == the_index)
				{
					// In this case, the index is a new element at the end of the array so we use addObject
					[(NSMutableArray*)lua_class_container->theObject addObject:new_object];
				}
				else
				{
					// NSMutableArray doesn't support sparse arrays. Maybe a custom subclass does though.
					// But should we use insertObject:atIndex: or replaceObjectAtIndex:withIndex?
					// Likely this will throw an exception by Obj-C.
					[(NSMutableArray*)lua_class_container->theObject replaceObjectAtIndex:the_index withObject:new_object];					
				}
			}
			else
			{
				luaL_error(lua_state, "Unsuporrted type for __newindex on NSMutableArray with number index (could be something inside a container if passing a container)");
			}
		}
		else
		{
			luaL_error(lua_state, "Unexpected type for __newindex on NSMutableArray with number index");
		}
	}
	else if(lua_isstring(lua_state, 2))
	{
		const char* index_string = lua_tostring(lua_state, 2);
//		NSLog(@"Got string in SetIndex: %s", index_string);
		NSString* string_key = [NSString stringWithUTF8String:index_string];

		if(LuaObjectBridge_IsInstance(lua_class_container) && [lua_class_container->theObject isKindOfClass:[NSMutableDictionary class]])
		{
			id new_object = LuaObjectBridge_topropertylist(lua_state, 3);
			if(lua_isnil(lua_state, 3))
			{
				// Special case for nil assignment. Allow removal of the object in the dictionary
				[(NSMutableDictionary*)lua_class_container->theObject removeObjectForKey:string_key];
			}
			else if(nil != new_object)
			{
				[(NSMutableDictionary*)lua_class_container->theObject setObject:new_object forKey:string_key];					
			}
			else
			{
				luaL_error(lua_state, "Unexpected type for __newindex on NSMutableDictionary with string index");
			}
		}
		else if(LuaObjectBridge_IsInstance(lua_class_container))
		{
			// Experimental property setter support.
			// e.g. instead of [myFoo setBar:a_bar];, can do myFoo.bar = a_bar;
			// I'm actually not going to use class_copyPropertyList because 
			// I would like to support anything that is KVC compliant.
			 
			// convert bar_ to setBar_ 
			NSString* property_string = [NSString stringWithUTF8String:index_string];
			NSString* setter_name = [[@"set" stringByAppendingString:NSStringHelperFunctions_CapitalizeFirstCharacter(property_string)] stringByAppendingString:@":"];

			// +1 for NULL and another +1 for optional omitted underscore
			size_t max_str_length = [setter_name length]+2;
			char objc_dst_string[max_str_length];
			SEL the_selector;
		#warning "FIXME: Need to specify class method vs. instance method"
			if(ObjectSupport_ConvertUnderscoredSelectorToObjC(objc_dst_string, [setter_name UTF8String], max_str_length, lua_class_container->theObject, LuaObjectBridge_IsInstance(lua_class_container), &the_selector, LuaObjectBridge_IsClass(lua_class_container)))
			{
				// TODO: OPTIMIZE: we are running ObjectSupport_ConvertUnderscoredSelectorToObjC twice,
				// once here, and again in LuaObjectBridge_InvokeMethod. It would be nice to cache the values.

				// Now get ready to invoke the function
				// Invoke method expects:
				// 1 for userdata object
				// Any thing > 1 is an argument
				// There is also an upvalue for the method name
				// Currently, our stack from this function is
				// 1 for userdata object
				// 2 for key
				// 3 for new value
				
				// Ultimately, we want our stack to look like:
				// [upvalue cclosure userdata newvalue]
								
				// I need the lua_method_name (e.g. setBar_) as the upvalue
				lua_pushstring(lua_state, [setter_name UTF8String]);
				lua_pushcclosure(lua_state, LuaObjectBridge_InvokeMethod, 1);

				lua_pushvalue(lua_state, 1); // copy userdata from position 1 to the current top
				lua_pushvalue(lua_state, 3); // copy the newvalue from position 3 to the current top

				// Invoke it
				lua_call(lua_state, 2, 0);
				return 0;
			}
		}
		else
		{
			luaL_error(lua_state, "Unexpected type for __newindex with string index");
		}
		
	}
	else if(lua_isuserdata(lua_state, 2))
	{
//		NSLog(@"Got userdata in SetIndex");
		
		// Don't know what to do with non-object. Abort for ease.
		LuaUserDataContainerForObject* key_object_container = LuaObjectBridge_LuaCheckClass(lua_state, 2);

		id key_object = key_object_container->theObject;

		if(LuaObjectBridge_IsInstance(lua_class_container) && [lua_class_container->theObject isKindOfClass:[NSMutableArray class]])
		{
			if(!LuaObjectBridge_IsInstance(key_object_container) && ![key_object isKindOfClass:[NSNumber class]])
			{
				return luaL_error(lua_state, "Unexpected key type for __newindex on NSMutableArray with userdata index");
			}
			
			id new_object = LuaObjectBridge_topropertylist(lua_state, 3);
			NSUInteger number_of_elements_in_array = [(NSMutableArray*)lua_class_container->theObject count];
			NSUInteger the_index = [key_object unsignedIntegerValue]-1;
			if(lua_isnil(lua_state, 3))
			{
				// Special case for nil assignment. Allow removal of the object in the array
				[(NSMutableArray*)lua_class_container->theObject removeObjectAtIndex:the_index];
			}
			else if(nil != new_object)
			{
				
				if(the_index < number_of_elements_in_array)
				{
					[(NSMutableArray*)lua_class_container->theObject replaceObjectAtIndex:the_index withObject:new_object];
				}
				else if(number_of_elements_in_array == the_index)
				{
					// In this case, the index is a new element at the end of the array so we use addObject
					[(NSMutableArray*)lua_class_container->theObject addObject:new_object];
				}
				else
				{
					// NSMutableArray doesn't support sparse arrays. Maybe a custom subclass does though.
					// But should we use insertObject:atIndex: or replaceObjectAtIndex:withIndex?
					// Likely this will throw an exception by Obj-C.
					[(NSMutableArray*)lua_class_container->theObject replaceObjectAtIndex:the_index withObject:new_object];					
				}
			}
			else
			{
				luaL_error(lua_state, "Unsuporrted type for __newindex on NSMutableArray with number index (could be something inside a container if passing a container)");
			}
		}
		else if(LuaObjectBridge_IsInstance(lua_class_container) && [lua_class_container->theObject isKindOfClass:[NSMutableDictionary class]])
		{
			id new_object = LuaObjectBridge_topropertylist(lua_state, 3);
			if(lua_isnil(lua_state, 3))
			{
				// Special case for nil assignment. Allow removal of the object in the dictionary
				[(NSMutableDictionary*)lua_class_container->theObject removeObjectForKey:key_object];
			}
			else if(nil != new_object)
			{
				[(NSMutableDictionary*)lua_class_container->theObject setObject:new_object forKey:key_object];					
			}
			else
			{
				luaL_error(lua_state, "Unexpected type for __newindex on NSMutableDictionary with userdata index");
			}
		}
		else if(LuaObjectBridge_IsInstance(lua_class_container) && LuaObjectBridge_isnsstring(lua_state, 2))
		{
			// Experimental property setter support.
			// e.g. instead of [myFoo setBar:a_bar];, can do myFoo.bar = a_bar;
			// I'm actually not going to use class_copyPropertyList because 
			// I would like to support anything that is KVC compliant.
			
			// convert bar_ to setBar_ 
			NSString* property_string = LuaObjectBridge_tonsstring(lua_state, 2);
			NSString* setter_name = [[@"set" stringByAppendingString:NSStringHelperFunctions_CapitalizeFirstCharacter(property_string)] stringByAppendingString:@":"];
			
			// +1 for NULL and another +1 for optional omitted underscore
			size_t max_str_length = [setter_name length]+2;
			char objc_dst_string[max_str_length];
			SEL the_selector;
#warning "FIXME: Need to specify class method vs. instance method"

			if(ObjectSupport_ConvertUnderscoredSelectorToObjC(objc_dst_string, [setter_name UTF8String], max_str_length, lua_class_container->theObject, LuaObjectBridge_IsInstance(lua_class_container), &the_selector, LuaObjectBridge_IsClass(lua_class_container)))
			{
				// TODO: OPTIMIZE: we are running ObjectSupport_ConvertUnderscoredSelectorToObjC twice,
				// once here, and again in LuaObjectBridge_InvokeMethod. It would be nice to cache the values.
				
				// Now get ready to invoke the function
				// Invoke method expects:
				// 1 for userdata object
				// Any thing > 1 is an argument
				// There is also an upvalue for the method name
				// Currently, our stack from this function is
				// 1 for userdata object
				// 2 for key
				// 3 for new value
				
				// Ultimately, we want our stack to look like:
				// [upvalue cclosure userdata newvalue]
				
				// I need the lua_method_name (e.g. setBar_) as the upvalue
				lua_pushstring(lua_state, [setter_name UTF8String]);
				lua_pushcclosure(lua_state, LuaObjectBridge_InvokeMethod, 1);
				
				lua_pushvalue(lua_state, 1); // copy userdata from position 1 to the current top
				lua_pushvalue(lua_state, 3); // copy the newvalue from position 3 to the current top
				
				// Invoke it
				lua_call(lua_state, 2, 0);
				return 0;
			}
		}
		else
		{
			luaL_error(lua_state, "Unexpected type for __newindex with userdata index");
		}
	}
	else
	{
//		NSLog(@"Got something else in SetIndex");
		luaL_error(lua_state, "Unexpected type for __newindex for key");
	}
	
	
	return 0;
}

// obj_index = 1 is userdata object
// upvalue index 1 is the lua_method_name (e.g. initWithFoo_andBar_)
static int LuaObjectBridge_InvokeMethod(lua_State* lua_state)
{
	const int NUMBER_OF_SUPPORT_ARGS = 0; // No internal use only arguments

//	NSLog(@"In LuaObjectBridge_InvokeMethod");
	int number_of_arguments = lua_gettop(lua_state);
//	NSLog(@"number_of_arguments=%d", number_of_arguments);
	
	
	const char* lua_method_name = luaL_checkstring(lua_state, lua_upvalueindex(1));
//	NSLog(@"lua_method_name=%s", lua_method_name);
	
	// using absolute
	LuaUserDataContainerForObject* object_container = LuaObjectBridge_LuaCheckClass(lua_state, 1);

	id the_object = object_container->theObject;
/*	
	if(object_container->isInstance)
	{
		NSLog(@"The object:%x, class:%@ isInstance:%d", object_container->theObject, NSStringFromClass([object_container->theObject class]), object_container->isInstance);
		NSLog(@"isSuper: %d", object_container->isSuper);
	}
	else
	{
		NSLog(@"got class: %@", NSStringFromClass(object_container->theObject));
	}
*/
	
	// Very special short circuit case for a method named "super".
	// We will return the the same object with the container marked with the isSuper flag marked.
	// This hack is not callable directly from Objective-C, but I assume in Objective-C, the user
	// invokes super directly, e.g. [super dealloc];
	if(0 == strcmp(lua_method_name, "super"))
	{
		if(LuaObjectBridge_IsClass(object_container))
		{
			LuaObjectBridge_PushClass(lua_state, LuaObjectBridge_GetClass(object_container));
		}
		else
		{
			// FIXME: Ugh. I have to violate my 1 object to 1 userdata rule here.
			// Because I am simply marking a flag in my container rather than creating a unique object,
			// I must create a separate userdata object. I really hope this doesn't break any other assumptions I forgot about.
			// I don't put this in the normal weak table because it will collide with the non-super object.
			// Instead, this goes in a special table just for super instances.
			Class super_class_parameter = nil;
			if(lua_isstring(lua_state, 2))
			{
				super_class_parameter = objc_getClass(lua_tostring(lua_state, 2));
			}
			else if(LuaObjectBridge_isnsstring(lua_state, 2))
			{
				super_class_parameter = NSClassFromString(LuaObjectBridge_tonsstring(lua_state, 2));
//				NSLog(@"self_class: %@, super_class: %@", NSStringFromClass(object_getClass(object_container->theObject)), NSStringFromClass(super_class_parameter));

			}
			else if(LuaObjectBridge_isid(lua_state, 2))
			{
				super_class_parameter = LuaObjectBridge_GetClass(lua_touserdata(lua_state, 2));
			}
			LuaObjectBridge_PushSuperid(lua_state, object_container->theObject);
			LuaUserDataContainerForObject* super_container = lua_touserdata(lua_state, -1);
#if !defined(LUA_COCOA_USE_INTERMEDIATE_OBJECTS_TO_HOLD_SUPERCLASS)
			super_container->superClass = super_class_parameter;
#else // experiment to try to create new intermediate containers to pass along superClass informatation
			// I think I was hoping to implicitly decide/remember/know which super class to invoke, but this wasn't working.
/*
			if(NULL != object_container->superClass)
			{
				super_container->superClass = ObjectSupport_GetSuperClassFromClass(object_container->superClass);
				
			}
			else
			{
//				super_container->superClass = NULL;
				super_container->superClass = super_class_parameter;

			}
*/
			super_container->superClass = super_class_parameter;

#endif
		}

		return 1;
	}
	
	
	// Convert the name of the selector to canonical Objective-C form

	// +1 for NULL and another +1 for optional omitted underscore
	size_t max_str_length = strlen(lua_method_name)+2;
	
	char objc_method_name[max_str_length];
	SEL the_selector;
	ParseSupportMethod* parse_support = nil;
	bool use_objc_msg_send = false; // use imp pointer by default since its faster
	Class which_class_found = NULL;
	bool is_instance_defined = false;
	bool did_find_lua_method = LuaSubclassBridge_FindLuaMethod(lua_state, object_container, lua_method_name, &which_class_found, &is_instance_defined);
	
	//		lua_pushstring(lua_state, lua_method_name);
	//		LuaSubclassBridge_GetIndexOnClass(lua_state, object_container, LuaObjectBridge_IsClass(object_container), &did_handle_case);
#warning "FIXME: Need to rewrite to distinguish between Lua-only methods and Obj-C bound methods

#warning "FIXME: Need to specify class method vs. instance method"
	if(ObjectSupport_ConvertUnderscoredSelectorToObjC(objc_method_name, lua_method_name, max_str_length, the_object, LuaObjectBridge_IsInstance(object_container), &the_selector, LuaObjectBridge_IsClass(object_container)))
	{
		//		NSString* class_name = [NSString stringWithUTF8String:object_getClassName(the_object)];
		NSString* class_name = NSStringFromClass(LuaObjectBridge_GetClass(object_container));
		
		//		NSLog(@"Got method and selector for class_name:%@", class_name);
#warning "FIXME: Need clue as to whether class or instance method"

		// Load up the Obj-C runtime and XML info into an object we can more easily use
		parse_support = [ParseSupportMethod parseSupportMethodFromClassName:class_name
						  methodName:[NSString stringWithUTF8String:objc_method_name] 
						  isInstance:LuaObjectBridge_IsInstance(object_container)
						  theReceiver:the_object
						  isClassMethod:LuaObjectBridge_IsClass(object_container)
						];
		
		// If there are variadic arguments, add them to the parse support information.
		// Note that if there are variadic arguments, this parse_support instance cannot be reused/cached for different function calls
		// Offset is 0-1 (0 for no internal use arguments, -1 because the first 2 arguments are supposed to be the receiver and selector,
		// but the selector is not an argument on the stack (it is a upvalue), so we must subtract 1
		LuaFFISupport_ParseVariadicArguments(lua_state, parse_support, NUMBER_OF_SUPPORT_ARGS-1);
		
		
	}
	else if(true == did_find_lua_method) // now lua-only method
	{
		// Assertion is that the lua function is on top of the stack.
		// Several (evil) things need to happen.
		// We need to push "self" as the first parameter.
		// But (this is evil), if the self object was marked as super, we need to disable the super status
		// because FindLuaMethod already used the super status to hunt for the proper method.
		// (If we don't remove the status, it will try to call super instead of self in the method implementation
		// of the function we are about to call.)
		// To get the non-super object, we can refer to our global weak table.
		// We also need to pass all the parameters received in this function call to the function we are about to call.
		// It should be much easier to shift the stack positions so that the function we are about to call
		// is at the very bottom and we should probably pop the super object since we don't want it to persist.
		// Finally, because Lua can return multiple values, we need to count the number of arguments that are returned.			
		
		
		// Put the function we are about to call as the first element in the stack, everything else shifts up 1
		lua_insert(lua_state, 1);
		
		// Next get the non-super instance of our method (if needed)
		// Assumption: super objects are always instances because otherwise we would have just provided the class
		if(LuaObjectBridge_IsSuper(object_container))
		{
// FIXME: Re-evaluate both of these cases. I'm no longer sure if either of these cases are the best/proper thing to do.
#if !defined(LUA_COCOA_USE_INTERMEDIATE_OBJECTS_TO_HOLD_SUPERCLASS)
			// pushes the non-super object on top of the stack
			LuaCocoaWeakTable_GetObjectInGlobalWeakTable(lua_state, object_container->theObject);
			// The super-instance should be at index 2 (shifted up from 1 after the function shift)
			// Replace the super-instance with the non-super one.
			lua_replace(lua_state, 2);
#else // experiment to try to create new intermediate containers to pass along superClass informatation
			// Will create the new userdata and leave it on the stack
			LuaObjectBridge_CreateUserData(lua_state, object_container->theObject, true, true, false);
			LuaUserDataContainerForObject* new_container = lua_touserdata(lua_state, -1);
			new_container->isLuaSubclass = object_container->isLuaSubclass;
			new_container->superClass = which_class_found;
			// Replace the super-instance with the non-super one.
			lua_replace(lua_state, 2);
#endif
		}
		// Turns out the the number_of_arguments is exactly the number_of_arguments we want.
		// (self + anything passed in)
		lua_call(lua_state, number_of_arguments, LUA_MULTRET);
		int number_of_return_arguments = lua_gettop(lua_state);
		//		NSLog(@"number_of_return_arguments from lua_call is %d", number_of_return_arguments);
		return number_of_return_arguments;
	}	
	else
	{

		// FIXME: I don't know what triggers this condition any more.
		
		
		ParseSupportArgument* return_value_argument = nil;
		/*
		 if(class_respondsToSelector(the_object->isa, @selector(isProxy)) && [the_object isProxy])
		 {
		 NSLog(@"respondsToSelector");
		 // Add 2: 1 for null character, 1 for possible last underscore that was omitted by scripter
		 //	char objc_method_name[method_string_length+2];
		 
		 strlcpy(objc_method_name, lua_method_name, max_str_length);
		 
		 // Replace all underscores with colons
		 size_t method_string_length = strlen(lua_method_name);
		 for(size_t char_index=0; char_index<method_string_length; char_index++)
		 {
		 if('_' == objc_method_name[char_index])
		 {
		 objc_method_name[char_index] = ':';
		 }
		 }
		 if(![the_object respondsToSelector:sel_registerName(objc_method_name)])
		 {
		 objc_method_name[method_string_length] = ':';
		 objc_method_name[method_string_length+1] = '\0';
		 }
		 if([the_object respondsToSelector:sel_registerName(objc_method_name)])
		 {
		 NSMethodSignature* the_sig = [the_object methodSignatureForSelector:sel_registerName(objc_method_name)];
		 return_value_argument = [[[ParseSupportArgument alloc] init] autorelease];
		 return_value_argument.objcEncodingType = [NSString stringWithUTF8String:[the_sig methodReturnType]];
		 //				   [return_value_argument.flattenedObjcEncodingTypeArray 
		 }
		 
		 }
		 */
		// Could be Lua-only method definition.
		// FIXME: We could actually check this
		
		
		//return luaL_error(lua_state, "Receiver %s does not implement method %s", class_getName(((Class)the_object)->isa), objc_method_name);
		parse_support = [[[ParseSupportMethod alloc] init] autorelease];
		// cheat/hack
		[parse_support setVariadic:true];
		if(LuaObjectBridge_IsClass(object_container))
		{
			[parse_support appendVaradicArgumentWithObjcEncodingType:_C_CLASS];
		}
		else
		{
			[parse_support appendVaradicArgumentWithObjcEncodingType:_C_ID];
		}
		
		[parse_support appendVaradicArgumentWithObjcEncodingType:_C_SEL];
		
		if(number_of_arguments - NUMBER_OF_SUPPORT_ARGS - 1 > 0)
		{
			
			// If there are variadic arguments, add them to the parse support information.
			// Note that if there are variadic arguments, this parse_support instance cannot be reused/cached for different function calls
			// Offset is 0-1 (0 for no internal use arguments, -1 because the first 2 arguments are supposed to be the receiver and selector,
			// but the selector is not an argument on the stack (it is a upvalue), so we must subtract 1
			LuaFFISupport_ParseVariadicArguments(lua_state, parse_support, NUMBER_OF_SUPPORT_ARGS-1);
		}
		return_value_argument = [[[ParseSupportArgument alloc] init] autorelease];
		return_value_argument.objcEncodingType = @"v"; // return _C_VOID
		[parse_support setReturnValue:return_value_argument];
		// need to use objc_msg_send to trigger forwardInvocation (I think)
		use_objc_msg_send = true;
		NSLog(@"didn't find selector/method for object:%@, lua_method=%s", the_object, lua_method_name);
		the_selector = sel_registerName(objc_method_name);
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
	size_t size_of_real_args = sizeof(ffi_type*) * parse_support.numberOfRealArguments;
	size_t size_of_flattened_args = sizeof(ffi_type*) * parse_support.numberOfFlattenedArguments;
	size_t size_of_custom_type_args = sizeof(ffi_type) * parse_support.numberOfRealArgumentsThatNeedToBeFlattened;
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
	
	ffi_cif the_cif;
	
	// FIXME: Check for 0 length sizes and avoid
#define ARBITRARY_NONZERO_SIZE 1
	size_t size_of_real_args_proxy = size_of_real_args ? size_of_real_args : ARBITRARY_NONZERO_SIZE;
	size_t size_of_flattened_args_proxy = size_of_flattened_args ? size_of_flattened_args : ARBITRARY_NONZERO_SIZE;
	size_t size_of_custom_type_args_proxy = size_of_custom_type_args ? size_of_custom_type_args : ARBITRARY_NONZERO_SIZE;
	size_t size_of_flattened_return_proxy = size_of_flattened_return ? size_of_flattened_return : ARBITRARY_NONZERO_SIZE;
	size_t size_of_custom_type_return_proxy = size_of_custom_type_return ? size_of_custom_type_return : ARBITRARY_NONZERO_SIZE;
#undef ARBITRARY_NONZERO_SIZE
	
	
	// use VLAs to use stack memory
	int8_t real_args_array[size_of_real_args_proxy];
	int8_t flattened_args_array[size_of_flattened_args_proxy];
	int8_t custom_type_args_array[size_of_custom_type_args_proxy];
	int8_t flattened_return_array[size_of_flattened_return_proxy];
	int8_t custom_type_return_array[size_of_custom_type_return_proxy];

	// Setup pointers to memory areas
	ffi_cif* cif_ptr = &the_cif;
	
	ffi_type** real_args_ptr = (ffi_type**)&real_args_array[0];
	ffi_type* custom_type_args_ptr = (ffi_type*)&custom_type_args_array[0];
	ffi_type** flattened_args_ptr = (ffi_type**)&flattened_args_array[0];

	ffi_type* real_return_ptr = NULL;
	ffi_type* custom_type_return_ptr = (ffi_type*)&custom_type_return_array[0];
	ffi_type** flattened_return_ptr = (ffi_type**)&flattened_return_array[0];

	char check_void_return;
	if(nil == parse_support.returnValue.objcEncodingType || 0 == [parse_support.returnValue.objcEncodingType length])
	{
		// FIXME:
		NSLog(@"no return type set. This is probably a bug");
		// Not sure if I should assume id or void
		check_void_return = _C_VOID;
	}
	else
	{
		check_void_return = [parse_support.returnValue.objcEncodingType UTF8String][0];
	}
	bool is_void_return = false;
	if(_C_VOID == check_void_return)
	{
		is_void_return = true;
	}
	
	if(0 == size_of_real_args)
	{
		real_args_ptr = NULL;
	}
	if(0 == size_of_flattened_args)
	{
		flattened_args_ptr = NULL;
	}
	if(0 == size_of_custom_type_args)
	{
		custom_type_args_ptr = NULL;
	}
	if(0 == size_of_flattened_return || true == is_void_return)
	{
		flattened_return_ptr = NULL;
	}
	if(0 == size_of_custom_type_return || true == is_void_return)
	{
		custom_type_return_ptr = NULL;
	}
	
	FFISupport_ParseSupportFunctionArgumentsToFFIType(parse_support, custom_type_args_ptr, &real_args_ptr, flattened_args_ptr);
		
	// real_return_ptr will be set by the function.
	FFISupport_ParseSupportFunctionReturnValueToFFIType(parse_support, custom_type_return_ptr, &real_return_ptr, flattened_return_ptr);
	
	
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
	
	// PyObjC and JSCocoa seem to look at the return value size and type to figure out which variant
	// of objc_msgSend* to use. But I thought the whole point of using libffi was to eliminate that problem.
	// MacRuby seems to grab an imp instead which makes more sense to me but there
	// are additional cases I don't yet understand in their code base
	void* function_ptr;
	
	{
		Class the_class;
		if(LuaObjectBridge_IsInstance(object_container))
		{
			the_class = object_getClass(object_container->theObject);
		}
		else
		{
			the_class = object_container->theObject;		
		}
		if(ObjectSupport_IsSubclassOfClass(the_class, objc_getClass("NSProxy")))
		{
			use_objc_msg_send = true;
//			NSLog(@"the real class is %@, but the proxied object is %@", NSStringFromClass(the_class), the_object);  
		}
	}
	
	Method saved_self_method = NULL;
	Method saved_super_method = NULL;
	IMP saved_self_imp = NULL;
	IMP saved_super_imp = NULL;
	
	// PyObjC way
	// Used for NSProxy classes
	if(use_objc_msg_send)
	{
		function_ptr = ObjectSupport_GetObjcMsgSendCallAddress([parse_support returnValueObjcEncodingType], LuaObjectBridge_IsSuper(object_container));
	}
	// MacRuby
	// Used for non-NSProxy classes
	else
	{
		Class the_class;
		if(LuaObjectBridge_IsInstance(object_container))
		{
			if(object_container->isSuper)
			{
				the_class = class_getSuperclass(object_getClass(object_container->theObject));
			}
			else
			{
				the_class = object_getClass(object_container->theObject);				
			}
		}
		else
		{
			if(object_container->isSuper)
			{
				the_class = class_getSuperclass(object_container->theObject);
			}
			else
			{
				the_class = object_container->theObject;
			}
		}
		
		// Assumption: Object instances always get instance methods, while classes always get class methods
		if(LuaObjectBridge_IsInstance(object_container))
		{
			if(LuaObjectBridge_IsSuper(object_container))
			{
//				NSLog(@"self_class: %@, super_class: %@", NSStringFromClass(object_getClass(object_container->theObject)), NSStringFromClass(object_container->superClass));
				saved_self_method = class_getInstanceMethod(object_getClass(object_container->theObject), the_selector);;
//				saved_super_method = class_getInstanceMethod(class_getSuperclass(object_getClass(object_container->theObject)), the_selector);;
				saved_super_method = class_getInstanceMethod(object_container->superClass, the_selector);;
				saved_self_imp = method_getImplementation(saved_self_method);
				saved_super_imp = method_getImplementation(saved_super_method);
				function_ptr = saved_super_imp;
				// temporarily swizzle (swap) methods
				method_setImplementation(saved_self_method, saved_super_imp);

			}
			else
			{
				Method the_method = class_getInstanceMethod(the_class, the_selector);
				function_ptr = method_getImplementation(the_method);
			}

		}
		else
		{
			if(LuaObjectBridge_IsSuper(object_container))
			{
				saved_self_method = class_getClassMethod(object_container->theObject, the_selector);;
//				saved_super_method = class_getClassMethod(class_getSuperclass(object_container->theObject), the_selector);;
				saved_super_method = class_getClassMethod(object_container->superClass, the_selector);;
				saved_self_imp = method_getImplementation(saved_self_method);
				saved_super_imp = method_getImplementation(saved_super_method);
				function_ptr = saved_super_imp;
				// temporarily swizzle (swap) methods
				method_setImplementation(saved_self_method, saved_super_imp);
			}
			else
			{
				Method the_method = class_getClassMethod(the_class, the_selector);
				function_ptr = method_getImplementation(the_method);
			}

			
		}
	}

		
	// This part of the implementation uses alloca because it is convenient, likely faster than heap memory, and all the other bridges do the same thing.
	// I would have preferred VLAs because I am unsure about the rules of using alloca (are they reliable as parameters to functions?)
	// but they didn't seem flexible enough as all the sizeof(type)'s are different values.
	// But the big downside is that I can't easily encapsulate the large switch statement into a function because it calls alloca.
	NSUInteger number_of_function_args = parse_support.numberOfRealArguments;

// START COPY AND PASTE HERE	
	void* current_arg;
	int i, j;

//	void** array_for_ffi_arguments = alloca(sizeof(void *) * number_of_function_args);
	void* array_for_ffi_arguments[number_of_function_args];

	// for out-arguments
//	void** array_for_ffi_ref_arguments = array_for_ffi_ref_arguments = alloca(sizeof(void *) * number_of_function_args);
	void* array_for_ffi_ref_arguments[number_of_function_args];
// END COPY AND PASTE HERE

	// remember that the first two argments to objc_msgSend are the object and selector
	// For objc_msgSendSuper, we need to do something different
	struct objc_super super_data;
	struct objc_super* super_data_ptr = &super_data;
	if(true == use_objc_msg_send && LuaObjectBridge_IsSuper(object_container))
	{
		super_data.receiver = the_object;
		
//		NSLog(@"super_data.receiver: %@", super_data.receiver);
#if !defined(__cplusplus)  &&  !__OBJC2__
		super_data.class = [super_data.receiver superclass];
//		NSLog(@"Super_class: %@", NSStringFromClass(super_data.class));
#else
		super_data.super_class = [super_data.receiver superclass];
//		NSLog(@"Super_class: %@", NSStringFromClass(super_data.super_class));


//		super_data.super_class = [the_object superclass]->isa;
//		NSLog(@"Super_class: %@", NSStringFromClass(super_data.super_class));
#endif

		array_for_ffi_arguments[0] = &super_data_ptr;

	}
	else
	{
		array_for_ffi_arguments[0] = &the_object;
	}

	array_for_ffi_arguments[1] = &the_selector;
//	NSLog(@"the_selector: %@", NSStringFromSelector(the_selector));

	// In our lua stack, arg1 is the object, but arg2 is the not the selector, but the next parameter because the selector is an upvalue
	// However we start a j=2 because lua starts at index=1, not 0
    for(i = 2, j = 2 + NUMBER_OF_SUPPORT_ARGS; i < number_of_function_args; i++, j++)
	{
//		LuaFFISupport_FillFFIArguments(lua_state, array_for_ffi_arguments, array_for_ffi_ref_arguments, i, j, cif_ptr->arg_types[i]->type, [parse_support.argumentArray objectAtIndex:i]);
	
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
	//						NSLog(@"current_arg.declaredType=%@ objcEncodingType=%@, inOutTypeModifier=%@", current_parse_support_argument.declaredType, current_parse_support_argument.objcEncodingType, current_parse_support_argument.inOutTypeModifier);
				if([current_parse_support_argument.inOutTypeModifier isEqualToString:@"o"] || [current_parse_support_argument.inOutTypeModifier isEqualToString:@"N"] || [current_parse_support_argument.inOutTypeModifier isEqualToString:@"n"])
				{
					
					// Lion workaround for lack of Full bridgesupport file
					char objc_encoding_type;
					NSString* nsstring_encoding_type = current_parse_support_argument.objcEncodingType;
					if([nsstring_encoding_type length] < 2)
					{
						// assuming we are dealing with regular id's
						objc_encoding_type = _C_ID;						
					}
					else
					{
						objc_encoding_type = [nsstring_encoding_type UTF8String][1];						
					}
					
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
								putarg(int8_t*, NULL);
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
								*((double*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(double*, (double*)&(array_for_ffi_ref_arguments[i]));
							}
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
								*((float*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(float*, (float*)&(array_for_ffi_ref_arguments[i]));
							}
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
								putarg(Class, nil);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(id));
								if(LuaObjectBridge_isid(lua_state, j))
								{
									// FIXME: Change to explicit toclass
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
					// Lion workaround for lack of Full bridgesupport file
					char objc_encoding_type;
					NSString* nsstring_encoding_type = current_parse_support_argument.objcEncodingType;
					if([nsstring_encoding_type length] < 1)
					{
						// assuming we are dealing with regular id's
						objc_encoding_type = _C_ID;						
					}
					else
					{
						objc_encoding_type = [nsstring_encoding_type UTF8String][0];						
					}
					
					switch(objc_encoding_type)
					{
						case _C_ID:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(id, nil);
							}
							else if(lua_isfunction(lua_state, j) && [current_parse_support_argument isBlock])
							{
								// coerce Lua function into Obj-C block
								id new_block = LuaBlockBridge_CreateBlockFromLuaFunctionWithParseSupport(lua_state, j, [current_parse_support_argument functionPointerEncoding]);
								[new_block autorelease];
								//id block_userdata = LuaObjectBridge_Pushid(lua_state, new_block);
								
								putarg(id, new_block);
							}
							else
							{
								// Will auto-coerce numbers, strings, tables to Cocoa objects
								id property_object = LuaObjectBridge_topropertylist(lua_state, j);			
								putarg(id, property_object);
							}
							break;
						}
						case _C_CLASS:
						{
							Class to_object = LuaObjectBridge_toid(lua_state, j);			
							putarg(Class, to_object);
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
						{
							if(lua_isfunction(lua_state, j) && [current_parse_support_argument isFunctionPointer])
							{
								NSLog(@"Non-block function pointers not implemented yet. Should be easy to adapt block code to handle.");
								// coerce Lua function into Obj-C block
								
//								id new_block = LuaBlockBridge_CreateBlockFromLuaFunctionWithParseSupport(lua_state, j, [current_parse_support_argument.functionPointerEncoding]);
//								putarg(id, new_block);
								putarg(void*, lua_touserdata(lua_state, j));

							}
							else
							{
								putarg(void*, lua_touserdata(lua_state, j));
							}
						}
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
	ffi_call(cif_ptr, FFI_FN(function_ptr), return_value, array_for_ffi_arguments);		
	
	// Undo the swizzle (swap) for super
	if(LuaObjectBridge_IsSuper(object_container))
	{
		// un-swizzle (swap) methods
		method_setImplementation(saved_self_method, saved_self_imp);
	}
	
	int number_of_return_values = 0;
	
	// If the result (now on the top of the stack) is an object instance
	// we need to check if we need to special handle the retain count.
	
	// This is exception is for things like CALayer where alloc leaves the retainCount at 0.
	// NSPlaceholder objects seem to have retainCounts of < 0. I don't think I need to worry about
	// retaining placeholder objects
	// Analysis:
	// For things like CALayer, defer CFRetain and release if the retainCount is 0 until init is called.
	// For things like Placeholder objects, I think retaining is irrelevant either way as I expect
	// a retain and release to be a no-op. However, if it is not a no-op, then I think I can
	// retain here and when init is called, the reference will generally be overwritten in Lua
	// so Lua knows to collect its memory and we will get to call a balancing release.
	// The release however must be deferred until the init.
	// But this block of code will see the final object as a new/different object because
	// the memory addresses are different.

	// I could be more aggressive about checking BridgeSupport to make sure id is the return type.
	if( 0 == strcmp(objc_method_name, "alloc")
	   || 0 == strcmp(objc_method_name, "allocWithZone:")
	)
	{

		// Drat. CALayer remains at retainCount=0 after alloc. Seems to change
		// after init. Releasing here causes the object to be released
		// before init can save the object.
		// Also, for placeholder objects, (e.g. NSPlaceholderString, NSPlaceholderDictionary)
		// I may be releasing the wrong objects anyway.
		// So here is a hack to defer retaining and releasing

		number_of_return_values += LuaFFISupport_PushReturnValue(lua_state, return_value, cif_ptr->rtype, parse_support.returnValue, stack_index_for_struct_return_value, false, false);

	}
	else if(0 == strcmp(objc_method_name, "copy")
		|| 0 == strcmp(objc_method_name, "copyWithZone:")
		|| 0 == strcmp(objc_method_name, "mutableCopy")
		|| 0 == strcmp(objc_method_name, "mutableCopyWithZone:")
		|| 0 == strcmp(objc_method_name, "new")
	)
	{
		// Unlike elsewhere, we use release instead of CFRelease
		// because in this case, we are not trying to cancel-out
		// the CFRetain used by lua_objc_pushid which keeps the
		// pointer alive under objc-gc, but cancel-out the extra
		// ref-increment caused by the above methods.
		// Under objc-gc, we only want to use release knowing
		// it is a no-op. Otherwise, we could accidentally decrement
		// the ref-count with CFRelease which is the only thing
		// preventing the objc-gc system from collecting an object
		// out from Lua.
		// I thought about autorelease, but I think release is better
		// because I'm guaranteed to still have an object because of the 
		// CFRetain stuff I do, and I don't have to worry about autorelease pools.
		
		
		
		// Special Hack for objects subclassed in Lua.
		// I need to make sure they get the lua_State* and maybe initialize an ivar table
		// This is a hack. I assume the return value is always an id for init.
		// Grab the return value so we create the environmental table first so it is ready for Pushid.
		LuaSubclassBridge_InitializeNewLuaObjectIfSubclassInLua(*(id*) return_value, lua_state);
		
		// FIXME: Need to copy object instance's Lua-side properties (environment tables, variables) if a subclass
#warning "FIXME: Need to copy object instance's Lua-side properties (environment tables, variables) if a subclass"	
		
		// This will do a CFRetain on the object for the bridge
		number_of_return_values += LuaFFISupport_PushReturnValue(lua_state, return_value, cif_ptr->rtype, parse_support.returnValue, stack_index_for_struct_return_value, true, false);

		id the_return_instance = LuaObjectBridge_toid(lua_state, -1);
		// Problem: the instance may not be actually conform to the NSObject protocol
		// respondsToSelector is part of that. Doesn't seem to be much sense checking.
//			if([the_return_instance respondsToSelector:@selector(release)])
//			{

			// This will decrement the retain count by 1 because we don't need the extra retain generated by these methods
			[the_return_instance release];
//			}
	}
	else if(0 == strncmp(objc_method_name, "init", 4))
	{
		// Any time a method starts with init, I'll assume an alloc immediately predated it.
		// This might be bad, but I don't know what else to do.


		// Special Hack for objects subclassed in Lua.
		// I need to make sure they get the lua_State* and maybe initialize an ivar table
		// This is a hack. I assume the return value is always an id for init.
		// Grab the return value so we create the environmental table first so it is ready for Pushid.
		LuaSubclassBridge_InitializeNewLuaObjectIfSubclassInLua(*(id*) return_value, lua_state);
		
		
		// This will push the return value. If the object is already in the weak table, it will do nothing to the retain counts
		// which we will fix immediately below this
		number_of_return_values += LuaFFISupport_PushReturnValue(lua_state, return_value, cif_ptr->rtype, parse_support.returnValue, stack_index_for_struct_return_value, true, false);
		
		// don't think I need to check, just get the pointer
		LuaUserDataContainerForObject* the_container = lua_touserdata(lua_state, -1);
		
		
		// Compare the pointers for the object passed into this function to the one that was returned.
		if(object_container->theObject == the_container->theObject)
		{
			// Another special exception needs to be made for calls to super:init()
			// when overriding methods. We do not want to add extra retains in this case.
			if(!LuaObjectBridge_IsSuper(object_container))
			{
				
				//			NSLog(@"We are reusing the same object for init");
				// In the case where we continue with the same object, we need to correct the retain counts and status flags that we deferred under the alloc side.
				// retain for bridge (using CFRetain for Obj-C 2.0 Garbage Collection to disable collection on this object while under Lua control)
				// retain for bridge (using CFRetain for Obj-C 2.0 Garbage Collection to disable collection on this object while under Lua control)
				CFRetain(the_container->theObject);
				// release for alloc (using regular retain for Obj-C 2.0 Garbage Collection. alloc/init only need to be nullified in the gc case, so no-op release is good in gc.)
				[the_container->theObject release];
				// clear the flag
				the_container->needsRelease = true;	
			}

		}
		else
		{
			//			NSLog(@"Looks like we have a different object for init");
			// In this case, we have a brand new object and userdata container that is separate from the old one.
			// The old one is expected to drop out so we can ignore it.
			// Don't need to call CFRetain in this case because PushReturnValue was instructed to CFRetain for us for our bridge.
			// Retain count should now be 2 on the object: 1 for alloc/init, 1 for CFRetain by our bridge
			// We need to release 1 for alloc/init (using regular retain for Obj-C 2.0 Garbage Collection. alloc/init only need to be nullified in the gc case, so no-op release is good in gc.)
			[the_container->theObject release];
		}
			


	}
	else if(parse_support.returnValue.isAlreadyRetained)
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
		// general case. Always try to retain and let the natural logic sort out the mess.
		if(false == is_void_return)
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
//	NSLog(@"number_of_return_values: %d", number_of_return_values); 
//	NSLog(@"top return type %d", lua_type(lua_state, -1));

	return number_of_return_values;
	
}




/**
 * I expect this to be invoked anytime a user tries to invoke a method on our userdata object.
 * e.g. NSString:alloc()
 * Since we aren't preregistering all method names, the access gets routed as a generic table
 * access where the key is the method name string ("alloc" in the above example).
 * Our job is to return a function that Lua can invoke. 
 * Note: we don't actually handle and invoke the function here. Part of the reason is we only
 * see the "key" which is just the method name. We don't see any arguments because we are 
 * not in an actual call.
 * In a chain like NSString:alloc():init(), init() isn't actually seen because it is processed 
 * separately expecting to be combined with whatever we return from the alloc() part.
 * So the solution is essentially recursive and we only need to focus on the first part here.
 */
// obj_index = 2/-1 is key
// obj_index = 1/-2 is userdata object
static int LuaObjectBridge_GetIndexOnClass(lua_State* lua_state)
{
//	NSLog(@"In LuaObjectBridge_GetIndexOnClass");


	LuaUserDataContainerForObject* lua_class_container = LuaObjectBridge_LuaCheckClass(lua_state, 1);



//	NSLog(@"The class: %@", lua_class_container->theObject);
	{
//		NSLog(@"In LuaObjectBridge_GetIndexOnClass:%s", LuaObjectBridge_tostring(lua_state, -1));

		
	}

	// Very special short circuit case for a method named "super".
	// We will return the the same object with the container marked with the isSuper flag marked.
	// This hack is not callable directly from Objective-C, but I assume in Objective-C, the user
	// invokes super directly, e.g. [super dealloc];
	if(0 == strcmp(LuaObjectBridge_tostring(lua_state, -1), "super"))
	{
/*
		NSLog(@"top: %d", lua_gettop(lua_state));
		NSLog(@"the object: %@", lua_class_container->theObject);
		NSLog(@"the string: %s", lua_tostring(lua_state, -1));
*/		
		lua_pushcclosure(lua_state, LuaObjectBridge_InvokeMethod, 1);		
		return 1;
	}
	
	/*
	if(0 == strcmp(LuaObjectBridge_tostring(lua_state, -1), "__ivars"))
	{
		NSLog(@"the string: %s", lua_tostring(lua_state, -1));
		if(LuaObjectBridge_IsLuaSubclass(lua_class_container))
		{
			NSLog(@"subclass");
		}
		else
		{
			NSLog(@"not subclass");
		}


	}
*/
	
	// FIXME: For instances, each object only needs a single env table so we simply need to set.
	// But for classes, we may need to traverse up the class hierarchy.
	if(0 == strcmp(LuaObjectBridge_tostring(lua_state, -1), "__ivars") && LuaObjectBridge_IsLuaSubclass(lua_class_container))
	{
		//		NSLog(@"top: %d", lua_gettop(lua_state));
		//		NSLog(@"the object: %@", lua_class_container->theObject);
		//		NSLog(@"the string: %s", lua_tostring(lua_state, -1));
		
		// Save the ffi_closure in the environment table (so it can be released later)
		// An additional benefit is that if we had an existing closure from a previous set,
		// then the old closure should be released from the table and lua __gc should properly release it.
		
		bool table_exists = LuaCocoaStrongTable_GetLuaSubclassEnvironmentTableInGlobalStrongTable(lua_state, lua_class_container->theObject);
#pragma unused(table_exists)
		lua_getfield(lua_state, -1, "__ivars"); // [__ivars env_table key userdata] 
		return 1;
	}
#warning "Need to re-enable to support Lua-only methods"
	// FIXME: Need to re-enable to support Lua-only methods. But this blocks overridden Obj-C methods from working.
	/*
	if(LuaObjectBridge_IsInstance(lua_class_container) && LuaObjectBridge_IsLuaSubclass(lua_class_container))
	{
		Class which_class_found = NULL;
		bool is_instance_defined = false;
		bool did_find_lua_method = LuaSubclassBridge_FindLuaMethod(lua_state, lua_class_container, lua_tostring(lua_state, -1), &which_class_found, &is_instance_defined);
		if(true == did_find_lua_method)
		{
			return 1;
		}
	}
	*/

//	 int num_args = lua_gettop(lua_state);
//	NSLog(@"num_args in GetIndex: %d", num_args);

	// check for number for NSArray index, do not coerce nsnumber because it may be an object in a dictionary
	if(lua_isnumber(lua_state, 2))
	{
		int the_index = lua_tointeger(lua_state, 2);

//		NSLog(@"Got number in GetIndex: %d", the_index);
		// I am assuming users are not using numbers for method names
		if(LuaObjectBridge_IsInstance(lua_class_container) && [lua_class_container->theObject isKindOfClass:[NSArray class]])
		{
			// Question: Do I adjust indices for counting at 1 instead of 0?
			// adjust index (lua starts at 1, so subtract 1 going to Obj-C)
			the_index = the_index-1;
			if(the_index < 0)
			{
				luaL_error(lua_state, "Illegal index value of %d for NSArray in __newindex", the_index);
			}
			LuaObjectBridge_Pushid(lua_state, [(NSArray*)lua_class_container->theObject objectAtIndex:the_index]);
			return 1;  // return now because we don't want to return a closure (done below)
		 }
		 else
		 {
			 return luaL_error(lua_state, "Number keys for __index only work with NSArray types");
		 }
	 }
	 // Check for string key for Dictionary index. Also try property/dot-notation getter
	 // Do after number check since numbers can be strings
	 else if(lua_isstring(lua_state, 2))
	 {
		 const char* index_string = lua_tostring(lua_state, 2);

		 
//	 NSLog(@"Got string in GetIndex: %s", index_string);
	 	 // FIXME: We want special handling for NSArray and NSDictionary.
		 // NSDictionary might be tricky because we need to differentiate between a objectForKey lookup 
		 // and a method call.
		 // my_dict:foo()
		 // my_dict[foo]
		 // both show up as a string "foo" here.
		 // Strategy: If dictionary, lookup method named "foo" first. If it exists, then invoke function.
		 // Otherwise, treat it as a key lookup.
		 // Reasoning: If both a method and key exist with the same name, we need to do the method 
		 // because it is harder to work around that. With a key, the user can always drop back to objectForKey:
		 
		 // TODO: OPTIMIZE: Since we get all this info, if the method lookup passes, we should pass this info
		 // for performance.
		 if([lua_class_container->theObject isKindOfClass:[NSDictionary class]])
		 {
			 // +1 for NULL and another +1 for optional omitted underscore
			 size_t max_str_length = strlen(index_string)+2;
			 
			 char objc_dst_string[max_str_length];
			 SEL the_selector;
#warning "FIXME: Need to specify class method vs. instance method"
			 if(!ObjectSupport_ConvertUnderscoredSelectorToObjC(objc_dst_string, index_string, max_str_length, lua_class_container->theObject, LuaObjectBridge_IsInstance(lua_class_container), &the_selector, LuaObjectBridge_IsClass(lua_class_container)))
			 {
				 // didn't find a method: treat as key lookup
				 LuaObjectBridge_Pushid(lua_state, [(NSDictionary*)lua_class_container->theObject objectForKey:[NSString stringWithUTF8String:index_string]]);
				 return 1; // return now because we don't want to return a closure (done below)
			 }
			 // fall through to do standard closure stuff
		 }
#if LUAOBJECTBRIDGE_ENABLE_GETTER_DOT_NOTATION
		 // EXPERIMENTAL: Getters (Properties) via dot notation

		 SEL the_selector;
		 bool found_property = false;
		 found_property = ObjectSupport_IsGetterPropertyEquivalent(index_string, lua_class_container->theObject, LuaObjectBridge_IsInstance(lua_class_container), &the_selector);

		 if(found_property)
		 {
//			 NSLog(@"found property: %s in %@", index_string, lua_class_container->theObject);
			 // I think I have found a property (in the loose sense as I want to support anything that is KVC, not just limited to actual declared properties)
			 // So instead of returning a function as the normal codepath,
			 // I want to invoke the getter and return its result.
			 // In order for this to work, the __call metamethod must just return the object (pass through).
			 // I expect the result must be a NSObject based userdata or this won't work correctly.

#if LUAOBJECTBRIDGE_GETTER_DOT_NOTATION_SUPPORT_ONLY_ID_TYPES
			 NSString* return_type_nsstring = ObjectSupport_GetMethodReturnType(lua_class_container->theObject, the_selector, LuaObjectBridge_IsInstance(lua_class_container));
			 __strong const char* objc_return_type = [return_type_nsstring UTF8String];
			 if(_C_ID == objc_return_type[0]) // only care if the first character is an '@'
#endif // LUAOBJECTBRIDGE_GETTER_DOT_NOTATION_SUPPORT_ONLY_ID_TYPES
			 {
				// TODO: OPTIMIZE: we are running ObjectSupport_ConvertUnderscoredSelectorToObjC twice,
				 // once here, and again in LuaObjectBridge_InvokeMethod. It would be nice to cache the values.
				 
				 // Now get ready to invoke the function
				 // Invoke method expects:
				 // 1 for userdata object
				 // Any thing > 1 is an argument
				 // There is also an upvalue for the method name
				 // Currently, our stack from this function is
				 // 1 for userdata object
				 // 2 for key
				 
				 // Ultimately, we want our stack to look like:
				 // [upvalue cclosure userdata key]
				 
				 // I need the lua_method_name (e.g. bar) as the upvalue
				 lua_pushstring(lua_state, index_string);
				 lua_pushcclosure(lua_state, LuaObjectBridge_InvokeMethod, 1);
				 
				 lua_pushvalue(lua_state, 1); // copy userdata from position 1 to the current top
				 
				 // Invoke it. It should return 1 value that is a userdata
				 lua_call(lua_state, 1, 1);
//				 NSLog(@"returned from property invoke: %d", lua_type(lua_state, -1));
//				 id test_id = LuaObjectBridge_checkid(lua_state, -1);
//				 NSLog(@"test_id: %@", test_id);
				 
				 // Return the result back to lua which should be an id userdata.
				 // Now it is up to __call if the user put () after it
				 return 1;
			 }
			 
			 // fall through to do standard closure stuff
		 }

#endif // LUAOBJECTBRIDGE_ENABLE_GETTER_DOT_NOTATION

		 // fall through to do standard closure stuff

	 }
	 // Key is userdata which may be an object.
	 // This could be a NSString, NSNumber, or any NSObject which are valid in dictionaries
	 else if(lua_isuserdata(lua_state, 2))
	 {
		 // Try NSDictionary before NSArray because NSNumber as index is unusual at not allowed in real Cococa without explicit coercion.
		 if(LuaObjectBridge_IsInstance(lua_class_container) && [lua_class_container->theObject isKindOfClass:[NSDictionary class]])
		 {
			id the_key = LuaObjectBridge_checkid(lua_state, 2);

			 LuaObjectBridge_Pushid(lua_state, [(NSDictionary*)lua_class_container->theObject objectForKey:the_key]);
			 return 1;  // return now because we don't want to return a closure (done below)
		 }
		 // Now that dictionary has passed, we can try NSArray
		 else if(LuaObjectBridge_IsInstance(lua_class_container) && [lua_class_container->theObject isKindOfClass:[NSArray class]])
		 {
			 LuaUserDataContainerForObject* lua_class_container = LuaObjectBridge_LuaCheckClass(lua_state, 2);
//			 id the_key = LuaObjectBridge_checkid(lua_state, 2);
			 id the_key = lua_class_container->theObject;

			 if(!LuaObjectBridge_IsInstance(lua_class_container) && ![the_key isKindOfClass:[NSNumber class]])
			 {
				 return luaL_error(lua_state, "Unexpected key type for __index on NSArray with userdata index");
			 }
			 
			 // Question: Do I adjust indices for counting at 1 instead of 0?
			 // adjust index (lua starts at 1, so subtract 1 going to Obj-C)
			 LuaObjectBridge_Pushid(lua_state, [(NSArray*)lua_class_container->theObject objectAtIndex:[the_key unsignedIntegerValue]-1]);
			 return 1;  // return now because we don't want to return a closure (done below)
		 }
		 else if(LuaObjectBridge_IsInstance(lua_class_container) && LuaObjectBridge_isnsstring(lua_state, 2))
		 {
			 // we have a nsstring key. try it as a property
#if LUAOBJECTBRIDGE_ENABLE_GETTER_DOT_NOTATION
			 // EXPERIMENTAL: Getters (Properties) via dot notation
			 NSString* property_name = LuaObjectBridge_tonsstring(lua_state, 2);
			 SEL the_selector;
			 Method the_method;
			 bool found_property = false;
			 found_property = ObjectSupport_IsGetterPropertyEquivalent([property_name UTF8String], lua_class_container->theObject, &the_selector, &the_method);
			 
			 if(found_property)
			 {
				 // I think I have found a property (in the loose sense as I want to support anything that is KVC, not just limited to actual declared properties)
				 // So instead of returning a function as the normal codepath,
				 // I want to invoke the getter and return its result.
				 // In order for this to work, the __call metamethod must just return the object (pass through).
				 // I expect the result must be a NSObject based userdata or this won't work correctly.
				 
#if LUAOBJECTBRIDGE_GETTER_DOT_NOTATION_SUPPORT_ONLY_ID_TYPES
				 char objc_return_type[2]; // only care if the first character is an '@'
				 method_getReturnType(the_method, objc_return_type, 2);
				 if(_C_ID == objc_return_type[0])
#endif // LUAOBJECTBRIDGE_GETTER_DOT_NOTATION_SUPPORT_ONLY_ID_TYPES
				 {
					 // TODO: OPTIMIZE: we are running ObjectSupport_ConvertUnderscoredSelectorToObjC twice,
					 // once here, and again in LuaObjectBridge_InvokeMethod. It would be nice to cache the values.
					 
					 // Now get ready to invoke the function
					 // Invoke method expects:
					 // 1 for userdata object
					 // Any thing > 1 is an argument
					 // There is also an upvalue for the method name
					 // Currently, our stack from this function is
					 // 1 for userdata object
					 // 2 for key
					 
					 // Ultimately, we want our stack to look like:
					 // [upvalue cclosure userdata key]
					 
					 // I need the lua_method_name (e.g. bar) as the upvalue
					 lua_pushstring(lua_state, [property_name UTF8String]);
					 lua_pushcclosure(lua_state, LuaObjectBridge_InvokeMethod, 1);
					 
					 lua_pushvalue(lua_state, 1); // copy userdata from position 1 to the current top
					 
					 // Invoke it. It should return 1 value that is a userdata
					 lua_call(lua_state, 1, 1);
//					 NSLog(@"returned from property invoke: %d", lua_type(lua_state, -1));
//					 id test_id = LuaObjectBridge_checkid(lua_state, -1);
//					 NSLog(@"test_id: %@", test_id);
					 
					 // Return the result back to lua which should be an id userdata.
					 // Now it is up to __call if the user put () after it
					 return 1;
				 }
				 
				 // fall through to do standard closure stuff
			 }
			 
#endif // LUAOBJECTBRIDGE_ENABLE_GETTER_DOT_NOTATION
			 
		 }
		 // fall through to do standard closure stuff
	 }
	 else
	 {
		 luaL_error(lua_state, "Unexpected key type for __index");
	 }
	 
	 	

	// One important thing to note is that we are pushing the key name as a closure value to the function that we return.
	// This is because Lua won't pass the name of the function to the function itself so we won't know
	// which Obj-C method to look up when we get to the invocation code.
	
	// Create a new closure (function) to be returned which will be invoked.
	// It includes an upvalue containing the "key" (method name) so we can retrieve it later
	// The assumption is that this string (key) is on the top of the stack.
	lua_pushcclosure(lua_state, LuaObjectBridge_InvokeMethod, 1);

	return 1;
}

static int LuaObjectBridge_GarbageCollect(lua_State* lua_state)
{
	LuaUserDataContainerForObject* lua_class_container = LuaObjectBridge_LuaCheckClass(lua_state, 1);
	id the_object = lua_class_container->theObject;
	if(lua_class_container->needsRelease)
	{
//		NSLog(@"LuaObjectBridge_GarbageCollect, CFReleasing object: 0x%x", the_object);
		CFRelease(the_object);
	}
	return 0;
}

static const struct luaL_reg LuaObjectBridge_MethodsForClassMetatable[] =
{
	// TODO: Complete list: http://lua-users.org/wiki/MetatableEvents
	{"__tostring", LuaObjectBridge_ToString},
	{"__tonumber", LuaObjectBridge_ToNumber},
	{"__eq", LuaObjectBridge_IsEqual},
	{"__len", LuaObjectBridge_GetLength},
	{"__concat", LuaObjectBridge_Concat},
	{"__call", LuaObjectBridge_Call},
	{"__index", LuaObjectBridge_GetIndexOnClass},
	{"__newindex", LuaObjectBridge_SetIndexOnClass},
	{"__gc", LuaObjectBridge_GarbageCollect},
	{NULL,NULL},
};


int luaopen_LuaObjectBridge(lua_State* lua_state)
{
	luaL_newmetatable(lua_state, LUACOCOA_OBJECT_METATABLE_ID);
	//	lua_pushvalue(lua_state, -1);
	//	lua_setfield(lua_state, -2, "__index");
	luaL_register(lua_state, NULL, LuaObjectBridge_MethodsForClassMetatable);
	
	return 1;
}


// will create a new userdata container for the object and push it on the stack.
static void LuaObjectBridge_CreateUserData(lua_State* lua_state, id the_object, bool should_retain, bool is_instance, bool is_super)
{
	// Create the new container
	void* return_class_userdata = lua_newuserdata(lua_state, sizeof(LuaUserDataContainerForObject));
	LuaUserDataContainerForObject* lua_class_container = (LuaUserDataContainerForObject*)return_class_userdata;
	
	// Set the metatable identifier on our new userdata
	luaL_getmetatable(lua_state, LUACOCOA_OBJECT_METATABLE_ID);
	lua_setmetatable(lua_state, -2);	
	

	// Add the object to the container
	lua_class_container->theObject = the_object;
	lua_class_container->isInstance = is_instance;
	lua_class_container->needsRelease = false;
	lua_class_container->isLuaSubclass = false;
	lua_class_container->isSuper = is_super;
	lua_class_container->superClass = NULL;

	// I only need to retain instances, not classes.
	// How do I distinguish Core Foundation instances?
	if(should_retain)
	{
		// We use CFRetain instead of retain because of Objective-C 2.0 garbage collection
		CFRetain(the_object);
		lua_class_container->needsRelease = true;
	}
	
	if(false == is_super)
	{
		if(true == is_instance)
		{
			// Make sure there is no super version in the global table
			void* super_userdata = LuaCocoaWeakTable_GetObjectInGlobalWeakTableForSuper(lua_state, the_object);
			// If it is there, we need to share the environmental table
			if(NULL != super_userdata)
			{
				// Stack: [super_userdata new_userdata]
				
				// Get the environment table from the super userdata
				lua_getfenv(lua_state, -1); // stack: [super-envtable super-userdata new-userdata]
				
				// Set the new-nonsuper-userdata's environment table to share the same one as the super-userdata
				lua_setfenv(lua_state, -2); // stack: [super-userdata new-userdata]
				
				lua_pop(lua_state, 1); // pop the super-userdata so we can return the new userdata on top of the stack
			}
			else
			{
				lua_pop(lua_state, 1); // pop the nil from LuaCocoaWeakTable_GetObjectInGlobalWeakTableForSuper

				if(LuaSubclassBridge_IsObjectSubclassInLua(the_object))
				{
/*
					bool table_exists = LuaCocoaStrongTable_GetLuaSubclassEnvironmentTableInGlobalStrongTable(lua_state, the_object);
					if(false == table_exists)
					{
						lua_pop(lua_state, 1); // pop LuaCocoaStrongTable_GetLuaSubclassEnvironmentTableInGlobalStrongTable
						if(!ObjectSupport_IsSubclassOfClass(object_getClass(the_object), objc_getClass("LuaCocoaProxyObject")))
						{
						
							NSLog(@"FIXME in LuaObjectBridge_CreateUserData: Expecting a LuaCocoaProxyObject. Crap: We might need a strong reference after all. Bailing...");
							return;
						}
						// NOTE: Non-LuaCocoaProxyObject's can't call this method.
						[the_object setLuaStateForLuaCocoaProxyObject:lua_state]; // This should create a new table
						table_exists = LuaCocoaStrongTable_GetLuaSubclassEnvironmentTableInGlobalStrongTable(lua_state, the_object); // try again
						assert(table_exists);
					}
					lua_setfenv(lua_state, -2); // set the new table as the environment table
*/
					LuaSubclassBridge_SetLuaStateFromLuaSubclassObject(lua_state, the_object);
				}
				else
				{
					// I want a clean environment table
					// Make the new table the new environment table
					// setfenv pops
					lua_newtable(lua_state); // create new table for environment table

					lua_newtable(lua_state); // create new table for methods table
					lua_setfield(lua_state, -2, "__methods"); // environment_table["__methods"] = new_table

					lua_newtable(lua_state); // create new table for method signature table
					lua_setfield(lua_state, -2, "__signatures"); // environment_table["__signatures"] = new_table

					lua_newtable(lua_state); // create new table for ivars table
					lua_setfield(lua_state, -2, "__ivars"); // environment_table["__ivars"] = new_table

					// Don't create ffi_closure table for instances
/*
//					lua_newtable(lua_state); // create new table for closures table
//					lua_setfield(lua_state, -2, "__fficlosures"); // environment_table["__methods"] = new_table
*/					
					lua_setfenv(lua_state, -2); // set the new table as the environment table
				}
			}
		}
		else
		{
			// I want a clean environment table
			// Make the new table the new environment table
			// setfenv pops
			lua_newtable(lua_state); // create new table for environment table
			
			lua_newtable(lua_state); // create new table for methods table
			lua_setfield(lua_state, -2, "__methods"); // environment_table["__methods"] = new_table
			
			lua_newtable(lua_state); // create new table for method signature table
			lua_setfield(lua_state, -2, "__signatures"); // environment_table["__signatures"] = new_table
			
			lua_newtable(lua_state); // create new table for ivars table
			lua_setfield(lua_state, -2, "__ivars"); // environment_table["__ivars"] = new_table
			
			lua_newtable(lua_state); // create new table for ffi_closures table
			lua_setfield(lua_state, -2, "__fficlosures"); // environment_table["__methods"] = new_table

			lua_setfenv(lua_state, -2); // set the new table as the environment table
		}
	}
	else
	{
		// The super case has a few more preconditions.
		// If the normal (non-super object) is already we must share the environment table with the new super object.
		// This is because the environment table may contain custom ivars or methods for the instance which 
		// need to be accessible when dealing with the super version of the instance.
		
		// Stack: [new_userdata]

		void* userdata_for_non_super = LuaCocoaWeakTable_GetObjectInGlobalWeakTable(lua_state, the_object);
		if(NULL != userdata_for_non_super)
		{
			// Stack: [base_userdata new_userdata]
			
			// Get the environment table from the super userdata
			lua_getfenv(lua_state, -1); // stack: [base-envtable base-userdata new-userdata]
			
			// Set the new-nonsuper-userdata's environment table to share the same one as the super-userdata
			lua_setfenv(lua_state, -2); // stack: [base-userdata new-userdata]
			
			lua_pop(lua_state, 1); // pop the non-super-userdata so we can return the new userdata on top of the stack
		}
		else
		{
			lua_pop(lua_state, 1); // pop the nil from LuaCocoaWeakTable_GetObjectInGlobalWeakTable
			
			// I want a clean environment table
			// Make the new table the new environment table
			// setfenv pops
			lua_newtable(lua_state); // create new table for environment table
			
			lua_newtable(lua_state); // create new table for methods table
			lua_setfield(lua_state, -2, "__methods"); // environment_table["__methods"] = new_table
			
			lua_newtable(lua_state); // create new table for method signature table
			lua_setfield(lua_state, -2, "__signatures"); // environment_table["__signatures"] = new_table
			
			lua_newtable(lua_state); // create new table for ivars table
			lua_setfield(lua_state, -2, "__ivars"); // environment_table["__ivars"] = new_table
			
			lua_newtable(lua_state); // create new table for closures table
			lua_setfield(lua_state, -2, "__fficlosures"); // environment_table["__methods"] = new_table

			lua_setfenv(lua_state, -2); // set the new table as the environment table
		}
	}
}

// Will push an existing lua container userdata onto the stack for the associated object,
// or will create a new userdata container for the object if it does not exist and push it on the stack.
static void LuaObjectBridge_PushOrCreateUserData(lua_State* lua_state, id the_object, bool should_retain, bool is_instance, bool is_super)
{
	if(nil == the_object)
	{
		lua_pushnil(lua_state);
		return;
	}

	// Do not pass in a class that is marked as super. (You should pass in the actual super class instead.)
	assert(!(true == is_super && false == is_instance));

	if(false == is_super)
	{
		
		// First check to see if we already have the object in our global weak table.
		// This will leave the userdata or nil on top of the stack
		void* return_userdata = LuaCocoaWeakTable_GetObjectInGlobalWeakTable(lua_state, the_object);
		
		// If it is not there, we need to create the new userdata container
		if(NULL == return_userdata)
		{
	//		NSLog(@"PushID did not find object in our weak table");

			lua_pop(lua_state, 1); // pop the nil value left from LuaCocoaWeakTable_GetObjectInGlobalWeakTable

			// Will create the new userdata and leave it on the stack
			LuaObjectBridge_CreateUserData(lua_state, the_object, should_retain, is_instance, is_super);

			// finally, add this container and object to the global weak table
			LuaCocoaWeakTable_InsertObjectInGlobalWeakTable(lua_state, -1, the_object);


		}

	}
	else
	{
#if 0 // Needed to violate uniqueness rule for super
		// First check to see if we already have the object in our global weak table.
		// This will leave the userdata or nil on top of the stack
		void* return_userdata = LuaCocoaWeakTable_GetObjectInGlobalWeakTableForSuper(lua_state, the_object);
		
		// If it is not there, we need to create the new userdata container
		if(NULL == return_userdata)
		{
		
			lua_pop(lua_state, 1); // pop the nil value left from LuaCocoaWeakTable_GetObjectInGlobalWeakTableForSuper
			
			// Will create the new userdata and leave it on the stack
			LuaObjectBridge_CreateUserData(lua_state, the_object, should_retain, is_instance, is_super);
			
			// finally, add this container and object to the global weak table for super
			LuaCocoaWeakTable_InsertObjectInGlobalWeakTableForSuper(lua_state, -1, the_object);
			
			// Need to set the is_lua_class flag. Use the non-super object as the source.
			// First, get a pointer to the new object since we know where it is.
			LuaUserDataContainerForObject* super_container = lua_touserdata(lua_state, -1);
			
			
			// First check to see if we already have the object in our global weak table.
			// This will leave the userdata or nil on top of the stack
			LuaUserDataContainerForObject* base_container = (LuaUserDataContainerForObject*)LuaCocoaWeakTable_GetObjectInGlobalWeakTable(lua_state, the_object);
			
			// If it is not there, we need to create the new userdata container
			if(NULL == base_container)
			{
				// FIXME: Should use ivar or method existance check to verify
				NSLog(@"Can't find base object to set isSuper flag");
			}
			else
			{
				super_container->isLuaSubclass = base_container->isLuaSubclass;
				//			super_container->superClass = base_container->superClass;
			}
			lua_pop(lua_state, 1); // pop LuaCocoaWeakTable_GetObjectInGlobalWeakTable
		}
#else
		// Will create the new userdata and leave it on the stack
		LuaObjectBridge_CreateUserData(lua_state, the_object, should_retain, is_instance, is_super);
		LuaUserDataContainerForObject* super_container = lua_touserdata(lua_state, -1);

		// First check to see if we already have the object in our global weak table.
		// This will leave the userdata or nil on top of the stack
		LuaUserDataContainerForObject* base_container = (LuaUserDataContainerForObject*)LuaCocoaWeakTable_GetObjectInGlobalWeakTable(lua_state, the_object);
		
		// If it is not there, we need to create the new userdata container
		if(NULL == base_container)
		{
			// FIXME: Should use ivar or method existance check to verify
			NSLog(@"Can't find base object to set isSuper flag");
		}
		else
		{
			super_container->isLuaSubclass = base_container->isLuaSubclass;
			//			super_container->superClass = base_container->superClass;
		}
		lua_pop(lua_state, 1); // pop LuaCocoaWeakTable_GetObjectInGlobalWeakTable

#endif		


	}

}



// Will push an object onto the lua stack (implicitly has container for it)
void LuaObjectBridge_Pushid(lua_State* lua_state, id the_object)
{
	// always try to retain. Generally this is what you want to do with calls to alloc* being the only exceptions.
	LuaObjectBridge_PushOrCreateUserData(lua_state, the_object, true, true, false);
}

// Will push an object onto the lua stack (implicitly has container for it)
void LuaObjectBridge_PushidWithRetainOption(lua_State* lua_state, id the_object, bool should_retain)
{
	LuaObjectBridge_PushOrCreateUserData(lua_state, the_object, should_retain, true, false);
}

// Will push an object onto the lua stack (implicitly has container for it)
void LuaObjectBridge_PushClass(lua_State* lua_state, Class the_class)
{
	// always try to retain. Generally this is what you want to do with calls to alloc* being the only exceptions.
	LuaObjectBridge_PushOrCreateUserData(lua_state, the_class, true, false, false);
}

// Will push an object onto the lua stack (implicitly has container for it)
void LuaObjectBridge_PushSuperid(lua_State* lua_state, id the_object)
{
	// always try to retain. Generally this is what you want to do with calls to alloc* being the only exceptions.
	LuaObjectBridge_PushOrCreateUserData(lua_state, the_object, true, true, true);
}

// Used to create class references in Lua so people can do things like: CALayer:alloc()
void LuaObjectBridge_CreateNewClassUserdata(lua_State* lua_state, NSString* class_name)
{
	// Not sure if I should use objc_getClass or objc_lookUpClass
	id the_class = objc_getClass([class_name UTF8String]);
	
	// FIXME: Consider supporting namespaces
	lua_pushvalue(lua_state, LUA_GLOBALSINDEX);		
	lua_pushstring(lua_state, [class_name UTF8String]);  /* Add variable name. */

	// I don't think I need to retain because this is for class objects, not instances
	LuaObjectBridge_PushOrCreateUserData(lua_state, the_class, false, false, false);

	lua_settable(lua_state, -3);

	lua_pop(lua_state, 1);


}

