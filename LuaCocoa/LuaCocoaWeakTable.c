//
//  LuaCocoaWeakTable.m
//  LuaCocoa
//
//  Created by Eric Wing on 11/11/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#include "LuaCocoaWeakTable.h"
#include "lua.h"
#include <stdbool.h>

#define LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_ID "LuaCocoa.GlobalWeakTable"
#define LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_FOR_SUPER_ID "LuaCocoa.GlobalWeakTableForSuper"
#define LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_BLOCKS "LuaCocoa.GlobalWeakTableForBlocks"


// Maps lightuserdata to (weak) container objects holding NSObjects, selectors, 
// and anything that has userdata containers around pointers.
// Allows for having unique containers (i.e. for the same NSObject, reuse the same containers)
void LuaCocoaWeakTable_CreateGlobalWeakObjectTable(lua_State* lua_state)
{
	// Push our key for the global registry for our weak table (so we can fetch the table later)
	lua_pushliteral(lua_state, LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_ID);
	
	// Now create (push) our weak table
	lua_newtable(lua_state);
	lua_pushvalue(lua_state, -1);  // table is its own metatable
	lua_setmetatable(lua_state, -2);
	lua_pushliteral(lua_state, "__mode");
	lua_pushliteral(lua_state, "kv"); // make values weak, I don't think lightuserdata is strong ref'd so 'k' is optional.
	lua_settable(lua_state, -3);   // metatable.__mode = "v"
	
	// Now that we've created a new table, put it in the global registry
	lua_settable(lua_state, LUA_REGISTRYINDEX); /* registry[LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_ID] = weak_table */
	
	// hmmm...I kind of expected needing a lua_pop(lua_state, 1); here to balance the stack, but it's already balanced.

	// This is a hack. I originally wanted 1 object to 1 userdata for uniqueness.
	// But to support the notion of getting super on an object, I need to set a flag on the userdata on the object.
	// But since the key object is still fundamentally the same, I must keep around multiple objects.
	// So I will put super in a separate weak table.
	// Do it again for the Super table

	// Push our key for the global registry for our weak table (so we can fetch the table later)
	lua_pushliteral(lua_state, LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_FOR_SUPER_ID);
	
	// Now create (push) our weak table
	lua_newtable(lua_state);
	lua_pushvalue(lua_state, -1);  // table is its own metatable
	lua_setmetatable(lua_state, -2);
	lua_pushliteral(lua_state, "__mode");
	lua_pushliteral(lua_state, "kv"); // make values weak, I don't think lightuserdata is strong ref'd so 'k' is optional.
	lua_settable(lua_state, -3);   // metatable.__mode = "v"
	
	// Now that we've created a new table, put it in the global registry
	lua_settable(lua_state, LUA_REGISTRYINDEX); /* registry[LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_ID] = weak_table */
	
	// hmmm...I kind of expected needing a lua_pop(lua_state, 1); here to balance the stack, but it's already balanced.
	
	
	// Push our key for the global registry for our weak table (so we can fetch the table later)
	lua_pushliteral(lua_state, LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_BLOCKS);
	
	// Now create (push) our weak table
	lua_newtable(lua_state);
	lua_pushvalue(lua_state, -1);  // table is its own metatable
	lua_setmetatable(lua_state, -2);
	lua_pushliteral(lua_state, "__mode");
	lua_pushliteral(lua_state, "kv"); // make values weak, I don't think lightuserdata is strong ref'd so 'k' is optional.
	lua_settable(lua_state, -3);   // metatable.__mode = "v"
	
	// Now that we've created a new table, put it in the global registry
	lua_settable(lua_state, LUA_REGISTRYINDEX); /* registry[LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_ID] = weak_table */
	
	// hmmm...I kind of expected needing a lua_pop(lua_state, 1); here to balance the stack, but it's already balanced.
	
}

