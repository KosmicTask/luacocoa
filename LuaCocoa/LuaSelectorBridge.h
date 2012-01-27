//
//  LuaSelectorBridge.h
//  LuaCocoa
//
//  Created by Eric Wing on 11/11/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//



#ifndef _LUA_SELECTOR_BRIDGE_H_
#define _LUA_SELECTOR_BRIDGE_H_

#import <objc/objc.h>
#include <stddef.h>

// Forward declaration so I don't need to #include "lua.h" here. (I don't have to worry about the search path of Lua for the public header.)
// But I have to use the formal "struct" version of the name instead of the typedef, i.e. "struct lua_State" instead of just "lua_State"
struct lua_State;


/* So the big question is why? Selectors could be represented as pure strings instead of userdata.
 The reason I have gone the userdata route is for type conversions in containers.
 When converting NSDictionary's and tables between Obj-C and Lua, information about whether something
 was intended as a string or selector may be lost unless we make a stronger distinction between the two.
 In addition, longer term, I am interested in experimenting with the idea of supporting Lua functions as
 selectors, though this isn't a great match-up because selectors are just method names and don't contain the
 class they map to so they don't exactly correspond.
 */

typedef struct LuaUserDataContainerForSelector
{
	SEL theSelector;
} LuaUserDataContainerForSelector;

int luaopen_LuaSelectorBridge(struct lua_State* lua_state);

// Warning: will convert strings and nsstrings and NSValue's with correct encoding to selectors
// Becareful to check for strings/nsstrings separately if you need to distinguish
bool LuaSelectorBridge_isselector(struct lua_State* lua_state, int stack_index);
SEL LuaSelectorBridge_checkselector(struct lua_State* lua_state, int stack_index);
SEL LuaSelectorBridge_toselector(struct lua_State* lua_state, int stack_index);
void LuaSelectorBridge_pushselector(struct lua_State* lua_state, SEL the_selector);

#endif // _LUA_SELECTOR_BRIDGE_H_