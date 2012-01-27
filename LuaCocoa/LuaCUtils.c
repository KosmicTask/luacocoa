/*
 Copyright (C) 2004 by Eric Wing
 
 */

#include "LuaCUtils.h"


#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include "lauxlib.h"

/* #define LUACUTILS_USE_INSIDE_LUA_DEBUG_TRAVERSAL */
#ifdef LUACUTILS_USE_INSIDE_LUA_DEBUG_TRAVERSAL

#define TEMP_INTERNAL_GET_DEBUG_GLOBAL_FUNCTION_NAME "TEMP_INTERNAL_GetDebugGlobalFunctionName"
static const char s_GetDebugGlobalFunctionNameFallback[] =
"function TEMP_INTERNAL_GetDebugGlobalFunctionName(start_level)"
"	if start_level == nil then"
"		start_level = 1"
"	end"
"	local find_global = function (func)"
"		for key,value in pairs(_G) do"
"			if value == func then return key end"
"		end"
"	end"
	
"	for level=start_level,20 do"
"	local info = debug.getinfo(level, \"fn\")"
"	if not info then break end"
"		if info.name == nil then"
"			info.name = find_global(info.func)"
"		end"
"		if info.name then"
"			return info.name"
"		end"
"	end"
"	return nil"
"\n"
"end"
;
#endif /* LUACUTILS_USE_INSIDE_LUA_DEBUG_TRAVERSAL */

/*
 extern "C" {
#include "lua.h"
 }
 */


/**
 * This function will create a nested table in Lua based on the 
 * the string you provide.
 * This function will create a nested table in Lua based on the 
 * the string you provide. Among other things, this may be used 
 * for things like namespaces when registering functions.
 * The original code was posted to the Lua mailing list by
 * Malte Thiesen in response to my question, "How to create Lua
 * nested namespaces in C.
 * I've been tempted to create a pure C version for portability sake, 
 * but I don't want to waste the time dealing with C string manipulation.
 * It probably would involve something like:
 * 
 * char* temp_str = strdup(original_str);
 * char* ret_str;
 * ret_str = strtok(temp_str, ".");
 * while(ret_str)
 * {
 *     // do something with the retstr
 *     printf("%s\n", ret_str);
 *     ret_str = strtok(NULL, ".");
 * }
 *
 * It's also tempting to invoke a Lua state to do the string manipulation
 * for me. It might be interesting to benchmark the differences in overhead
 * between creating and invoking a Lua state, string manipulation in C++ 
 * (with implied memory allocations in the class implementation), and 
 * pure C overhead (strcpy needed because strtok is non-const).
 * 
 * @param L The Lua state to operate on.
 * @param table_name The name of the table you want to create. This could
 * be something like "sc.master.sound" or "console". Each (nested) 
 * table/layer/namespace needs to be separated by exactly one dot (".").
 * @return Returns true on success, false on an error.
 */
int LuaCUtils_CreateNestedTable(lua_State * L, const char* table_name)
{
	// The tablename is seperated at the periods and the subtables are
	// created if they don't exist.
	// On success true is returned and the last subtable is on top of
	// the Lua-stack.
	char* copy_of_table_name;
	char* sub_table_name;
	size_t str_length;
	int is_first_pass = 1;
	
	if(NULL == table_name)
	{
		// Is this an error, or is this allowed?
		return 1;
	}
	
	str_length = strlen(table_name);
	copy_of_table_name = (char*)calloc(str_length+1, sizeof(char));
	if(NULL == copy_of_table_name)
	{
		// out of memory?
		return 0;
	}
	strncpy(copy_of_table_name, table_name, str_length);
	
	// Use strok_r for reentrant, use strsep to be non-obsolete
	sub_table_name = strtok(copy_of_table_name, ".");
	while(NULL != sub_table_name)
	{
		// Tables need to have a name (something like "a..b" occured)
		// strtok seems to skip over things like .. and seems to prevent 
		// this case from happenning, but the check is here just is case.
		if(strlen(sub_table_name) == 0)
		{
			// free memory
			free(copy_of_table_name);
			return 0;
		}
		// Check if a table already exists
		// At the first pass the table is searched in the global
		// namespace. Later the parent-table on the stack is searched.
		if(1 == is_first_pass)
		{
			lua_pushstring(L, sub_table_name);
			lua_gettable(L, LUA_GLOBALSINDEX);
		}
		else
		{
			lua_pushstring(L, sub_table_name);
			lua_gettable(L, -2);
			if(!lua_isnil(L, -1))
			{
				lua_remove(L, -2);
			}
		}
		
		// If the table wasn't found, it has to be created
		if (lua_isnil(L, -1))
		{
			// Pop nil from the stack
			lua_pop(L, 1);
			// Create new table
			lua_newtable(L);
			lua_pushstring(L, sub_table_name);
			lua_pushvalue(L, -2);
			if(1 == is_first_pass)
			{
				lua_settable(L, LUA_GLOBALSINDEX);
			}
			else
			{
				lua_settable(L, -4);
				lua_remove(L, -2);
			}
		}

		// Disable the first pass flag
		if(1 == is_first_pass)
		{
			is_first_pass = 0;
		}
		
		// Get the next token
		// Use strok_r for reentrant, use strsep to be non-obsolete
		sub_table_name = strtok(NULL, ".");
	}
	
	free(copy_of_table_name);
	return 1;
}