/**
 * #stack_position_of_userdata Where the userdata (LuaUserDataContainerForObject*) for the new object is in the Lua stack.
 * @the_object The raw Objective-C object/pointer (no lua container). Will use as the key (light userdata) the weak table.
 * Object is defined loosely as we currently use anything with a container including NSObjects and selectors.
 * I think it will actually work with any thing that is a pointer.
 */
void LuaCocoaWeakTable_InsertObjectInGlobalWeakTable(lua_State* lua_state, int stack_position_of_userdata, void* the_object)
{
	lua_getfield(lua_state, LUA_REGISTRYINDEX, LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_ID); // puts the global weak table on top of the stack
	
	lua_pushlightuserdata(lua_state, the_object); // stack: [object_ptr weak_table]
	if(stack_position_of_userdata < 0)
	{
		// Because we pushed more items on the stack, we need to compensate for the changed relative stack index
		lua_pushvalue(lua_state, stack_position_of_userdata - 2); // stack: [userdata_container object_ptr weak_table]
	}
	else
	{
		// absolute stack positions don't change
		lua_pushvalue(lua_state, stack_position_of_userdata); // stack: [userdata_container object_ptr weak_table]	
	}
	
	lua_settable(lua_state, -3); // weak_table[object_ptr] = userdata_container
	
	// table is still on top of stack. Don't forget to pop it now that we are done with it
	lua_pop(lua_state, 1);
}



/* Leaves result on the stack. Don't forget to pop when done.
 */
void* LuaCocoaWeakTable_GetObjectInGlobalWeakTable(lua_State* lua_state, void* the_object)
{
	lua_getfield(lua_state, LUA_REGISTRYINDEX, LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_ID); // puts the global weak table on top of the stack
	
	lua_pushlightuserdata(lua_state, the_object); // stack: [weak_table the_object_ptr]
	lua_gettable(lua_state, -2); // get weak_table[the_object], stack: [weak_table lua_object_container_userdata]
	
	// Either nil or the lua_object_container is on the top of the stack.
	// But the weaktable is still underneath it.
	// Since I'm modifying the stack, I want to hide the weak_table as an implementation detail
	// and return so there is only 1 new item on the stack (not two). So replace the weak_table
	// with my return value and pop.
	lua_replace(lua_state, -2); // takes the top item and replaces the item at index -2 with it and pops
	
	if(lua_isnil(lua_state, -1))
	{
		return NULL;
	}
	else
	{
		return lua_touserdata(lua_state, -1);
	}
}


/**
 * #stack_position_of_userdata Where the userdata (LuaUserDataContainerForObject*) for the new object is in the Lua stack.
 * @the_object The raw Objective-C object/pointer (no lua container). Will use as the key (light userdata) the weak table.
 * Object is defined loosely as we currently use anything with a container including NSObjects and selectors.
 * I think it will actually work with any thing that is a pointer.
 */
void LuaCocoaWeakTable_InsertObjectInGlobalWeakTableForSuper(lua_State* lua_state, int stack_position_of_userdata, void* the_object)
{
	lua_getfield(lua_state, LUA_REGISTRYINDEX, LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_FOR_SUPER_ID); // puts the global weak table on top of the stack
	
	lua_pushlightuserdata(lua_state, the_object); // stack: [object_ptr weak_table]
	if(stack_position_of_userdata < 0)
	{
		// Because we pushed more items on the stack, we need to compensate for the changed relative stack index
		lua_pushvalue(lua_state, stack_position_of_userdata - 2); // stack: [userdata_container object_ptr weak_table]
	}
	else
	{
		// absolute stack positions don't change
		lua_pushvalue(lua_state, stack_position_of_userdata); // stack: [userdata_container object_ptr weak_table]	
	}
	
	lua_settable(lua_state, -3); // weak_table[object_ptr] = userdata_container
	
	// table is still on top of stack. Don't forget to pop it now that we are done with it
	lua_pop(lua_state, 1);
}



