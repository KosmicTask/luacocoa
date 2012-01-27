//
//  LuaFunctionBridge.h
//  LuaCocoa
//
//  Created by Eric Wing on 11/9/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

// Forward declaration so I don't need to #include "lua.h" here. (I don't have to worry about the search path of Lua for the public header.)
// But I have to use the formal "struct" version of the name instead of the typedef, i.e. "struct lua_State" instead of just "lua_State"
struct lua_State;

#ifndef _LUA_FUNCTION_BRIDGE_H_
#define _LUA_FUNCTION_BRIDGE_H_


//int LuaFunctionBridge_FFIPrepCif(lua_State* lua_state);
//int LuaFunctionBridge_FFICall(lua_State* lua_state);

int luaopen_LuaFunctionBridge(struct lua_State* state);

#endif // _LUA_FUNCTION_BRIDGE_H_