int LuaCUtils_RegisterFunc(lua_State* lua_state,
						   lua_CFunction function_ptr,
						   const char* function_name,
						   const char* library_name,
						   void* user_light_data
)
{
	/* Validate arguments. */
	if (!lua_state || !function_ptr || !function_name)
	{
		return 0;
	}
	if (0 == strlen(function_name))
	{
		return 0;
	}
	
//	fprintf(stderr, "Lua Register, start top = %d\n", lua_gettop(lua_state));
	
	/* This will embed the function in a namespace if
		desired */
	if(NULL != library_name)
	{
		LuaCUtils_CreateNestedTable(lua_state, library_name);		/* stack: table */
	}
	else
	{
		lua_pushvalue(lua_state, LUA_GLOBALSINDEX);				/* stack: table */
	}
	
	/* Register function into script object.
	 * Also passes pointer to a SpaceObjScriptIO instance 
	 * via lightuserdata.
	 */
	lua_pushstring( lua_state, function_name );  /* Add function name. */
	lua_pushlightuserdata( lua_state, user_light_data );  /* Add pointer to this object. */
	lua_pushcclosure( lua_state, function_ptr, 1 );  /* Add function pointer. */
	lua_settable( lua_state, -3);

	/* use function_name when calling from Lua */
	lua_pushstring( lua_state, function_name );					/* stack: table string */
	/* remember function_name as upvalue */
	lua_pushstring( lua_state, function_name );					/* stack: table string string */
	/* push closure on stack */
	lua_pushcclosure( lua_state, function_ptr, 1 );				/* stack: table string func */
	/* add function to namespace table */
	lua_settable( lua_state, -3);								/* stack: table */
	
	/* pop the table that we created/getted */
	lua_pop(lua_state, 1);											/* stack: */

//	fprintf(stderr, "Lua Register, end top = %d\n", lua_gettop(lua_state));

	
	return 1;
}


int LuaCUtils_RegisterNumber(lua_State* script,
							lua_Number value,
							const char* literal_name,
							const char* library_name)
{
	/* Validate arguments */
	if (!script || !literal_name)
	{
		return 0;
	}
	if (0 == strlen(literal_name))
	{
		return 0;
	}
	
	/* This will embed the function in a namespace if
	   desired */
	if(NULL != library_name)
	{
		LuaCUtils_CreateNestedTable(script, library_name);
	}
	else
	{
		lua_pushvalue(script, LUA_GLOBALSINDEX);		
	}
	
	/* Register variable into table */
	lua_pushstring( script, literal_name);  /* Add variable name. */
	lua_pushnumber( script, value );  /* Add value */
	lua_settable( script, -3);
	
	/* pop the table that we created/getted */
	lua_pop(script, 1);
	
	return 1;
}