/* Leaves result on the stack. Don't forget to pop when done.
 */
void* LuaCocoaWeakTable_GetObjectInGlobalWeakTableForSuper(lua_State* lua_state, void* the_object)
{
	lua_getfield(lua_state, LUA_REGISTRYINDEX, LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_FOR_SUPER_ID); // puts the global weak table on top of the stack
	
	lua_pushlightuserdata(lua_state, the_object); // stack: [weak_table the_object_ptr]
	lua_gettable(lua_state, -2); // get weak_table[the_object], stack: [weak_table lua_object_container_userdata]
	
	// Either nil or the lua_object_container is on the top of the stack.
	// But the weaktable is still underneath it.
	// Since I'm modifying the stack, I want to hide the weak_table as an implementation detail
	// and return so there is only 1 new item on the stack (not two). So replace the weak_table
	// with my return value and pop.
	lua_replace(lua_state, -2); // takes the top item and replaces the item at index -2 with it and pops
	
	if(lua_isnil(lua_state, -1))
	{
		return NULL;
	}
	else
	{
		return lua_touserdata(lua_state, -1);
	}
}



/**
 * @stack_position_of_lua_function Where the lua function for the new block is in the Lua stack. Will use as the key the weak table.
 * @the_block The raw Objective-C object/pointer (no lua container).
 * Object is defined loosely as we currently use anything with a container including NSObjects and selectors.
 * I think it will actually work with any thing that is a pointer.
 */
void LuaCocoaWeakTable_InsertLuaFunctionKeyAndBlockValueInGlobalWeakTable(lua_State* lua_state, int stack_position_of_lua_function, void* the_block)
{
	lua_getfield(lua_state, LUA_REGISTRYINDEX, LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_BLOCKS); // puts the global weak table on top of the stack
	
	if(stack_position_of_lua_function < 0)
	{
		// Because we pushed more items on the stack, we need to compensate for the changed relative stack index
		lua_pushvalue(lua_state, stack_position_of_lua_function - 1); // stack: [lua_function weak_table]
	}
	else
	{
		// absolute stack positions don't change
		lua_pushvalue(lua_state, stack_position_of_lua_function); // stack: [lua_function weak_table]	
	}
	
	lua_pushlightuserdata(lua_state, the_block); // stack: [the_block lua_function weak_table]

	lua_settable(lua_state, -3); // weak_table[lua_function] = the_block
	
	// table is still on top of stack. Don't forget to pop it now that we are done with it
	lua_pop(lua_state, 1);
}



/* Leaves result on the stack. Don't forget to pop when done.
 */
void* LuaCocoaWeakTable_GetBlockForLuaFunctionInGlobalWeakTable(lua_State* lua_state, int stack_position_of_lua_function)
{
	lua_getfield(lua_state, LUA_REGISTRYINDEX, LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_BLOCKS); // puts the global weak table on top of the stack
	
	if(stack_position_of_lua_function < 0)
	{
		// Because we pushed more items on the stack, we need to compensate for the changed relative stack index
		lua_pushvalue(lua_state, stack_position_of_lua_function - 1); //  stack: [lua_function weak_table]
	}
	else
	{
		// absolute stack positions don't change
		lua_pushvalue(lua_state, stack_position_of_lua_function); //  stack: [lua_function weak_table]	
	}
	
	lua_gettable(lua_state, -2); // get weak_table[lua_function], stack: [block weak_table]
	
	// Either nil or the block pointer is on the top of the stack.
	// But the weaktable is still underneath it.
	// Since I'm modifying the stack, I want to hide the weak_table as an implementation detail
	// and return so there is only 1 new item on the stack (not two). So replace the weak_table
	// with my return value and pop.
	lua_replace(lua_state, -2); // takes the top item and replaces the item at index -2 with it and pops
	
	if(lua_isnil(lua_state, -1))
	{
		return NULL;
	}
	else
	{
		return lua_touserdata(lua_state, -1);
	}
}


