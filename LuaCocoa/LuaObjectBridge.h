//
//  LuaObjectBridge.h
//  LuaCocoa
//
//  Created by Eric Wing on 10/22/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#ifndef _LUA_OBJECT_BRIDGE_H_
#define _LUA_OBJECT_BRIDGE_H_

#import <objc/objc.h>
#import <Foundation/Foundation.h>


// Experimental support for things like foo = my_calayer.name
#define LUAOBJECTBRIDGE_ENABLE_GETTER_DOT_NOTATION 1
	// There may be some problematic cases with supporting dot-notation for non-object types.
	// For example, foo:year() returns a lua number. The current implementation
	// may first try to interpret that as foo.year, and return the number.
	// Then call is is invoked on the number which is a runtime error (e.g. 2010()).
	// This option only has an effect if LUAOBJECTBRIDGE_ENABLE_GETTER_DOT_NOTATION is enabled.
	#define LUAOBJECTBRIDGE_GETTER_DOT_NOTATION_SUPPORT_ONLY_ID_TYPES 1

// Forward declaration so I don't need to #include "lua.h" here. (I don't have to worry about the search path of Lua for the public header.)
// But I have to use the formal "struct" version of the name instead of the typedef, i.e. "struct lua_State" instead of just "lua_State"
struct lua_State;


typedef struct LuaUserDataContainerForObject
{
	// In general, I am expecting to call NSObject provided methods.
	// NSProxy might be an exception I need to worry about.
	__strong id theObject;
	bool isInstance;
	bool needsRelease;
	bool isLuaSubclass;
	bool isSuper;
	Class superClass;
} LuaUserDataContainerForObject;

int luaopen_LuaObjectBridge(struct lua_State* lua_state);
void LuaObjectBridge_CreateNewClassUserdata(struct lua_State* lua_state, NSString* class_name);

LuaUserDataContainerForObject* LuaObjectBridge_LuaCheckClass(struct lua_State* lua_state, int stack_index);

// might be considered the equivalent of lua_checkid()

// These do not auto-coerce (e.g. do not interpret numbers as NSNumbers, tables as NSArrays/Dictionaries)
// The backend code actually makes decisions based on these results.
id LuaObjectBridge_checkid(struct lua_State* lua_state, int stack_index);
bool LuaObjectBridge_isid(struct lua_State* lua_state, int stack_index);
bool LuaObjectBridge_isidclass(struct lua_State* lua_state, int stack_index);
bool LuaObjectBridge_isidinstance(struct lua_State* lua_state, int stack_index);
id LuaObjectBridge_toid(struct lua_State* lua_state, int stack_index);

void LuaObjectBridge_Pushid(struct lua_State* lua_state, id the_object);
void LuaObjectBridge_PushidWithRetainOption(struct lua_State* lua_state, id the_object, bool should_retain);
void LuaObjectBridge_PushClass(struct lua_State* lua_state, Class the_class);
// For an instance object, will push its super representation.
void LuaObjectBridge_PushSuperid(struct lua_State* lua_state, id the_object);

// will return true for integers, floats, booleans, and NSNumbers
bool LuaObjectBridge_isnsnumber(struct lua_State* lua_state, int stack_index);
NSNumber* LuaObjectBridge_checknsnumber(struct lua_State* lua_state, int stack_index);
NSNumber* LuaObjectBridge_tonsnumber(struct lua_State* lua_state, int stack_index);
void LuaObjectBridge_pushunboxednsnumber(struct lua_State* lua_state, NSNumber* the_number);

// return true for nil and NSNull
bool LuaObjectBridge_isnsnull(struct lua_State* lua_state, int stack_index);
NSNull* LuaObjectBridge_checknsnull(struct lua_State* lua_state, int stack_index);
NSNull* LuaObjectBridge_tonsnull(struct lua_State* lua_state, int stack_index);

// will return true for strings, numbers (which is always convertible to a string) and NSString
bool LuaObjectBridge_isnsstring(struct lua_State* lua_state, int stack_index);
// Does not copy string
NSString* LuaObjectBridge_checknsstring(struct lua_State* lua_state, int stack_index);
// Does not copy string
NSString* LuaObjectBridge_tonsstring(struct lua_State* lua_state, int stack_index);
void LuaObjectBridge_pushunboxednsstring(struct lua_State* lua_state, NSString* the_string);
__strong const char* LuaObjectBridge_tostring(struct lua_State* lua_state, int stack_index);

bool LuaObjectBridge_isnsarray(struct lua_State* lua_state, int stack_index);
void LuaObjectBridge_pushunboxednsarray(struct lua_State* lua_state, NSArray* the_array);

bool LuaObjectBridge_isnsdictionary(struct lua_State* lua_state, int stack_index);
void LuaObjectBridge_pushunboxednsdictionary(struct lua_State* lua_state, NSDictionary* the_array);

bool LuaObjectBridge_ispropertylist(struct lua_State* lua_state, int stack_index);
id LuaObjectBridge_topropertylist(struct lua_State* lua_state, int stack_index);
id LuaObjectBridge_topropertylistornsnull(struct lua_State* lua_state, int stack_index);

void LuaObjectBridge_pushunboxedpropertylist(struct lua_State* lua_state, id the_object);

// Internal use only
Class LuaObjectBridge_GetClass(LuaUserDataContainerForObject* object_container);
bool LuaObjectBridge_IsClass(LuaUserDataContainerForObject* object_container);


#endif // _LUA_OBJECT_BRIDGE_H_

