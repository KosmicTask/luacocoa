//
//  LuaBlockBridge.h
//  LuaCocoa
//
//  Created by Eric Wing on 2/18/12.
//  Copyright (c) 2012 PlayControl Software, LLC. All rights reserved.
//

//
//  StructBridge.h
//  LuaCocoa
//
//  Created by Eric Wing on 10/13/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#ifndef _LUA_BLOCK_BRIDGE_H
#define _LUA_BLOCK_BRIDGE_H


#ifdef __cplusplus
extern "C" {
#endif

// Forward declaration so I don't need to #include "lua.h" here. (I don't have to worry about the search path of Lua for the public header.)
// But I have to use the formal "struct" version of the name instead of the typedef, i.e. "struct lua_State" instead of just "lua_State"
struct lua_State;

//@class NSString;
@class ParseSupportFunction;
//@class ParseSupport;

#include <stdbool.h>

int luaopen_LuaBlockBridge(struct lua_State* lua_state);

// Not autoreleased
id LuaBlockBridge_CreateBlockFromLuaFunctionWithParseSupport(struct lua_State* lua_state, int index_of_lua_function, ParseSupportFunction* parse_support);


int LuaBlockBridge_CallBlock(struct lua_State* lua_state, id the_block, int lua_argument_start_index);



#ifdef __cplusplus
}
#endif

#endif /* _LUA_BLOCK_BRIDGE_H */