/**
 * @stack_position_of_lua_function Where the lua function for the new block is in the Lua stack. Will use as the key the weak table.
 * @the_block The raw Objective-C object/pointer (no lua container).
 * Object is defined loosely as we currently use anything with a container including NSObjects and selectors.
 * I think it will actually work with any thing that is a pointer.
 */
void LuaCocoaWeakTable_InsertBlockKeyAndLuaFunctionValueInGlobalWeakTable(lua_State* lua_state, void* the_block, int stack_position_of_lua_function)
{
	lua_getfield(lua_state, LUA_REGISTRYINDEX, LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_BLOCKS); // puts the global weak table on top of the stack
	
	lua_pushlightuserdata(lua_state, the_block); // stack: [the_block  weak_table]
	// index=0 is a special case and will delete the entry
	if(0 == stack_position_of_lua_function)
	{
		lua_pushnil(lua_state);
	}
	else if(stack_position_of_lua_function < 0)
	{
		// Because we pushed more items on the stack, we need to compensate for the changed relative stack index
		lua_pushvalue(lua_state, stack_position_of_lua_function - 2); //  stack: [lua_function the_block weak_table]
	}
	else
	{
		// absolute stack positions don't change
		lua_pushvalue(lua_state, stack_position_of_lua_function); // stack: [lua_function the_block weak_table]
	}
	
	lua_settable(lua_state, -3); // weak_table[the_block] = lua_function
	
	// table is still on top of stack. Don't forget to pop it now that we are done with it
	lua_pop(lua_state, 1);
}



/* Leaves result on the stack. Don't forget to pop when done.
 */
_Bool LuaCocoaWeakTable_GetLuaFunctionForBlockInGlobalWeakTable(lua_State* lua_state, void* the_block)
{
	lua_getfield(lua_state, LUA_REGISTRYINDEX, LUACOCOA_OBJECT_GLOBAL_WEAK_TABLE_BLOCKS); // puts the global weak table on top of the stack
	
	lua_pushlightuserdata(lua_state, the_block); // stack: [the_block weak_table]
	
	lua_gettable(lua_state, -2); // get weak_table[the_block], stack: [lua_function weak_table]
	
	// Either nil or the block pointer is on the top of the stack.
	// But the weaktable is still underneath it.
	// Since I'm modifying the stack, I want to hide the weak_table as an implementation detail
	// and return so there is only 1 new item on the stack (not two). So replace the weak_table
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

// This adds the mappings in both directions

// This removes the mappings in both directions
void LuaCocoaWeakTable_InsertBidirectionalLuaFunctionBlockInGlobalWeakTable(lua_State* lua_state, int stack_position_of_lua_function, void* the_block)
{
	LuaCocoaWeakTable_InsertLuaFunctionKeyAndBlockValueInGlobalWeakTable(lua_state, stack_position_of_lua_function, the_block);
	
	// Now we need to remove the opposite direction mapping
	LuaCocoaWeakTable_InsertBlockKeyAndLuaFunctionValueInGlobalWeakTable(lua_state, the_block, stack_position_of_lua_function);
}


// This removes the mappings in both directions
void LuaCocoaWeakTable_RemoveBidirectionalLuaFunctionBlockInGlobalWeakTable(lua_State* lua_state, void* the_block)
{
	// need to get the Lua function on the stack so we can remove it
	LuaCocoaWeakTable_GetLuaFunctionForBlockInGlobalWeakTable(lua_state, the_block);
	// Sets table[lua_function] = nil
	LuaCocoaWeakTable_InsertLuaFunctionKeyAndBlockValueInGlobalWeakTable(lua_state, -1, NULL);
	lua_pop(lua_state, 1);
	
	// Now we need to remove the opposite direction mapping
	LuaCocoaWeakTable_InsertBlockKeyAndLuaFunctionValueInGlobalWeakTable(lua_state, the_block, 0);
}



