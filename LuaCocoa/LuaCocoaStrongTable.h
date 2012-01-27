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
	
	
	void LuaCocoaStrongTable_InsertLuaSubclassEnvironmentTableInGlobalStrongTable(struct lua_State* lua_state, int stack_position_of_table, void* the_object);
	_Bool LuaCocoaStrongTable_GetLuaSubclassEnvironmentTableInGlobalStrongTable(struct lua_State* lua_state, void* the_object);
	void LuaCocoaStrongTable_RemoveLuaSubclassEnvironmentTableInGlobalStrongTable(struct lua_State* lua_state, void* the_object);

#ifdef __cplusplus
}
#endif

#endif /* _LUA_COCOA_STRONG_TABLE_H */