int LuaCUtils_RegisterBoolean(lua_State* script,
							bool value,
							const char* literal_name,
							const char* library_name)
{
	/* Validate arguments */
	if (!script || !literal_name)
	{
		return 0;
	}
	if (0 == strlen(literal_name))
	{
		return 0;
	}
	
	/* This will embed the function in a namespace if
	 desired */
	if(NULL != library_name)
	{
		LuaCUtils_CreateNestedTable(script, library_name);
	}
	else
	{
		lua_pushvalue(script, LUA_GLOBALSINDEX);		
	}
	
	/* Register variable into table */
	lua_pushstring( script, literal_name);  /* Add variable name. */
	lua_pushboolean( script, value );  /* Add value */
	lua_settable( script, -3);
	
	/* pop the table that we created/getted */
	lua_pop(script, 1);
	
	return 1;
}



int LuaCUtils_RegisterInteger(lua_State* script,
							lua_Integer value,
							const char* literal_name,
							const char* library_name)
{
	/* Validate arguments */
	if (!script || !literal_name)
	{
		return 0;
	}
	if (0 == strlen(literal_name))
	{
		return 0;
	}
	
	/* This will embed the function in a namespace if
	 desired */
	if(NULL != library_name)
	{
		LuaCUtils_CreateNestedTable(script, library_name);
	}
	else
	{
		lua_pushvalue(script, LUA_GLOBALSINDEX);		
	}
	
	/* Register variable into table */
	lua_pushstring( script, literal_name);  /* Add variable name. */
	lua_pushinteger( script, value );  /* Add value */
	lua_settable( script, -3);
	
	/* pop the table that we created/getted */
	lua_pop(script, 1);
	
	return 1;
}

int LuaCUtils_RegisterLightUserData(lua_State* script,
							  void* value,
							  const char* literal_name,
							  const char* library_name)
{
	/* Validate arguments */
	if (!script || !literal_name)
	{
		return 0;
	}
	if (0 == strlen(literal_name))
	{
		return 0;
	}
	
	/* This will embed the function in a namespace if
	 desired */
	if(NULL != library_name)
	{
		LuaCUtils_CreateNestedTable(script, library_name);
	}
	else
	{
		lua_pushvalue(script, LUA_GLOBALSINDEX);		
	}
	
	/* Register variable into table */
	lua_pushstring( script, literal_name);  /* Add variable name. */
	lua_pushlightuserdata( script, value );  /* Add value */
	lua_settable( script, -3);
	
	/* pop the table that we created/getted */
	lua_pop(script, 1);
	
	return 1;
}

int LuaCUtils_RegisterString(lua_State* script,
							const char* value,
							const char* literal_name,
							const char* library_name)
{
	/* Validate arguments */
	if (!script || !literal_name)
	{
		return 0;
	}
	if (0 == strlen(literal_name))
	{
		return 0;
	}
	
	/* This will embed the function in a namespace if
	 desired */
	if(NULL != library_name)
	{
		LuaCUtils_CreateNestedTable(script, library_name);
	}
	else
	{
		lua_pushvalue(script, LUA_GLOBALSINDEX);		
	}
	
	/* Register variable into table */
	lua_pushstring( script, literal_name);  /* Add variable name. */
	lua_pushstring( script, value );  /* Add value */
	lua_settable( script, -3);
	
	/* pop the table that we created/getted */
	lua_pop(script, 1);
	
	return 1;
}

/**
 * Returns an string containing the function, filename, and line number.
 * Returns an string containing the function, filename, and line number.
 * It may look like "CreateShip:/fwiffo/melee/fleets/common/scripts/Ship.lua:151
 * @return Returns a pointer to ret_string containing these items separated by colons
 * or NULL on error.
 */
