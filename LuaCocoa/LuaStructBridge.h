//
//  StructBridge.h
//  LuaCocoa
//
//  Created by Eric Wing on 10/13/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#ifndef _LUA_STRUCT_BRIDGE_H
#define _LUA_STRUCT_BRIDGE_H


#ifdef __cplusplus
extern "C" {
#endif

// Forward declaration so I don't need to #include "lua.h" here. (I don't have to worry about the search path of Lua for the public header.)
// But I have to use the formal "struct" version of the name instead of the typedef, i.e. "struct lua_State" instead of just "lua_State"
struct lua_State;

@class NSString;

#include <stdbool.h>

// Creates a new metatable and leaves on Lua stack.
// If metatable already exists, it returns 0 with metatable on the stack.
//bool LuaStructBridge_GetOrCreateStructMetatable(struct lua_State* lua_state, NSString* key_name, NSString* struct_name);

// Applies a metatable (from keyname) to the userdata at the specified stack position
// Stack should be unchanged after return
bool LuaStructBridge_SetStructMetatableOnUserdata(struct lua_State* lua_state, int obj_index, NSString* key_name, NSString* struct_name);


bool LuaStructBridge_isstruct(struct lua_State* lua_state, int obj_index);

NSString* LuaStructBridge_GetBridgeKeyNameFromMetatable(struct lua_State* lua_state, int obj_index);
const char* LuaStructBridge_GetBridgeKeyNameFromMetatableAsString(struct lua_State* lua_state, int obj_index);

NSString* LuaStructBridge_GetBridgeStructNameFromMetatable(struct lua_State* lua_state, int obj_index);


// Generates an alias constructor function for easy use in Lua. Essentially,
// NSRect = LuaCocoa.GenerateStructConstructorByName("NSRect")
// Then the user can do:
// local my_rect = NSRect(1.0, 2.0, 3.0, 4.)
void LuaStructBridge_GenerateAliasStructConstructor(struct lua_State* lua_state, NSString* struct_name);

int luaopen_LuaStructBridge(struct lua_State* lua_state);

#ifdef __cplusplus
}
#endif

#endif /* _LUA_STRUCT_BRIDGE_H */

