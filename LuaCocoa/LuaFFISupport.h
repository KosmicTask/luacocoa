//
//  LuaFFISupport.h
//  LuaCocoa
//
//  Created by Eric Wing on 10/23/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//



#ifndef _FFI_SUPPORT_H_
#define _FFI_SUPPORT_H_

#include <stddef.h>
#import <Foundation/Foundation.h>
#import <ffi/ffi.h>

#import "ParseSupportFunction.h"
#import "ParseSupportArgument.h"

#ifdef __cplusplus
extern "C" {
#endif
	
// Forward declaration so I don't need to #include "lua.h" here. (I don't have to worry about the search path of Lua for the public header.)
// But I have to use the formal "struct" version of the name instead of the typedef, i.e. "struct lua_State" instead of just "lua_State"
struct lua_State;
	
	
ffi_type* FFISupport_FFITypeForObjcEncoding(char objc_encoding);
ffi_type* FFISupport_FFITypeForObjcEncodingInNSString(NSString* objc_encoding);

size_t FFISupport_ParseSupportFunctionArgumentsToFFIType(ParseSupportFunction* parse_support_function, ffi_type* memory_for_custom_types, ffi_type*** ffi_type_for_args, ffi_type** elements_for_ffi_type_for_args);


// Watch out! ffi_type_for_args always sets/returns a different pointer which is bad if you malloc'd memory. Pass in a pointer by reference.
size_t FFISupport_ParseSupportFunctionReturnValueToFFIType(ParseSupportFunction* parse_support_function, ffi_type* memory_for_custom_type, ffi_type** ffi_type_for_args, ffi_type** elements_for_ffi_type_for_args);


//void LuaFFISupport_FillFFIArguments(struct lua_State* lua_state, void** array_for_ffi_arguments, void** array_for_ffi_ref_arguments, size_t current_ffi_argument_index, size_t current_lua_argument_index, unsigned short current_ffi_type, ParseSupportArgument* parse_support_argument);
	
int LuaFFISupport_PushReturnValue(struct lua_State* lua_state, void* return_value, ffi_type* ffi_type_for_arg, ParseSupportArgument* parse_support_argument, int stack_index_for_value_already_in_stack, bool should_retain, bool is_out_argument);

size_t LuaFFISupport_ParseVariadicArguments(struct lua_State* lua_state, ParseSupportFunction* parse_support, int lua_argument_list_start_index_offset);

size_t LuaFFISupport_ParseVariadicArgumentsInFFIArgs(ParseSupportFunction* parse_support, ffi_cif* the_cif, void** args_from_ffi, int argument_list_start_index_offset);

#ifdef __cplusplus
}
#endif



#endif /* _FFI_SUPPORT_H_ */