//
//  LuaCocoaStrongTable.h
//  LuaCocoa
//
//  Created by Eric Wing on 11/15/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#ifndef _LUA_COCOA_STRONG_TABLE_H
#define _LUA_COCOA_STRONG_TABLE_H

#ifdef __cplusplus
extern "C" {
#endif
	
	
	// Forward declaration so I don't need to #include "lua.h" here. (I don't have to worry about the search path of Lua for the public header.)
	// But I have to use the formal "struct" version of the name instead of the typedef, i.e. "struct lua_State" instead of just "lua_State"
	struct lua_State;
	
	void LuaCocoaStrongTable_CreateGlobalStrongObjectTable(struct lua_State* lua_state);
	
	void LuaCocoaStrongTable_InsertObjectInGlobalStrongTable(struct lua_State* lua_state, int stack_position_of_userdata, void* the_object);
	
	void* LuaCocoaStrongTable_GetObjectInGlobalStrongTable(struct lua_State* lua_state, void* the_object);

	void LuaCocoaStrongTable_RemoveObjectInGlobalStrongTable(struct lua_State* lua_state, void* the_object);

	
	void LuaCocoaStrongTable_InsertLuaSubclassEnvironmentTableInGlobalStrongTable(struct lua_State* lua_state, int stack_position_of_table, void* the_object);
	_Bool LuaCocoaStrongTable_GetLuaSubclassEnvironmentTableInGlobalStrongTable(struct lua_State* lua_state, void* the_object);
	void LuaCocoaStrongTable_RemoveLuaSubclassEnvironmentTableInGlobalStrongTable(struct lua_State* lua_state, void* the_object);

	
	// WARNING: I am actually putting the block clean up data in this table, not the actual block. The names are a historical artifact. Do not try to get the block from these functions. Use the weak table functions instead.
	// The key is the the_block, the value is the Lua function.
	// Be careful not to not be using these same block (object) pointers elsewhere (like generic bridge pushing)
	// because this uses the same registry table as the Object Strong table above.
	
	void LuaCocoaStrongTable_InsertLuaFunctionValueForBlockCleanupKeyInGlobalStrongTable(struct lua_State* lua_state, int stack_position_of_luafunction, void* the_block_cleanup);
	void LuaCocoaStrongTable_GetLuaFunctionValueForBlockCleanupKeyInGlobalStrongTable(struct lua_State* lua_state, void* the_block_cleanup);
	void LuaCocoaStrongTable_RemoveLuaFunctionValueForBlockCleanupKeyInGlobalStrongTable(struct lua_State* lua_state, void* the_block_cleanup);

	
#ifdef __cplusplus
}
#endif

#endif /* _LUA_COCOA_STRONG_TABLE_H */

