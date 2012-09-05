//
//  LuaCocoaStrongTable.m
//  LuaCocoa
//
//  Created by Eric Wing on 11/15/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#include "LuaCocoaStrongTable.h"
#include "lua.h"
#include <assert.h>
#include <stdbool.h>
//#import "LuaCocoaProxyObject.h" // hack
#import <objc/runtime.h> // hack
#import "ObjectSupport.h" // hack
#import "LuaSubclassBridge.h"

#define LUACOCOA_OBJECT_GLOBAL_STRONG_TABLE_ID "LuaCocoa.GlobalStrongTable"
#define LUACOCOA_OBJECT_GLOBAL_STRONG_TABLE_FOR_ENVIRONMENT_TABLES_FOR_LUASUBCLASSES_ID "LuaCocoa.GlobalStrongTable.ForEnvironmentTablesForLuaSubclasses"
#define LUACOCOA_OBJECT_GLOBAL_TABLE_FOR_ENVIRONMENT_TABLES_FOR_LUASUBCLASSES_FOR_INNER_NONPROXY_ID "LuaCocoa.GlobalTable.ForEnvironmentTablesForLuaSubclassesForInnerNonProxy"


// Maps lightuserdata to (weak) container objects holding NSObjects, selectors, 
// and anything that has userdata containers around pointers.
// Allows for having unique containers (i.e. for the same NSObject, reuse the same containers)
void LuaCocoaStrongTable_CreateGlobalStrongObjectTable(lua_State* lua_state)
{
	// Push our key for the global registry for our weak table (so we can fetch the table later)
	lua_pushliteral(lua_state, LUACOCOA_OBJECT_GLOBAL_STRONG_TABLE_ID);
	
	// Now create (push) our strong table
	lua_newtable(lua_state);
	lua_pushvalue(lua_state, -1);  // table is its own metatable
	lua_setmetatable(lua_state, -2);
	
	// Now that we've created a new table, put it in the global registry
	lua_settable(lua_state, LUA_REGISTRYINDEX); /* registry[LUACOCOA_OBJECT_GLOBAL_STRONG_TABLE_ID] = strong_table */
	
	// hmmm...I kind of expected needing a lua_pop(lua_state, 1); here to balance the stack, but it's already balanced.



	// Push our key for the global registry for our weak table (so we can fetch the table later)
	lua_pushliteral(lua_state, LUACOCOA_OBJECT_GLOBAL_STRONG_TABLE_FOR_ENVIRONMENT_TABLES_FOR_LUASUBCLASSES_ID);
	
	// Now create (push) our strong table
	lua_newtable(lua_state);
	lua_pushvalue(lua_state, -1);  // table is its own metatable
	lua_setmetatable(lua_state, -2);
	
	// Now that we've created a new table, put it in the global registry
	lua_settable(lua_state, LUA_REGISTRYINDEX); /* registry[LUACOCOA_OBJECT_GLOBAL_STRONG_TABLE_FOR_ENVIRONMENT_TABLES_FOR_LUASUBCLASSES_ID] = strong_table */
	
	// hmmm...I kind of expected needing a lua_pop(lua_state, 1); here to balance the stack, but it's already balanced.
	
	
	
	// HACK: I am normally expecting to put LuaCocoaProxyObject's in this table.
	// But I have a corner case for super where the object is not in the wrapper, but I still want to be able to get the
	// environmental table. So, for this case, I will also put the inner object in the table as a key 
	// if the object is a LuaCocoaProxyObject.
	
	// Push our key for the global registry for our weak table (so we can fetch the table later)
	// I am using a weak table because for non-proxy objects, I am a little worried about those objects not cleaning up after themselves.
	// My theory is that there should be a Proxy object with real environmental table already, so I just need to be able to find it.
	// If this isn't true, then the table risks being collected before we have a strong reference to it which may be a bug
	// (depending if there is useful information in the table or just an empty table).
	lua_pushliteral(lua_state, LUACOCOA_OBJECT_GLOBAL_TABLE_FOR_ENVIRONMENT_TABLES_FOR_LUASUBCLASSES_FOR_INNER_NONPROXY_ID);
	
	// Now create (push) our weak table
	lua_newtable(lua_state);
	lua_pushvalue(lua_state, -1);  // table is its own metatable
	lua_setmetatable(lua_state, -2);
	lua_pushliteral(lua_state, "__mode");
	lua_pushliteral(lua_state, "kv"); // make values weak, I don't think lightuserdata is strong ref'd so 'k' is optional.
	lua_settable(lua_state, -3);   // metatable.__mode = "v"
	
	// Now that we've created a new table, put it in the global registry
	lua_settable(lua_state, LUA_REGISTRYINDEX); /* registry[LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_ID] = weak_table */
	
	
}

/**
 * @stack_position_of_userdata Where the userdata (LuaUserDataContainerForObject*) for the new object is in the Lua stack.
 * @the_object The raw Objective-C object/pointer (no lua container). Will use as the key (light userdata) the strong table.
 * Object is defined loosely as we currently use anything with a container including NSObjects and selectors.
 * I think it will actually work with any thing that is a pointer.
 */