size_t LuaCUtils_GetLocationString(lua_State* lua_stack, int level, unsigned int function_name_level_offset, char ret_string[], size_t max_size)
{
	const char* function_name = "";
	const char* file_name = "";
	int current_line = 0;
	
	int error;
	lua_Debug ar;
	fprintf(stderr, "top start =%d\n", lua_gettop(lua_stack));

	/*
	 * Typically, the level is 1 to 
	 * go one up the stack to find information about 
	 * who called this function so we can find the name
	 * and line number.
	 * This function only fills the private parts of the structure.
	 * lua_getinfo must be called afterwards.
	 */
	error = lua_getstack(lua_stack, level, &ar);
	// If there was an error, return
	if(1 != error)
	{
		return 0;
	}
	/* Fill up the structure with requested information
	 * n - gets the "name" of the function we're looking at
	 * n also gets "namewhat" which states 'global', 'local',
	 * 'field', or 'method'.
	 * S - Provides the "source" which seems to be 
	 * the full path and filename (via chunkname) associated
	 * with this lua state.
	 * S also provides "short_src" which seems to be a 60 max character
	 * truncated version of source.
	 * S also provides "what" which is Lua function, C function, 
	 * Lua main.
	 * And S provides the line number ("linedefined") that the 
	 * current function begins its definition.
	 * l - Provides the current line number ("currentline").
	 * u - provides the number of upvalues ("nups").
	 */
	//	error = lua_getinfo(script_ptr, "nSlu", &ar);
	error = lua_getinfo(lua_stack, "nSl", &ar);
	
	if(0 == error)
	{
		return 0;
	}
	
#if 0
	fprintf(stderr, "Name: %s\n", ar.name);
	
	fprintf(stderr, "namewhat: %s\n", ar.namewhat);
	fprintf(stderr, "what: %s\n", ar.what);
	fprintf(stderr, "short_src: %s\n", ar.short_src);
	
	fprintf(stderr, "source: %s\n", ar.source);
	fprintf(stderr, "currentline: %d\n", ar.currentline);
	fprintf(stderr, "linedefined: %d\n", ar.linedefined);
	fprintf(stderr, "upvalues: %d\n", ar.nups);
#endif
	
	current_line = ar.currentline;
	

#if 1
	if(NULL != ar.source)
	{
		file_name = ar.source;
	}
#else
	if(NULL != ar.short_src)
	{
		file_name = ar.short_src;
	}
#endif

	if(NULL != ar.name)
	{
		function_name = ar.name;


		
	}
	else
	{
		/* Ugh. Lua 5.1 doesn't report function names at 
		 * the global level when called from C.
		 * Mike Pall offered me some code that works from within Lua
		 * to restore the 5.0 behavior.
		 */
#ifndef LUACUTILS_USE_INSIDE_LUA_DEBUG_TRAVERSAL
//		fprintf(stderr, "top (start) =%d\n", lua_gettop(lua_stack));
		error = lua_getinfo(lua_stack, "f", &ar);
		if(0 == error)
		{
			fprintf(stderr, "Crap, error calling lua_getinfo");
		}
		/* There should be a function pushed on top by calling get_info with "f". 
		 * If not, I don't know what's going on. Hopefully something was pushed.
		 * otherwise my pop is going to be unbalanced.
		 */
		if(lua_isfunction(lua_stack, -1))
		{
			/* table is in the stack at index 't' */
			lua_pushnil(lua_stack);  /* dummy key because each call to lua_next pops 1 */
			while(lua_next(lua_stack, LUA_GLOBALSINDEX) != 0)
			{
				/* uses 'key' (at index -2) and 'value' (at index -1) */
				/*
				printf("%s - %s\n",
					   lua_typename(lua_stack, lua_type(lua_stack, -2)),
					   lua_typename(lua_stack, lua_type(lua_stack, -1)));
					   
				if(lua_type(lua_stack, -2) == LUA_TSTRING)
				{
					printf("\tkey  : %s\n", lua_tostring(lua_stack, -2));
				}
				else
				{
			//		printf("\tkey  : %d\n", lua_tointeger(lua_stack, -2));
				}
				if(lua_type(lua_stack, -1) == LUA_TSTRING)
				{
					printf("\tvalue: %s\n", lua_tostring(lua_stack, -1));
				}
				else
				{
			//		printf("\tvalue: %d\n", lua_tointeger(lua_stack, -1));
				}
				*/
				
				/* Experimental results are coming out as:
				 * string - function (key - value)
				 * The current function is at index: -1, and the function we want
				 * to compare against is at -3 (put there by lua_getinfo(L, "f", &ar)).
				 * If we hit, the function name is the string at index: -2
				 */
				if(lua_type(lua_stack, -1) == LUA_TFUNCTION)
				{
					if(lua_rawequal(lua_stack, -1, -3))
					{
						printf("We have a match!!!\n");
						if(lua_type(lua_stack, -2) == LUA_TSTRING)
						{
							function_name = lua_tostring(lua_stack, -2);
							printf("\tkey  : %s\n", lua_tostring(lua_stack, -2));
						}
						/* else, we don't have a global name? */
						
						/* We're going to break early. We need to make sure
						 * the stack is popped correctly. Normally,
						 * the end of the loop pops 1, and the next call to
						 * lua_next pops another 1. Since we are bypassing
						 * both, we need to pop 2.
						 */
						 lua_pop(lua_stack, 2);
						 break;
					}
				}
						   
				/* removes 'value'; keeps 'key' for next iteration where 
				 * the next call to lua_next will pop the key and start all over again
				 */
				lua_pop(lua_stack, 1);
			}
//			fprintf(stderr, "top (out) =%d\n", lua_gettop(lua_stack));

			/* We need to pop the function on the stack placed by lua_getinfo(L, "f", &ar) */
		}
		/* pop the function placed by get_info */
		lua_pop(lua_stack, 1);
//		fprintf(stderr, "top (end) =%d\n", lua_gettop(lua_stack));
		
				
								
#else
		/* load in the code I need to extract the function name
		 * (I don't know how to reach it through the C-api)
		 */
		error = luaL_loadstring(lua_stack, s_GetDebugGlobalFunctionNameFallback)
			|| lua_pcall(lua_stack, 0, 0, 0);
		if(error)
		{
			printf("error running function `GetDebugGlobalFunctionName': %s",
				   lua_tostring(lua_stack, -1));
			lua_pop(lua_stack, 1);
		}
		
		
		lua_getglobal(lua_stack, TEMP_INTERNAL_GET_DEBUG_GLOBAL_FUNCTION_NAME);
		lua_pushinteger(lua_stack, level + function_name_level_offset);   /* push 1st argument */
		#if 0
		lua_call(lua_stack, 1, 1, 0);
		#else
		if (lua_pcall(lua_stack, 1, 1, 0) != 0)
		{
			printf("error running function `GetDebugGlobalFunctionName': %s",
				   lua_tostring(lua_stack, -1));
			lua_pop(lua_stack, 1);
		}
		#endif
		if(lua_isstring(lua_stack, -1))
		{
			function_name = lua_tostring(lua_stack, -1);
		}
		lua_pop(lua_stack, 1);

		// erase the debug function
		lua_pushnil(lua_stack);
		lua_setglobal(lua_stack, TEMP_INTERNAL_GET_DEBUG_GLOBAL_FUNCTION_NAME);

		fprintf(stderr, "top end =%d\n", lua_gettop(lua_stack));

		fprintf(stderr, "final string is: %s\n", function_name);
		
		
#endif		

	}
	fprintf(stderr, "top end =%d\n", lua_gettop(lua_stack));

	return snprintf(ret_string, max_size, "%s:%s:%d", file_name, function_name, current_line);


}


