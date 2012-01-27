//
//  LuaSubclassBridge.h
//  LuaCocoa
//
//  Created by Eric Wing on 11/13/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//




#ifndef _LUA_SUBCLASS_BRIDGE_H_
#define _LUA_SUBCLASS_BRIDGE_H_

#import <objc/objc.h>
#include <stddef.h>
#include <stdbool.h>

struct LuaUserDataContainerForObject;

// Forward declaration so I don't need to #include "lua.h" here. (I don't have to worry about the search path of Lua for the public header.)
// But I have to use the formal "struct" version of the name instead of the typedef, i.e. "struct lua_State" instead of just "lua_State"
struct lua_State;

int luaopen_LuaSubclassBridge(struct lua_State* lua_state);

//id LuaSubclassBridge_initWithLuaCocoaState(id self, SEL _cmd, struct lua_State* lua_state);
//void LuaSubclassBridge_InitializeNewLuaObject(id the_object, struct lua_State* lua_state);

// May handle either the proxy wrapper or underlying luaCocoaObject
struct lua_State* LuaSubclassBridge_GetLuaStateFromLuaSubclassObject(id the_object);
void LuaSubclassBridge_SetLuaStateFromLuaSubclassObject(struct lua_State* lua_state, id the_object);

// Must pass the proxy wrapper and not the actual object
// (Lua strong table key is based on proxy address.)
void LuaSubclassBridge_InitializeNewLuaObject(id the_object, struct lua_State* lua_state);
bool LuaSubclassBridge_InitializeNewLuaObjectIfSubclassInLua(id the_object, struct lua_State* lua_state);

// May handle either the proxy wrapper or underlying luaCocoaObject
bool LuaSubclassBridge_IsClassSubclassInLua(Class the_class);
bool LuaSubclassBridge_IsObjectSubclassInLua(id the_object);



// Internal use only

#define LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER "luaCocoaluaStateWithAUniqueVariableNameSoICanUseAsAnIdentifierForLuaCocoaSubclasses"

// -3 for userdata object
// -2 for index or key (function_name)
// -1 for new value (function)
bool LuaSubclassBridge_SetNewMethod(struct lua_State* lua_state);
bool LuaSubclassBridge_SetNewMethodSignature(struct lua_State* lua_state);
bool LuaSubclassBridge_SetNewMethodAndSignature(struct lua_State* lua_state);

//int LuaSubclassBridge_GetIndexOnClass(struct lua_State* lua_state, struct LuaUserDataContainerForObject* lua_class_container, bool is_class, bool* did_handle_case);
//bool LuaSubclassBridge_FindLuaMethod(struct lua_State* lua_state, struct LuaUserDataContainerForObject* lua_class_container, const char* method_name);
bool LuaSubclassBridge_FindLuaMethodInClass(struct lua_State* lua_state, Class starting_class, const char* method_name, Class* which_class_found, bool* is_instance_defined);
bool LuaSubclassBridge_FindLuaMethod(struct lua_State* lua_state, struct LuaUserDataContainerForObject* lua_class_container, const char* method_name, Class* which_class_found, bool* is_instance_defined);

const char* LuaSubclassBridge_FindLuaSignature(struct lua_State* lua_state, struct LuaUserDataContainerForObject* lua_class_container, const char* method_name);


void LuaSubclassBridge_InitializeNewLuaObject(id the_object, struct lua_State* lua_state);

#endif // _LUA_SUBCLASS_BRIDGE_H_