void LuaCocoaStrongTable_InsertObjectInGlobalStrongTable(lua_State* lua_state, int stack_position_of_userdata, void* the_object)
{
	int top0 = lua_gettop(lua_state);
	lua_getfield(lua_state, LUA_REGISTRYINDEX, LUACOCOA_OBJECT_GLOBAL_STRONG_TABLE_ID); // puts the global strong table on top of the stack
	
	lua_pushlightuserdata(lua_state, the_object); // stack: [object_ptr strong_table]
	if(stack_position_of_userdata < 0)
	{
		// Because we pushed more items on the stack, we need to compensate for the changed relative stack index
		lua_pushvalue(lua_state, stack_position_of_userdata - 2); // stack: [userdata_container object_ptr strong_table]
	}
	else
	{
		// absolute stack positions don't change
		lua_pushvalue(lua_state, stack_position_of_userdata); // stack: [userdata_container object_ptr strong_table]	
	}
	
	lua_settable(lua_state, -3); // strong_table[object_ptr] = userdata_container
	
	// table is still on top of stack. Don't forget to pop it now that we are done with it
	lua_pop(lua_state, 1);
	int top1 = lua_gettop(lua_state);
	assert(top0 == top1);
}



/* Leaves result on the stack. Don't forget to pop when done.
 */
void* LuaCocoaStrongTable_GetObjectInGlobalStrongTable(lua_State* lua_state, void* the_object)
{
	// The block implmentation is currently identical except it doesn't return any values so we can build on top of it.
	LuaCocoaStrongTable_GetLuaFunctionValueForBlockCleanupKeyInGlobalStrongTable(lua_state, the_object);
	
	if(lua_isnil(lua_state, -1))
	{
		return NULL;
	}
	else
	{
		return lua_touserdata(lua_state, -1);
	}
}


void LuaCocoaStrongTable_RemoveObjectInGlobalStrongTable(lua_State* lua_state, void* the_object)
{	
	lua_pushnil(lua_state);
	LuaCocoaStrongTable_InsertObjectInGlobalStrongTable(lua_state, -1, the_object);
	lua_pop(lua_state, 1);
}

/**
 * @stack_position_of_table Where the table for the new object is in the Lua stack.
 * @the_object The raw Objective-C object/pointer (no lua container). Will use as the key (light userdata) the strong table.
 * Object is defined loosely as we currently use anything with a container including NSObjects and selectors.
 * I think it will actually work with any thing that is a pointer.
 */
void LuaCocoaStrongTable_InsertLuaSubclassEnvironmentTableInGlobalStrongTable(lua_State* lua_state, int stack_position_of_table, void* the_object)
{
	int top0 = lua_gettop(lua_state);
	lua_getfield(lua_state, LUA_REGISTRYINDEX, LUACOCOA_OBJECT_GLOBAL_STRONG_TABLE_FOR_ENVIRONMENT_TABLES_FOR_LUASUBCLASSES_ID); // puts the global strong table on top of the stack
//	printf("creating table with key: 0x%x", the_object);
	lua_pushlightuserdata(lua_state, the_object); // stack: [object_ptr strong_table]
	if(stack_position_of_table < 0)
	{
		// Because we pushed more items on the stack, we need to compensate for the changed relative stack index
		lua_pushvalue(lua_state, stack_position_of_table - 2); // stack: [userdata_container object_ptr strong_table]
	}
	else
	{
		// absolute stack positions don't change
		lua_pushvalue(lua_state, stack_position_of_table); // stack: [userdata_container object_ptr strong_table]	
	}
	
	lua_settable(lua_state, -3); // strong_table[object_ptr] = userdata_container
	
	
	// table is still on top of stack. Don't forget to pop it now that we are done with it
	lua_pop(lua_state, 1);
	int top1 = lua_gettop(lua_state);
	assert(top0 == top1);
	
	
	// HACK: I am normally expecting to put LuaCocoaProxyObject's in this table.
	// But I have a corner case for super where the object is not in the wrapper, but I still want to be able to get the
	// environmental table. So, for this case, I will also put the inner object in the table as a key 
	// if the object is a LuaCocoaProxyObject.
//	if(ObjectSupport_IsSubclassOfClass(object_getClass(the_object), objc_getClass("LuaCocoaProxyObject")))
#warning "Need to re-examine due to LuaCocoaProxyObject removal"
	if(LuaSubclassBridge_IsClassSubclassInLua(object_getClass(the_object)))
	{
		lua_getfield(lua_state, LUA_REGISTRYINDEX, LUACOCOA_OBJECT_GLOBAL_TABLE_FOR_ENVIRONMENT_TABLES_FOR_LUASUBCLASSES_FOR_INNER_NONPROXY_ID); // puts the global strong table on top of the stack
		//	printf("creating table with key: 0x%x", the_object);
//		lua_pushlightuserdata(lua_state, [(LuaCocoaProxyObject*)the_object luaCocoaObject]); // stack: [object_ptr strong_table]
		lua_pushlightuserdata(lua_state, the_object); // stack: [object_ptr strong_table]
		if(stack_position_of_table < 0)
		{
			// Because we pushed more items on the stack, we need to compensate for the changed relative stack index
			lua_pushvalue(lua_state, stack_position_of_table - 2); // stack: [userdata_container object_ptr strong_table]
		}
		else
		{
			// absolute stack positions don't change
			lua_pushvalue(lua_state, stack_position_of_table); // stack: [userdata_container object_ptr strong_table]	
		}
		
		lua_settable(lua_state, -3); // strong_table[object_ptr] = userdata_container
		
		// table is still on top of stack. Don't forget to pop it now that we are done with it
		lua_pop(lua_state, 1);
		int top2 = lua_gettop(lua_state);
		assert(top0 == top2);
	}

}