/**
 * Fills in the fields for function, filename, and line number.
 * Fills in the fields for function, filename, and line number.
 * This version uses line number as an int.
 * @return false on error and all fields are set to "" or -1
 */
int LuaCUtils_GetLocationInfo(lua_State* lua_stack, int level, unsigned int function_name_level_offset, char function_name[], size_t function_name_max_size, char path_and_file[], size_t path_and_file_max_size, int* line_number)
{
	int error;
	lua_Debug ar;
	
	
	// Typically, the level is 1 to 
	// go one up the stack to find information about 
	// who called this function so we can find the name
	// and line number.
	// This function only fills the private parts of the structure.
	// lua_getinfo must be called afterwards.
	error = lua_getstack(lua_stack, level, &ar);
	// If there was an error, return
	if(1 != error)
	{
//		function_name = "";
//		path_and_file = "";
//		*line_number = -1;
		return 0;
	}
	/* Fill up the structure with requested information
	 * n - gets the "name" of the function we're looking at
	 * n also gets "namewhat" which states 'global', 'local',
	 * 'field', or 'method'.
	 * S - Provides the "source" which seems to be 
	 * the full path and filename (via chunkname) associated
	 * with this lua state.
	 * S also provides "short_src" which seems to be a 60 max character
	 * truncated version of source.
	 * S also provides "what" which is Lua function, C function, 
	 * Lua main.
	 * And S provides the line number ("linedefined") that the 
	 * current function begins its definition.
	 * l - Provides the current line number ("currentline").
	 * u - provides the number of upvalues ("nups").
	 */
	//	error = lua_getinfo(script_ptr, "nSlu", &ar);
	error = lua_getinfo(lua_stack, "nSl", &ar);
	
	// If there was an error, print out what we have
	if(0 == error)
	{
//		function_name = "";
//		path_and_file = "";
//		*line_number = -1;		
		return 0;
	}
	
#if 0
	fprintf(stderr, "Name: %s\n", ar.name);
	
	fprintf(stderr, "namewhat: %s\n", ar.namewhat);
	fprintf(stderr, "what: %s\n", ar.what);
	fprintf(stderr, "short_src: %s\n", ar.short_src);
	
	fprintf(stderr, "source: %s\n", ar.source);
	fprintf(stderr, "currentline: %d\n", ar.currentline);
	fprintf(stderr, "linedefined: %d\n", ar.linedefined);
	fprintf(stderr, "upvalues: %d\n", ar.nups);
#endif
	
	if(NULL != line_number)
	{
		*line_number = ar.currentline;
	}

	if(path_and_file != NULL && path_and_file_max_size > 0)
	{
		if(NULL != ar.source)
		{
			strncpy(path_and_file, ar.source, path_and_file_max_size-1);
			path_and_file[path_and_file_max_size-1] = '\0';
		}
		else
		{
			path_and_file[0] = '\0';
		}
	}
	if(function_name != NULL && function_name_max_size > 0)
	{
		if(NULL != ar.name)
		{
			strncpy(function_name, ar.name, function_name_max_size-1);
			function_name[function_name_max_size-1] = '\0';
		}
		else
		{
			/* Ugh. Lua 5.1 doesn't report function names at 
			 * the global level when called from C.
			 * Mike Pall offered me some code that works from within Lua
			 * to restore the 5.0 behavior.
			 */
	
#ifndef LUACUTILS_USE_INSIDE_LUA_DEBUG_TRAVERSAL
			//		fprintf(stderr, "top (start) =%d\n", lua_gettop(lua_stack));
			error = lua_getinfo(lua_stack, "f", &ar);
			if(0 == error)
			{
				fprintf(stderr, "Crap, error calling lua_getinfo");
			}
			/* There should be a function pushed on top by calling get_info with "f". 
			 * If not, I don't know what's going on. Hopefully something was pushed.
			 * otherwise my pop is going to be unbalanced.
			 */
			if(lua_isfunction(lua_stack, -1))
			{
				/* table is in the stack at index 't' */
				lua_pushnil(lua_stack);  /* dummy key because each call to lua_next pops 1 */
				while(lua_next(lua_stack, LUA_GLOBALSINDEX) != 0)
				{
					/* uses 'key' (at index -2) and 'value' (at index -1) */
					/*
					 printf("%s - %s\n",
					 lua_typename(lua_stack, lua_type(lua_stack, -2)),
					 lua_typename(lua_stack, lua_type(lua_stack, -1)));
					 
					 if(lua_type(lua_stack, -2) == LUA_TSTRING)
					 {
					 printf("\tkey  : %s\n", lua_tostring(lua_stack, -2));
					 }
					 else
					 {
					 //		printf("\tkey  : %d\n", lua_tointeger(lua_stack, -2));
					 }
					 if(lua_type(lua_stack, -1) == LUA_TSTRING)
					 {
					 printf("\tvalue: %s\n", lua_tostring(lua_stack, -1));
					 }
					 else
					 {
					 //		printf("\tvalue: %d\n", lua_tointeger(lua_stack, -1));
					 }
					 */
					
					/* Experimental results are coming out as:
					 * string - function (where: key - value)
					 * The current function is at index: -1, and the function we want
					 * to compare against is at -3 (put there by lua_getinfo(L, "f", &ar)).
					 * If we hit, the function name is the string at index: -2
					 */
					if(lua_type(lua_stack, -1) == LUA_TFUNCTION)
					{
						if(lua_rawequal(lua_stack, -1, -3))
						{
							printf("We have a match!!!\n");
							if(lua_type(lua_stack, -2) == LUA_TSTRING)
							{
								strncpy(function_name, lua_tostring(lua_stack, -2), function_name_max_size-1);
//								printf("\tkey  : %s\n", lua_tostring(lua_stack, -2));
							}
							/* else, we don't have a global name? */
							
							/* We're going to break early. We need to make sure
							 * the stack is popped correctly. Normally,
							 * the end of the loop pops 1, and the next call to
							 * lua_next pops another 1. Since we are bypassing
							 * both, we need to pop 2.
							 */
							lua_pop(lua_stack, 2);
							break;
						}
					}
					
					/* removes 'value'; keeps 'key' for next iteration where 
					 * the next call to lua_next will pop the key and start all over again
					 */
					lua_pop(lua_stack, 1);
				}
				//			fprintf(stderr, "top (out) =%d\n", lua_gettop(lua_stack));
				
				/* We need to pop the function on the stack placed by lua_getinfo(L, "f", &ar) */
			}
			/* pop the function placed by get_info */
			lua_pop(lua_stack, 1);
			//		fprintf(stderr, "top (end) =%d\n", lua_gettop(lua_stack));
			
			
			
#else
			/* load in the code I need to extract the function name
			 * (I don't know how to reach it through the C-api)
			 */
			error = luaL_loadstring(lua_stack, s_GetDebugGlobalFunctionNameFallback)
			|| lua_pcall(lua_stack, 0, 0, 0);
			if(error)
			{
				printf("error running function `GetDebugGlobalFunctionName': %s",
					   lua_tostring(lua_stack, -1));
				lua_pop(lua_stack, 1);
			}
			
			
			lua_getglobal(lua_stack, TEMP_INTERNAL_GET_DEBUG_GLOBAL_FUNCTION_NAME);
			lua_pushinteger(lua_stack, level + function_name_level_offset);   /* push 1st argument */
#if 0
			lua_call(lua_stack, 1, 1, 0);
#else
			if (lua_pcall(lua_stack, 1, 1, 0) != 0)
			{
				printf("error running function `GetDebugGlobalFunctionName': %s",
					   lua_tostring(lua_stack, -1));
				lua_pop(lua_stack, 1);
			}
#endif
			if(lua_isstring(lua_stack, -1))
			{
				strncpy(function_name, lua_tostring(lua_stack, -1), function_name_max_size-1);
			}
			else
			{
				function_name[0] = '\0';
			}

			lua_pop(lua_stack, 1);
			
			// erase the debug function
			lua_pushnil(lua_stack);
			lua_setglobal(lua_stack, TEMP_INTERNAL_GET_DEBUG_GLOBAL_FUNCTION_NAME);
			
			fprintf(stderr, "top end =%d\n", lua_gettop(lua_stack));
			
			fprintf(stderr, "final string is: %s\n", function_name);
			
			
#endif		
			
			
		}
	}
	return 1;
}



bool LuaCUtils_checkboolean(lua_State* lua_state, int n_arg)
{
	luaL_checktype(lua_state, n_arg, LUA_TBOOLEAN); /* may raise an error */
	return lua_toboolean(lua_state, n_arg);
}

bool LuaCUtils_optboolean(lua_State* lua_state, int n_arg, int def)
{
	return luaL_opt(lua_state, LuaCUtils_checkboolean, n_arg, def);
}

const void* LuaCUtils_checklightuserdata(lua_State* lua_state, int n_arg)
{
	luaL_checktype(lua_state, n_arg, LUA_TLIGHTUSERDATA); /* may raise an error */
	return lua_topointer(lua_state, n_arg);
}

/*
void* LuaCUtils_optlightuserdata(lua_State* lua_state, int n_arg, int def)
{
	return luaL_opt(lua_state, LuaCUtils_checklightuserdata, n_arg, def);
}
*/

