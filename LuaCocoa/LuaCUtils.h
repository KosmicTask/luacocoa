/*
 Copyright (C) 2004 by Eric Wing
 
 */

/* This is a subset and adaption of my LuaUtils.h/cpp.
 * The easy parts have been copied and converted to pure C
 * for better compatibility with C and Obj-C.
 */

#ifndef LUACUTILS_H
#define LUACUTILS_H

#ifdef __cplusplus
extern "C" {
#endif

#include "lua.h"
#include <stdbool.h>

int LuaCUtils_CreateNestedTable(lua_State * L, const char* table_name);

int LuaCUtils_RegisterFunc(lua_State* script,
						   lua_CFunction function_ptr,
						   const char* function_name,
						   const char* library_name,
						   void* user_light_data
						   );

int LuaCUtils_RegisterNumber(lua_State* script,
							lua_Number value, 
							const char* literal_name,
							const char* library_name);
		
int LuaCUtils_RegisterBoolean(lua_State* script,
							bool value, 
							const char* literal_name,
							const char* library_name);							

int LuaCUtils_RegisterInteger(lua_State* script,
							lua_Integer value, 
							const char* literal_name,
							const char* library_name);			
										
int LuaCUtils_RegisterLightUserData(lua_State* script,
							void* value, 
							const char* literal_name,
							const char* library_name);
								
int LuaCUtils_RegisterString(lua_State* script,
							const char* value, 
							const char* literal_name,
							const char* library_name);


// Typically, level=1 and function_level_offset is either 1 or 2.
// Example:
// function OnEvent()
// pc.log(...)
// If the offset is set to 1, then an error in pc.log will report "log" as the 
// location of the error.
// If the offset is set to 2, then an error in pc.log will report "OnEvent" as the
// location of the error.
size_t LuaCUtils_GetLocationString(lua_State* lua_stack, int level, unsigned int function_name_level_offset, char ret_string[], size_t max_size);
int LuaCUtils_GetLocationInfo(lua_State* lua_stack, int level, unsigned int function_name_level_offset, char function_name[], size_t function_name_max_size, char path_and_file[], size_t path_and_file_max_size, int* line_number);


bool LuaCUtils_checkboolean(lua_State* lua_state, int n_arg);
bool LuaCUtils_optboolean(lua_State* lua_state, int n_arg, int def);
const void* LuaCUtils_checklightuserdata(lua_State* lua_state, int n_arg);
//void* LuaCUtils_optlightuserdata(lua_State* lua_state, int n_arg, int def);


#ifdef __cplusplus
}
#endif

#endif /* LUAUTILS_H */

