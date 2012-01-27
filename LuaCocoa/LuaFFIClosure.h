/*
 *  LuaFFIClosure.h
 *  LuaCocoa
 *
 *  Created by Eric Wing on 9/21/10.
 *  Copyright 2010 PlayControl Software, LLC. All rights reserved.
 *
 */

#ifndef _LUA_FFICLOSURE_H_
#define _LUA_FFICLOSURE_H_

// Forward declaration so I don't need to #include "lua.h" here. (I don't have to worry about the search path of Lua for the public header.)
// But I have to use the formal "struct" version of the name instead of the typedef, i.e. "struct lua_State" instead of just "lua_State"
struct lua_State;
//struct ffi_cif;
//struct ffi_type;
//struct ffi_closure;
@class ParseSupport;
#include <ffi/ffi.h>


typedef struct LuaFFIClosureUserDataContainer
{
	ffi_cif* luaFFICif;
	ffi_type** luaFFIRealArgs;
	ffi_type** luaFFIFlattenedArgs;
	ffi_type* luaFFICustomTypeArgs;

	ffi_type* luaFFIRealReturnArg;
	ffi_type** luaFFIFlattenedReturnArg;
	ffi_type* luaFFICustomTypeReturnArg;
	
	ffi_closure* luaFFIClosure;
	
	__strong ParseSupport* parseSupport;
	Class theClass;
	struct lua_State* luaState;
} LuaFFIClosureUserDataContainer;

//LuaFFIClosureUserDataContainer* LuaFFIClosure_CreateNewLuaFFIClosure(struct lua_State* lua_state, struct ffi_cif* the_cif, struct _ffi_type** arg_types, struct ffi_closure* the_closure, ParseSupport* parse_support);
LuaFFIClosureUserDataContainer* LuaFFIClosure_CreateNewLuaFFIClosure(
	struct lua_State* lua_state,
	ffi_cif* the_cif,
	ffi_type** real_args_ptr,
	ffi_type** flattened_args_ptr,
	ffi_type* custom_type_args_ptr, 
	ffi_type* real_return_ptr, 
	ffi_type** flattened_return_ptr, 
	ffi_type* custom_type_return_ptr, 
	ffi_closure* the_closure, 
	ParseSupport* parse_support,
	Class the_class
);


int luaopen_LuaFFIClosure(struct lua_State* state);

#endif // _LUA_FFICLOSURE_H_