/* Leaves result on the stack. Don't forget to pop when done.
 */
_Bool LuaCocoaStrongTable_GetLuaSubclassEnvironmentTableInGlobalStrongTable(lua_State* lua_state, void* the_object)
{
	lua_getfield(lua_state, LUA_REGISTRYINDEX, LUACOCOA_OBJECT_GLOBAL_STRONG_TABLE_FOR_ENVIRONMENT_TABLES_FOR_LUASUBCLASSES_ID); // puts the global weak table on top of the stack
	
	lua_pushlightuserdata(lua_state, the_object); // stack: [strong_table the_object_ptr]
	lua_gettable(lua_state, -2); // get strong_table[the_object], stack: [strong_table lua_object_container_userdata]
	
	// Either nil or the lua_object_container is on the top of the stack.
	// But the weaktable is still underneath it.
	// Since I'm modifying the stack, I want to hide the weak_table as an implementation detail
	// and return so there is only 1 new item on the stack (not two). So replace the strong_table
	// with my return value and pop.
	lua_replace(lua_state, -2); // takes the top item and replaces the item at index -2 with it and pops
	
	if(lua_isnil(lua_state, -1))
	{
		return false;
	}
	else
	{
		return true;
	}
}

void LuaCocoaStrongTable_RemoveLuaSubclassEnvironmentTableInGlobalStrongTable(lua_State* lua_state, void* the_object)
{
	int top0 = lua_gettop(lua_state);

	lua_pushnil(lua_state);
	// Note: LuaCocoaStrongTable_InsertLuaSubclassEnvironmentTableInGlobalStrongTable should also automatically clear my hack.
	LuaCocoaStrongTable_InsertLuaSubclassEnvironmentTableInGlobalStrongTable(lua_state, -1, the_object);
	lua_pop(lua_state, 1);
	int top1 = lua_gettop(lua_state);
	assert(top0 == top1);
}


/**
 * This function is intended to save the Lua function in the registry to prevent garbage collection from deleting out from under the Obj-C block that is using it.
 * @stack_position_of_luafunction Where the Lua function is in the Lua stack.
 * @the_block The raw Objective-C object/pointer (no lua container). Will use as the key (light userdata) the strong table.
 * Object is defined loosely as we currently use anything with a container including NSObjects and selectors.
 * I think it will actually work with any thing that is a pointer.
 */
void LuaCocoaStrongTable_InsertLuaFunctionValueForBlockCleanupKeyInGlobalStrongTable(lua_State* lua_state, int stack_position_of_luafunction, void* the_block)
{
	// Can reuse object implementation
	LuaCocoaStrongTable_InsertObjectInGlobalStrongTable(lua_state, stack_position_of_luafunction, the_block);
}

/* Leaves result on the stack. Don't forget to pop when done.
 */
void LuaCocoaStrongTable_GetLuaFunctionValueForBlockCleanupKeyInGlobalStrongTable(lua_State* lua_state, void* the_block)
{
	lua_getfield(lua_state, LUA_REGISTRYINDEX, LUACOCOA_OBJECT_GLOBAL_STRONG_TABLE_ID); // puts the global weak table on top of the stack
	
	lua_pushlightuserdata(lua_state, the_block); // stack: [strong_table the_object_ptr]
	lua_gettable(lua_state, -2); // get strong_table[the_object], stack: [strong_table lua_object_container_userdata]
	
	// Either nil or the lua_object_container is on the top of the stack.
	// But the weaktable is still underneath it.
	// Since I'm modifying the stack, I want to hide the weak_table as an implementation detail
	// and return so there is only 1 new item on the stack (not two). So replace the strong_table
	// with my return value and pop.
	lua_replace(lua_state, -2); // takes the top item and replaces the item at index -2 with it and pops

}

void LuaCocoaStrongTable_RemoveLuaFunctionValueForBlockCleanupKeyInGlobalStrongTable(lua_State* lua_state, void* the_block)
{
	// The object implementation is identical except it returns values, so we can just use it and throw away the return value.
	LuaCocoaStrongTable_RemoveObjectInGlobalStrongTable(lua_state, the_block);
}
