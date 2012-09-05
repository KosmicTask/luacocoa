//
//  LuaCocoaWeakTable.h
//  LuaCocoa
//
//  Created by Eric Wing on 11/11/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#ifndef _LUA_COCOA_WEAK_TABLE_H
#define _LUA_COCOA_WEAK_TABLE_H

#ifdef __cplusplus
extern "C" {
#endif
	
	
// Forward declaration so I don't need to #include "lua.h" here. (I don't have to worry about the search path of Lua for the public header.)
// But I have to use the formal "struct" version of the name instead of the typedef, i.e. "struct lua_State" instead of just "lua_State"
struct lua_State;
	
void LuaCocoaWeakTable_CreateGlobalWeakObjectTable(struct lua_State* lua_state);

void LuaCocoaWeakTable_InsertObjectInGlobalWeakTable(struct lua_State* lua_state, int stack_position_of_userdata, void* the_object);

void* LuaCocoaWeakTable_GetObjectInGlobalWeakTable(struct lua_State* lua_state, void* the_object);

// This is a hack. I originally wanted 1 object to 1 userdata for uniqueness.
// But to support the notion of getting super on an object, I need to set a flag on the userdata on the object.
// But since the key object is still fundamentally the same, I must keep around multiple objects.
// So I will put super in a separate weak table.
void LuaCocoaWeakTable_InsertObjectInGlobalWeakTableForSuper(struct lua_State* lua_state, int stack_position_of_userdata, void* the_object);
	
void* LuaCocoaWeakTable_GetObjectInGlobalWeakTableForSuper(struct lua_State* lua_state, void* the_object);
	



	
	
void LuaCocoaWeakTable_InsertLuaFunctionKeyAndBlockValueInGlobalWeakTable(struct lua_State* lua_state, int stack_position_of_lua_function, void* the_block);

/* Leaves result on the stack. Don't forget to pop when done.
 */
void* LuaCocoaWeakTable_GetBlockForLuaFunctionInGlobalWeakTable(struct lua_State* lua_state, int stack_position_of_lua_function);


/**
 * @stack_position_of_lua_function Where the lua function for the new block is in the Lua stack. Will use as the key the weak table.
 * @the_block The raw Objective-C object/pointer (no lua container).
 * Object is defined loosely as we currently use anything with a container including NSObjects and selectors.
 * I think it will actually work with any thing that is a pointer.
 */
void LuaCocoaWeakTable_InsertBlockKeyAndLuaFunctionValueInGlobalWeakTable(struct lua_State* lua_state, void* the_block, int stack_position_of_lua_function);
/* Returns true if the function is there, false if not. Leaves result on the stack or nil on the stack. Don't forget to pop when done.
 */
_Bool LuaCocoaWeakTable_GetLuaFunctionForBlockInGlobalWeakTable(struct lua_State* lua_state, void* the_block);

	

// Convenience method that wraps LuaCocoaWeakTable_InsertLuaFunctionKeyAndBlockValueInGlobalWeakTable and LuaCocoaWeakTable_InsertBlockKeyAndLuaFunctionValueInGlobalWeakTable
// This adds the mappings in both directions
void LuaCocoaWeakTable_InsertBidirectionalLuaFunctionBlockInGlobalWeakTable(struct lua_State* lua_state, int stack_position_of_lua_function, void* the_block);

// This removes the mappings in both directions
void LuaCocoaWeakTable_RemoveBidirectionalLuaFunctionBlockInGlobalWeakTable(struct lua_State* lua_state, void* the_block);

#ifdef __cplusplus
}
#endif

#endif /* _LUA_COCOA_WEAK_TABLE_H */

