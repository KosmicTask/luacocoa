/*
 *  LuaFFIClosure.c
 *  LuaCocoa
 *
 *  Created by Eric Wing on 9/21/10.
 *  Copyright 2010 PlayControl Software, LLC. All rights reserved.
 *
 */

#include "LuaFFIClosure.h"

#include "lua.h"
#include "lauxlib.h"
#import "ParseSupport.h"
#include <CoreFoundation/CoreFoundation.h>
//#include <ffi/ffi.h>
#include <sys/mman.h>   // for mmap()

const char* LUACOCOA_FFICLOSURE_METATABLE_ID = "LuaCocoa.ffi_closure";



static int LuaFFIClosure_GarbageCollect(lua_State* lua_state)
{
//		fprintf(stderr, "In GarbageCollect\n");
	LuaFFIClosureUserDataContainer* ret_val = (LuaFFIClosureUserDataContainer*)luaL_checkudata(lua_state, -1, LUACOCOA_FFICLOSURE_METATABLE_ID);
	if(NULL != ret_val)
	{
		if(NULL != ret_val->luaFFIClosure)
		{
			// Note: I don't believe it's possible to unregister a method in Obj-C,
			// so the runtime will still th
//			NSLog(@"LuaFFIClosure freeing closure");
			// Free the memory associated with the closure.
			if(munmap(ret_val->luaFFIClosure, sizeof(ret_val->luaFFIClosure)) == -1)
			{
				// Check errno and handle the error.
				NSLog(@"munmap failed in LuaFFIClosure");
				// Check errno and handle the error.
				perror( "munmap failed in LuaFFIClosure" );
				fprintf( stderr, "munmap failed in LuaFFIClosure: %s\n", strerror( errno ) );
			}
			else
			{
				ret_val->luaFFIClosure = NULL;
			}

		}
		
		if(NULL != ret_val->luaFFICustomTypeReturnArg)
		{
			free(ret_val->luaFFICustomTypeReturnArg);
			ret_val->luaFFICustomTypeReturnArg = NULL;
		}
		if(NULL != ret_val->luaFFIFlattenedReturnArg)
		{
			free(ret_val->luaFFIFlattenedReturnArg);
			ret_val->luaFFIFlattenedReturnArg = NULL;
		}
		if(NULL != ret_val->luaFFIRealReturnArg)
		{
			free(ret_val->luaFFIRealReturnArg);
			ret_val->luaFFIRealReturnArg = NULL;
		}
		
		if(NULL != ret_val->luaFFICustomTypeArgs)
		{
			free(ret_val->luaFFICustomTypeArgs);
			ret_val->luaFFICustomTypeArgs = NULL;
		}
		if(NULL != ret_val->luaFFIFlattenedArgs)
		{
			free(ret_val->luaFFIFlattenedArgs);
			ret_val->luaFFIFlattenedArgs = NULL;
		}
		if(NULL != ret_val->luaFFIRealArgs)
		{
			free(ret_val->luaFFIRealArgs);
			ret_val->luaFFIRealArgs = NULL;
		}
		if(NULL != ret_val->luaFFICif)
		{
			free(ret_val->luaFFICif);
			ret_val->luaFFICif = NULL;
		}
		if(NULL != ret_val->parseSupport)
		{
			CFRelease(ret_val->parseSupport);
			ret_val->parseSupport = nil;
		}
	}
	return 0;
}



static const struct luaL_reg LuaFFIClosure_LuaMethods[] =
{
	{"__gc", LuaFFIClosure_GarbageCollect},
	{NULL,NULL},
};


LuaFFIClosureUserDataContainer* LuaFFIClosure_CreateNewLuaFFIClosure(lua_State* lua_state, ffi_cif* the_cif,
	ffi_type** real_args_ptr,
	ffi_type** flattened_args_ptr,
	ffi_type* custom_type_args_ptr, 
	ffi_type* real_return_ptr, 
	ffi_type** flattened_return_ptr, 
	ffi_type* custom_type_return_ptr,
	ffi_closure* the_closure, ParseSupport* parse_support, Class the_class)
{
	// Create the new container
	LuaFFIClosureUserDataContainer* return_userdata = (LuaFFIClosureUserDataContainer*)lua_newuserdata(lua_state, sizeof(LuaFFIClosureUserDataContainer));
	return_userdata->luaFFICif = the_cif;
	return_userdata->luaFFIRealArgs = real_args_ptr;
	return_userdata->luaFFIFlattenedArgs = flattened_args_ptr;
	return_userdata->luaFFICustomTypeArgs = custom_type_args_ptr;
	return_userdata->luaFFIRealReturnArg = real_return_ptr;
	return_userdata->luaFFIFlattenedReturnArg = flattened_return_ptr;
	return_userdata->luaFFICustomTypeReturnArg = custom_type_return_ptr;

	return_userdata->luaFFIClosure = the_closure;
	return_userdata->parseSupport = parse_support;
	if(nil != return_userdata->parseSupport)
	{
		CFRetain(return_userdata->parseSupport);		
	}
	return_userdata->theClass = the_class;
	return_userdata->luaState = lua_state;

	// Set the metatable identifier on our new userdata
	luaL_getmetatable(lua_state, LUACOCOA_FFICLOSURE_METATABLE_ID);
	lua_setmetatable(lua_state, -2);	
	return return_userdata;
}


int luaopen_LuaFFIClosure(lua_State* state)
{
	luaL_newmetatable(state, LUACOCOA_FFICLOSURE_METATABLE_ID);
	luaL_register(state, NULL, LuaFFIClosure_LuaMethods);
	
	return 1;
}

