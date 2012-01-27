//
//  LuaSelectorBridge.m
//  LuaCocoa
//
//  Created by Eric Wing on 11/11/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//
#import <Foundation/Foundation.h>

#import "LuaSelectorBridge.h"
#include "LuaCocoaWeakTable.h"
#include "lua.h"
#include "lauxlib.h"
#import "LuaObjectBridge.h"

const char* LUACOCOA_SELECTOR_METATABLE_ID = "LuaCocoa.Selector";


// returns pointer if a LuaCocoa.Selector, null otherwise
static LuaUserDataContainerForSelector* LuaSelectorBridge_LuaIsSelector(lua_State *L, int stack_index)
{
	void *p = lua_touserdata(L, stack_index);
	if (p != NULL) {  /* value is a userdata? */
		if (lua_getmetatable(L, stack_index))
		{  /* does it have a metatable? */
			lua_getfield(L, LUA_REGISTRYINDEX, LUACOCOA_SELECTOR_METATABLE_ID);  /* get correct metatable */
			if (lua_rawequal(L, -1, -2))
			{  /* does it have the correct mt? */
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


// returns pointer if LuaCocoa.Object, lua_error otherwise
static LuaUserDataContainerForSelector* LuaSelectorBridge_LuaCheckSelectorContainer(lua_State* lua_state, int stack_index)
{
	return luaL_checkudata(lua_state, stack_index, LUACOCOA_SELECTOR_METATABLE_ID);
}



bool LuaSelectorBridge_isselector(lua_State* lua_state, int stack_index)
{
	// Check if boxed NSValue
	if(LuaObjectBridge_isidinstance(lua_state, stack_index))
	{
		id the_object = LuaObjectBridge_toid(lua_state, stack_index);
		if([the_object isKindOfClass:[NSValue class]])
		{
			if(!strcmp([the_object objCType], @encode(SEL)))
			{
				return true;
			}
			else
			{
				return false;
			}
		}
		else
		{
			return false;
		}
	}
	
	LuaUserDataContainerForSelector* the_container = LuaSelectorBridge_LuaIsSelector(lua_state, stack_index);
	if(NULL == the_container)
	{
		return false;
	}
	else
	{
		return true;
	}
}

SEL LuaSelectorBridge_checkselector(lua_State* lua_state, int stack_index)
{
	// Will handle both string and NSString
	if(LuaObjectBridge_isnsstring(lua_state, stack_index))
	{
		return NSSelectorFromString(LuaObjectBridge_tonsstring(lua_state, stack_index));
	}
	// Check if boxed NSValue
	if(LuaObjectBridge_isidinstance(lua_state, stack_index))
	{
		id the_object = LuaObjectBridge_toid(lua_state, stack_index);
		if([the_object isKindOfClass:[NSValue class]])
		{
			if(!strcmp([the_object objCType], @encode(SEL)))
			{
				SEL return_selector;
				[the_object getValue:&return_selector];
				return return_selector;
			}
			else
			{
				luaL_error(lua_state, "Not an selector type in NSValue");
			}
		}
		else
		{
			luaL_error(lua_state, "Not an instance type");
		}
	}
	
	LuaUserDataContainerForSelector* the_container = LuaSelectorBridge_LuaCheckSelectorContainer(lua_state, stack_index);
	return the_container->theSelector;
}


// Warning: will convert strings and nsstrings and NSValue's with correct encoding to selectors
SEL LuaSelectorBridge_toselector(lua_State* lua_state, int stack_index)
{
	// Will handle both string and NSString
	if(LuaObjectBridge_isnsstring(lua_state, stack_index))
	{
		return NSSelectorFromString(LuaObjectBridge_tonsstring(lua_state, stack_index));
	}
	// Check if boxed NSValue
	if(LuaObjectBridge_isidinstance(lua_state, stack_index))
	{
		id the_object = LuaObjectBridge_toid(lua_state, stack_index);
		if([the_object isKindOfClass:[NSValue class]])
		{
			if(!strcmp([the_object objCType], @encode(SEL)))
			{
				SEL return_selector;
				[the_object getValue:&return_selector];
				return return_selector;
			}
			else
			{
				return NULL;
			}
		}
		else
		{
			return NULL;
		}
	}
		
	LuaUserDataContainerForSelector* the_container = LuaSelectorBridge_LuaIsSelector(lua_state, stack_index);
	if(NULL == the_container)
	{
		return NULL;
	}
	return the_container->theSelector;
}



// Will push an existing lua container userdata onto the stack for the associated object,
// or will create a new userdata container for the object if it does not exist and push it on the stack.
static void LuaSelectorBridge_PushOrCreateUserData(lua_State* lua_state, SEL the_selector)
{
	if(NULL == the_selector)
	{
		lua_pushnil(lua_state);
		return;
	}
	
	// First check to see if we already have the object in our global weak table.
	// This will leave the userdata or nil on top of the stack
	void* return_class_userdata = LuaCocoaWeakTable_GetObjectInGlobalWeakTable(lua_state, the_selector);
	
	// If it is not there, we need to create the new userdata container
	if(NULL == return_class_userdata)
	{
		lua_pop(lua_state, 1); // pop the nil value left from LuaCocoaWeakTable_GetObjectInGlobalWeakTable
		
		// Create the new container
		void* return_selector_userdata = lua_newuserdata(lua_state, sizeof(LuaUserDataContainerForSelector));
		LuaUserDataContainerForSelector* lua_selector_container = (LuaUserDataContainerForSelector*)return_selector_userdata;
		
		// Set the metatable identifier on our new userdata
		luaL_getmetatable(lua_state, LUACOCOA_SELECTOR_METATABLE_ID);
		lua_setmetatable(lua_state, -2);	
		
		// Add the object to the container
		lua_selector_container->theSelector = the_selector;
		
		// finally, add this container and object to the global weak table
		LuaCocoaWeakTable_InsertObjectInGlobalWeakTable(lua_state, -1, the_selector);
		
	}
	else
	{
		//		NSLog(@"PushID Found object in our weak table");
	}
}



void LuaSelectorBridge_pushselector(lua_State* lua_state, SEL the_selector)
{
	LuaSelectorBridge_PushOrCreateUserData(lua_state, the_selector);
}


static int LuaSelectorBridge_ToString(lua_State* lua_state)
{
	LuaUserDataContainerForSelector* lua_class_container = LuaSelectorBridge_LuaCheckSelectorContainer(lua_state, -1);

	lua_pushstring(lua_state, [NSStringFromSelector(lua_class_container->theSelector) UTF8String]);
	return 1;
}

/* FIXME: This function won't work unless I change the global weak table to reflect the new selector address.
 
static int LuaSelectorBridge_Call(lua_State* lua_state)
{
	LuaUserDataContainerForSelector* lua_class_container = LuaSelectorBridge_LuaCheckSelectorContainer(lua_state, -1);
	// TODO: Probably should check the number of arguments
	NSString* new_string = LuaObjectBridge_checknsstring(lua_state, -1);
	// This line will break things without changes to the weak table
	lua_class_container->theSelector = NSSelectorFromString(new_string);
	return 0;
}
*/

static int LuaSelectorBridge_ToSelector(lua_State* lua_state)
{
	NSString* the_string = LuaObjectBridge_checknsstring(lua_state, -1);
	LuaSelectorBridge_pushselector(lua_state, NSSelectorFromString(the_string));
	return 1;
}




static const struct luaL_reg LuaSelectorBridge_MethodsForSelectorMetatable[] =
{
	// Don't think I need much for selectors.
	{"__tostring", LuaSelectorBridge_ToString},
//	{"__call", LuaSelectorBridge_Call},
	// For __eq, since we use the global weak table to unique things, I think the default comparison will just work.
	// If not, I think I read Obj-C makes SEL's unique so it is just a simple pointer comparison there too.
//	{"__eq", LuaSelectorBridge_IsEqual},
	// I don't have to worry about memory management with selectors
//	{"__gc", LuaSelectorBridge_GarbageCollect},
	{NULL,NULL},
};

static const luaL_reg LuaSelectorBridge_LuaFunctions[] = 
{
	{"toselector", LuaSelectorBridge_ToSelector},
	
	{NULL,NULL},
};


int luaopen_LuaSelectorBridge(lua_State* lua_state)
{
	luaL_newmetatable(lua_state, LUACOCOA_SELECTOR_METATABLE_ID);
	//	lua_pushvalue(lua_state, -1);
	//	lua_setfield(lua_state, -2, "__index");
	luaL_register(lua_state, NULL, LuaSelectorBridge_MethodsForSelectorMetatable);
	
	luaL_register(lua_state, "LuaCocoa", LuaSelectorBridge_LuaFunctions);

	
	return 1;
}