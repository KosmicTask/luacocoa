//
//  LuaFFISupport.m
//  LuaCocoa
//
//  Created by Eric Wing on 10/23/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "LuaFFISupport.h"
#import <objc/runtime.h>
#include "lua.h"
#include "lauxlib.h"
#import "BridgeSupportController.h"
#import "LuaObjectBridge.h"
#import "LuaStructBridge.h"
#import "LuaSelectorBridge.h"

// Borrowed from JSCocoa 
// + (ffi_type*)ffi_typeForTypeEncoding:(char)encoding
ffi_type* FFISupport_FFITypeForObjcEncoding(char objc_encoding)
{
	switch(objc_encoding)
	{
		case	_C_ID:
		case	_C_CLASS:
		case	_C_SEL:
		case	_C_PTR:		
		case	_C_CHARPTR:		return	&ffi_type_pointer;
			
		case	_C_CHR:			return	&ffi_type_sint8;
		case	_C_UCHR:		return	&ffi_type_uint8;
		case	_C_SHT:			return	&ffi_type_sint16;
		case	_C_USHT:		return	&ffi_type_uint16;
		case	_C_INT:
		case	_C_LNG:			return	&ffi_type_sint32;
		case	_C_UINT:
		case	_C_ULNG:		return	&ffi_type_uint32;
		case	_C_LNG_LNG:		return	&ffi_type_sint64;
		case	_C_ULNG_LNG:	return	&ffi_type_uint64;
		case	_C_FLT:			return	&ffi_type_float;
		case	_C_DBL:			return	&ffi_type_double;
		case	_C_BOOL:		return	&ffi_type_sint8;
		case	_C_VOID:		return	&ffi_type_void;
	}
	return	NULL;
}

ffi_type* FFISupport_FFITypeForObjcEncodingInNSString(NSString* objc_encoding)
{
	// Lion workaround for lack of Full bridgesupport file
	if(0 == [objc_encoding length])
	{
		return FFISupport_FFITypeForObjcEncoding(_C_ID);
	}
	return FFISupport_FFITypeForObjcEncoding([objc_encoding UTF8String][0]);
}


// Returns the "flattened" number of arguments (including null characters needed for flattened structs
// I require two arrays to be passed in.
// One array of ffi_types that will contain the overall ffi_type information.
// The other array is for the the (sub)elements field of the ffi_type.
// Since you are responsible for allocating the memory to this function, you must pass in the memory blocks as the two separate parameters.
// This function will set the elements field to point to the correct location in the second block for each type
// as the function fills the data.
size_t FFISupport_ParseSupportFunctionArgumentsToFFIType(ParseSupportFunction* parse_support_function, ffi_type* memory_for_custom_types, ffi_type*** ffi_type_for_args, ffi_type** elements_for_ffi_type_for_args)
{
	size_t i = 0;
	size_t j = 0;
	size_t k = 0;


	for(ParseSupportArgument* an_argument in parse_support_function.argumentArray)
	{
		if(an_argument.isStructType)
		{
			(*ffi_type_for_args)[i] = &memory_for_custom_types[k];
			k++;

			(*ffi_type_for_args)[i]->size	= 0;
			(*ffi_type_for_args)[i]->alignment = 0;
			(*ffi_type_for_args)[i]->type	= FFI_TYPE_STRUCT;

			// There are two separate arrays in play, one for the overall type, and one for the subelements.
			// The overall array needs to be told where the elements array is.
			(*ffi_type_for_args)[i]->elements = &elements_for_ffi_type_for_args[j];
			for(NSString* objc_encoding in an_argument.flattenedObjcEncodingTypeArray)
			{
				elements_for_ffi_type_for_args[j] = FFISupport_FFITypeForObjcEncodingInNSString(objc_encoding);
				j++;
			}
			// Must add NULL for the last element according to the docs
			elements_for_ffi_type_for_args[j] = NULL;
			j++;
			i++;
		}
		else
		{
			(*ffi_type_for_args)[i] = FFISupport_FFITypeForObjcEncodingInNSString(an_argument.objcEncodingType);
			i++;			
		}
	}
	return i;
}

// Watch out! ffi_type_for_args may return a different pointer which is bad if you malloc'd memory.
size_t FFISupport_ParseSupportFunctionReturnValueToFFIType(ParseSupportFunction* parse_support_function, ffi_type* memory_for_custom_type, ffi_type** ffi_type_for_args, ffi_type** elements_for_ffi_type_for_args)
{
	if(nil == parse_support_function.returnValue)
	{
		*ffi_type_for_args = FFISupport_FFITypeForObjcEncoding(_C_VOID);
//		*ffi_type_for_args = ffi_type_void;
		return 0;
	}
	
	size_t j = 0;
	
	ParseSupportArgument* an_argument = parse_support_function.returnValue;

	if(an_argument.isStructType)
	{
		// This implementation mirrors FFISupport_ParseSupportFunctionArgumentsToFFIType.
		// ffi_type_for_args only has storage for the pointer.
		// memory_for_custom_type has the actual memory for the entire ffi_type struct.
		// So we need to connect the two.
		// This was the cause of my bug with NSView's (NSRect)cascadeTopLeftFromPoint:(NSRect) under 64-bit Intel.
		// Not doing this was causing me to trample over memory from my arguments which were setup in a previous call and 
		// ffi_prep_cif to fail with FFI_BAD_TYPEDEF.
		// size and alignment were garbage which were my hints.
		(*ffi_type_for_args) = &memory_for_custom_type[0];

		(*ffi_type_for_args)->size	= 0;
		(*ffi_type_for_args)->alignment = 0;
		(*ffi_type_for_args)->type	= FFI_TYPE_STRUCT;
		
		// There are two separate arrays in play, one for the overall type, and one for the subelements.
		// The overall array needs to be told where the elements array is.
		(*ffi_type_for_args)->elements = &elements_for_ffi_type_for_args[j];
		for(NSString* objc_encoding in an_argument.flattenedObjcEncodingTypeArray)
		{
			elements_for_ffi_type_for_args[j] = FFISupport_FFITypeForObjcEncodingInNSString(objc_encoding);
			j++;
		}
		// Must add NULL for the last element according to the docs
		elements_for_ffi_type_for_args[j] = NULL;
		j++;
	}
	else
	{
//		NSLog(@"address of ffi_type_pointer: 0x%x", &ffi_type_pointer);
//		NSLog(@"address of ffi_type_pointer.size: %d", ffi_type_pointer.size);
//		NSLog(@"address of ffi_type_pointer.type: %d", ffi_type_pointer.type);

		*ffi_type_for_args = FFISupport_FFITypeForObjcEncodingInNSString(an_argument.objcEncodingType);

//		ffi_type* the_ptr = FFISupport_FFITypeForObjcEncodingInNSString(an_argument.objcEncodingType);
//		NSLog(@"address of the_ptr: 0x%x", the_ptr);
//		*ffi_type_for_args = *the_ptr;
//		*ffi_type_for_args = ffi_type_void;

//		NSLog(@"address of ffi_type_for_args.size: %d", ffi_type_for_args->size);
//		NSLog(@"address of ffi_type_pointer.type: %d", ffi_type_for_args->type);

//		ffi_type_pointer

	}
	return j;
}

int LuaFFISupport_PushReturnValueForPointerReference(lua_State* lua_state, void* return_value, ffi_type* ffi_type_for_arg, ParseSupportArgument* parse_support_argument, int stack_index_for_value_already_in_stack)
{
	if(nil == parse_support_argument)
	{
		return 0;
	}
	int number_of_return_values = 0;

	// Lion workaround for lack of Full bridgesupport file
	NSString* nsstring_encoding_type = parse_support_argument.objcEncodingType;
	char objc_encoding_type;

	if(0 == [nsstring_encoding_type length])
	{
		// Assuming we are dealing with regular id's
		objc_encoding_type = _C_ID;
	}
	else
	{
		objc_encoding_type = [nsstring_encoding_type UTF8String][0];
		// verify that it is a pointer
		if(_C_PTR != objc_encoding_type || FFI_TYPE_POINTER != ffi_type_for_arg->type)
		{
			NSLog(@"Don't know how to handle non-pointer (_C_PTR) type for argument out");
			lua_pushnil(lua_state);
			return 1;
		}
	
		objc_encoding_type = [nsstring_encoding_type UTF8String][1];
	}

	
	switch(objc_encoding_type)
	{
		case _C_BOOL:
		{
			_Bool** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				lua_pushboolean(lua_state, **(_Bool**)return_value);												
			}
			number_of_return_values++;
			break;
		}
		case _C_CHR:
		{
			int8_t** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				lua_pushinteger(lua_state, **(int8_t**)return_value);				
			}
			number_of_return_values++;
			break;
		}
		case _C_SHT:
		{
			int16_t** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				lua_pushinteger(lua_state, **(int16_t**)return_value);				
			}
			number_of_return_values++;
			break;
		}
        case _C_INT:
        {    
			int32_t** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				lua_pushinteger(lua_state, **(int32_t**)return_value);				
			}
			number_of_return_values++;
			break;			
		}
        case _C_LNG:
		case _C_LNG_LNG:
		{
			int64_t** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				lua_pushinteger(lua_state, **(int64_t**)return_value);				
			}
			number_of_return_values++;
			break;
		}
        case _C_UCHR:
		{
			uint8_t** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				lua_pushinteger(lua_state, **(uint8_t**)return_value);				
			}
            number_of_return_values++;
			break;
		}
        case _C_USHT:
		{
			uint16_t** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				lua_pushinteger(lua_state, **(uint16_t**)return_value);				
			}
            number_of_return_values++;
			break;
		}
        case _C_UINT:
		{
			uint32_t** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				lua_pushinteger(lua_state, **(uint32_t**)return_value);				
			}
            number_of_return_values++;
			break;
		}
        case _C_ULNG:
        case _C_ULNG_LNG:
		{
			uint64_t** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				lua_pushinteger(lua_state, **(uint64_t**)return_value);				
			}
            number_of_return_values++;
			break;
		}
        case _C_DBL:
		{
			double** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				lua_pushnumber(lua_state, **(double**)return_value);				
			}
            number_of_return_values++;
			break;
		}
        case _C_FLT:
		{
			float** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				lua_pushnumber(lua_state, **(float**)return_value);				
			}
            number_of_return_values++;
			break;
		}
			
        case _C_STRUCT_B:
		{
			// FIXME: Array goes here too
			
			// Note: For structs, I am requiring they pass in a struct.
			// This struct seems to be modified by reference, so I can just return the existing one
			// which is the same pointer as the original.
  
			// the result is already in the stack
            lua_pushvalue(lua_state, stack_index_for_value_already_in_stack);
			
			number_of_return_values++;
			break;
		}
			
		case _C_ID:
		{
			id** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				LuaObjectBridge_Pushid(lua_state, **(id**)return_value);
			}
			number_of_return_values++;
			break;
		}
		case _C_CLASS:
		{
			id** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				LuaObjectBridge_PushClass(lua_state, **(Class**)return_value);
			}
			number_of_return_values++;
			break;
		}
		case _C_CHARPTR:
		{
			const char** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				lua_pushstring(lua_state, *(const char**)return_value);
			}
			number_of_return_values++;
			break;
		}
		case _C_SEL:
		{
			SEL** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				LuaSelectorBridge_pushselector(lua_state, **(SEL**)return_value);
			}
			number_of_return_values++;
			break;
		}
		case _C_PTR:
		{
			// Special case: We need to distinguish between CoreFoundation types and others.
			// I forgot what the MagicCookie is stuff is so I omit that which is used elsewhere. (I also don't have the xml.)
			void** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			// Oops: I can be __CF or __CG. I think I need to track the CFType/tollfree bridge stuff and some how resolve the mapping.
			//					if([type_encoding_string hasPrefix:@"^{__CF"])
			else if([nsstring_encoding_type hasPrefix:@"^{__C"])
			{
				LuaObjectBridge_Pushid(lua_state, **(id**)return_value);
			}
			else
			{
				lua_pushlightuserdata(lua_state, *(void**)return_value);
			}
			number_of_return_values++;
			break;
		}
		default:
		{
			void** check_ptr = return_value;
			if(NULL == check_ptr || NULL == *check_ptr)
			{
				lua_pushnil(lua_state);
			}
			else
			{
				lua_pushlightuserdata(lua_state, *(void**)return_value);
			}
			number_of_return_values++;
			break;
		}
	}
	return number_of_return_values;
}


int LuaFFISupport_PushReturnValue(lua_State* lua_state, void* return_value, ffi_type* ffi_type_for_arg, ParseSupportArgument* parse_support_argument, int stack_index_for_value_already_in_stack, bool should_retain, bool is_out_argument)
{
	if(nil == parse_support_argument)
	{
		return 0;
	}
	
	if(true == is_out_argument)
	{
		return LuaFFISupport_PushReturnValueForPointerReference(lua_state, return_value, ffi_type_for_arg, parse_support_argument, stack_index_for_value_already_in_stack);
		
	}
	NSString* type_encoding_string = [parse_support_argument objcEncodingType];
	char objc_encoding_type = [type_encoding_string UTF8String][0];
	
	int number_of_return_values = 0;
	
	switch(ffi_type_for_arg->type)
	{
		case FFI_TYPE_INT:
		{
			lua_pushinteger(lua_state, *(int *) return_value);
			number_of_return_values++;
			break;
		}
		case FFI_TYPE_SINT8:
		{
			if(_C_BOOL == objc_encoding_type)
			{
				lua_pushboolean(lua_state, *(int8_t *) return_value);								
			}
			else
			{
				lua_pushinteger(lua_state, *(int8_t *) return_value);				
			}
			number_of_return_values++;
			break;
		}
		case FFI_TYPE_SINT16:
		{
			lua_pushinteger(lua_state, *(int16_t *) return_value);
			number_of_return_values++;
			break;
		}
        case FFI_TYPE_SINT32:
        {    
			lua_pushinteger(lua_state, *(int32_t *) return_value);
			number_of_return_values++;
			break;			
		}
        case FFI_TYPE_SINT64:
		{
			lua_pushinteger(lua_state, *(int64_t *) return_value);
			number_of_return_values++;
			break;
		}
        case FFI_TYPE_UINT8:
		{
			lua_pushinteger(lua_state, *(uint8_t *) return_value);
            number_of_return_values++;
			break;
		}
        case FFI_TYPE_UINT16:
		{
            lua_pushinteger(lua_state, *(uint16_t *) return_value);
            number_of_return_values++;
			break;
		}
        case FFI_TYPE_UINT32:
		{
            lua_pushinteger(lua_state, *(uint32_t *) return_value);
            number_of_return_values++;
			break;
		}
        case FFI_TYPE_UINT64:
		{
            lua_pushinteger(lua_state, *(uint64_t *) return_value);
            number_of_return_values++;
			break;
		}
            
#if FFI_TYPE_LONGDOUBLE != FFI_TYPE_DOUBLE
        case FFI_TYPE_LONGDOUBLE:
		{
            lua_pushnumber(lua_state, *(long double *) return_value);
            number_of_return_values++;
			break;
		}
#endif
        case FFI_TYPE_DOUBLE:
		{
            lua_pushnumber(lua_state, *(double *) return_value);
            number_of_return_values++;
			break;
		}
        case FFI_TYPE_FLOAT:
		{
            lua_pushnumber(lua_state, *(float *) return_value);
            number_of_return_values++;
			break;
		}
			
        case FFI_TYPE_STRUCT:
		{
			// Array goes here too
            /* the result is already in the stack */
            lua_pushvalue(lua_state, stack_index_for_value_already_in_stack);
            number_of_return_values++;
			break;
		}
        case FFI_TYPE_POINTER:
		{
			switch(objc_encoding_type)
			{
				case _C_ID:
				{
					LuaObjectBridge_PushidWithRetainOption(lua_state, *(id*) return_value, should_retain);
					number_of_return_values++;
					break;
				}
				case _C_CLASS:
				{
					LuaObjectBridge_PushClass(lua_state, *(Class*) return_value);
					number_of_return_values++;
					break;
				}
				case _C_CHARPTR:
				{
					lua_pushstring(lua_state, *(const char**)return_value);
					number_of_return_values++;
					break;
				}
				case _C_SEL:
				{
					LuaSelectorBridge_pushselector(lua_state, *(SEL*) return_value);
					number_of_return_values++;
					break;
				}
				case _C_PTR:
				{
					// Special case: We need to distinguish between CoreFoundation types and others.
					// I forgot what the MagicCookie is stuff is so I omit that which is used elsewhere. (I also don't have the xml.)
					// Oops: I can be __CF or __CG. I think I need to track the CFType/tollfree bridge stuff and some how resolve the mapping.
//					if([type_encoding_string hasPrefix:@"^{__CF"])
					if([type_encoding_string hasPrefix:@"^{__C"])
					{
						LuaObjectBridge_PushidWithRetainOption(lua_state, *(id*) return_value, should_retain);
					}
					else
					{
						lua_pushlightuserdata(lua_state, *(void**) return_value);
					}
					number_of_return_values++;
					break;
				}
				default:
				{
					lua_pushlightuserdata(lua_state, *(void**) return_value);
					number_of_return_values++;
					break;
				}
			}
			break;
		}
		default:
		{
			NSLog(@"LuaFFISupport_PushReturnValue return type not handled (unexpected type): %d", ffi_type_for_arg->type);
			break;
		}
    }
	return number_of_return_values;
}

size_t LuaFFISupport_ParseVariadicArguments(lua_State* lua_state, ParseSupportFunction* parse_support, int lua_argument_list_start_index_offset)
{
	NSUInteger number_of_function_arguments = parse_support.numberOfRealArguments;
	size_t number_of_found_variadic_arguments = 0;
	
	// 1 lua arg is for the XML string.
	// number_of_function_arguments is the number of fixed arguments described in the xml
	// The remaining would be for variadic args
	if(parse_support.isVariadic)
	{
		//		NSLog(@"is_variadic number_of_function_arguments=%d, number_of_lua_args=%d", number_of_function_arguments, number_of_lua_args);
		
		NSUInteger printf_format_string_index = 0;
		bool has_printf_format_string = [parse_support retrievePrintfFormatIndex:&printf_format_string_index];
		if(true == has_printf_format_string)
		{
			// Find the lua argument with the format string and pass it to a function that will parse it to find the number of arguments and types
			// For this, we need to shift by lua_argument_list_start_index_offset because the first arguments might be for internal use
			// Don't forget to add one more because the stack index starts at 1, not 0.
			const char* printf_format_string = LuaObjectBridge_tostring(lua_state, printf_format_string_index+lua_argument_list_start_index_offset+1);
			//			NSLog(@"Format string is %s", printf_format_string);
			number_of_found_variadic_arguments = [parse_support appendVaradicArgumentsWithPrintfFormat:printf_format_string];
			//			NSLog(@"number_of_found_variadic_args: %d", number_of_found_variadic_args);
			
			// Can validate here
			/*
			 if(number_of_found_variadic_args != )
			 {
			 // error
			 }
			 */
		}
		else
		{
			//			int number_of_variadic_args = number_of_lua_args - 1 - number_of_function_arguments;
			// Total number of arguments for function parameters in the lua stack
			int number_of_lua_args_for_function = lua_gettop(lua_state) - lua_argument_list_start_index_offset;
			// Starting at the end of the non-variadic arguments, iterated through each of the remaining
			for(NSUInteger i=number_of_function_arguments+1; i<=number_of_lua_args_for_function; i++)
			{
				// add +1 because lua index starts at 1, not 0
				// don't forget to add the start offset too
				int current_lua_stack_position = i+lua_argument_list_start_index_offset;
				
				if(lua_isboolean(lua_state, current_lua_stack_position))
				{
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_BOOL];
					number_of_found_variadic_arguments++;
				}
				else if(lua_isinteger(lua_state, current_lua_stack_position))
				{
#if __LP64__
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_LNG];
#else
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_INT];
#endif
					number_of_found_variadic_arguments++;
				}
				else if(lua_isnumber(lua_state, current_lua_stack_position))
				{
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_DBL];
					number_of_found_variadic_arguments++;
				}
				else if(lua_isstring(lua_state, current_lua_stack_position))
				{
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_CHARPTR];
					number_of_found_variadic_arguments++;
				}
				// I expect this case mostly for NULL terminated lists.
				else if(lua_isnil(lua_state, current_lua_stack_position))
				{
					[parse_support appendVaradicArgumentWithObjcEncodingTypeString:@"^v"];
					number_of_found_variadic_arguments++;
				}
				// FIXME: Handle struct? vs id vs array? vs selector?
				else if(lua_isuserdata(lua_state, current_lua_stack_position))
				{
					NSString* key_name = nil;
					if(LuaObjectBridge_isid(lua_state, current_lua_stack_position))
					{
						[parse_support appendVaradicArgumentWithObjcEncodingType:_C_ID];
						number_of_found_variadic_arguments++;						
					}
					else if(nil != (key_name = LuaStructBridge_GetBridgeKeyNameFromMetatable(lua_state, current_lua_stack_position)))
					{
						NSLog(@"Warning: stucts as variadic parameters are untested and untrusted. Found struct with keyname:%@", key_name);
						// TODO: Get the correct encoding type string and set it.
						// I can get the struct and key names, but the problem is that the expecting encoding type is not the struct form of the string, but the function form.
						// <sigh>
						// But maybe it doesn't matter if I am just trying to get the name part?
						//luaL_error(lua_state, "Lua type:%s not supported for variadic function parameter", lua_typename(lua_state, current_lua_stack_position));
						//ParseSupportStruct* parse_support_struct = [ParseSupportStruct parseSupportStructFromKeyName:key_name];

						NSString* xml_string = [[[BridgeSupportController sharedController] masterXmlHash] objectForKey:key_name];
						NSError* xml_error = nil;
						NSXMLDocument* xml_document = [[[NSXMLDocument alloc] initWithXMLString:xml_string options:0 error:&xml_error] autorelease];
						if(nil != xml_error)
						{
							NSLog(@"Unexpected error: ParseSupport initWithKeyName: failed in xmlDocument creation: %@", [xml_error localizedDescription]);
						}
						NSString* encoding_string = ParseSupport_ObjcType([xml_document rootElement]);
						[parse_support appendVaradicArgumentWithObjcEncodingTypeString:encoding_string];

					}
					else
					{
					//	luaL_error(lua_state, "Lua type:%s not supported for variadic function parameter", lua_typename(lua_state, current_lua_stack_position));
						// Is it a lightuserdata pointer or some other pointer we can just push through?
						[parse_support appendVaradicArgumentWithObjcEncodingTypeString:@"^v"];
						number_of_found_variadic_arguments++;
					}


				}
				else
				{
//					NSLog(@"Type not supported for variadic function parameter");
					luaL_error(lua_state, "Lua type:%s not supported for variadic function parameter", lua_typename(lua_state, current_lua_stack_position));
				}

			}
		}
	}
	return number_of_found_variadic_arguments;
}


size_t LuaFFISupport_ParseVariadicArgumentsInFFIArgs(ParseSupportFunction* parse_support, ffi_cif* the_cif, void** args_from_ffi, int argument_list_start_index_offset)
{
#warning "Untested code"
//	NSUInteger number_of_function_arguments = parse_support.numberOfRealArguments;
	size_t number_of_found_variadic_arguments = 0;
	
	// 1 lua arg is for the XML string.
	// number_of_function_arguments is the number of fixed arguments described in the xml
	// The remaining would be for variadic args

	NSUInteger printf_format_string_index = 0;
	bool has_printf_format_string = [parse_support retrievePrintfFormatIndex:&printf_format_string_index];
	if(true == has_printf_format_string)
	{
		__strong const char* printf_format_string = NULL;
		ParseSupportArgument* printf_format_argument = [parse_support.argumentArray objectAtIndex:printf_format_string_index];
		char objc_encoding_type = [printf_format_argument.objcEncodingType UTF8String][0];
		switch(objc_encoding_type)
		{
			case _C_ID:
			{
				// Expecting NSString in this case
				NSString* the_argument = *(NSString**)args_from_ffi[printf_format_string_index];
				printf_format_string = [the_argument UTF8String];
				break;
			}
			case _C_CHARPTR:
			{
				printf_format_string = *(const char**)args_from_ffi[printf_format_string_index];
				break;
			}
			default:
			{
				NSLog(@"Unexpected printf type %c in LuaFFISupport_ParseVariadicArgumentsInFFIArgs", objc_encoding_type);
				printf_format_string = *(const char**)args_from_ffi[printf_format_string_index];
			}
		}
		
		
		//			NSLog(@"Format string is %s", printf_format_string);
		number_of_found_variadic_arguments = [parse_support appendVaradicArgumentsWithPrintfFormat:printf_format_string];
		//			NSLog(@"number_of_found_variadic_args: %d", number_of_found_variadic_args);
		
		// Can validate here
		/*
		 if(number_of_found_variadic_args != )
		 {
		 // error
		 }
		 */
	}
	else
	{
		//			int number_of_variadic_args = number_of_lua_args - 1 - number_of_function_arguments;
		// Total number of arguments for function parameters in the lua stack
		int number_of_ffi_args_for_function = the_cif->nargs;
		// Starting at the end of the non-variadic arguments, iterated through each of the remaining
		for(NSUInteger i=argument_list_start_index_offset; i<=number_of_ffi_args_for_function; i++)
		{
			switch(the_cif->arg_types[i]->type)
			{
				case FFI_TYPE_INT:
				{
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_INT];
					break;
				}
				case FFI_TYPE_SINT8:
				{
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_CHR];
					break;
				}
				case FFI_TYPE_SINT16:
				{
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_SHT];
					break;
				}
				case FFI_TYPE_SINT32:
				{    
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_INT];
					break;			
				}
				case FFI_TYPE_SINT64:
				{
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_LNG];
					break;
				}
				case FFI_TYPE_UINT8:
				{
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_UCHR];
					break;
				}
				case FFI_TYPE_UINT16:
				{
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_USHT];
					break;
				}
				case FFI_TYPE_UINT32:
				{
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_UINT];
					break;
				}
				case FFI_TYPE_UINT64:
				{
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_ULNG];
					break;
				}
					
#if FFI_TYPE_LONGDOUBLE != FFI_TYPE_DOUBLE
				case FFI_TYPE_LONGDOUBLE:
				{
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_DBL];
					break;
				}
#endif
				case FFI_TYPE_DOUBLE:
				{
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_DBL];
					break;
				}
				case FFI_TYPE_FLOAT:
				{
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_FLT];
					break;
				}
					
				case FFI_TYPE_STRUCT:
				{
					// This probably isn't going to work 
					NSLog(@"Warning: Passing struct as varadic argument. This probably won't work");
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_STRUCT_B];
					break;
				}
				case FFI_TYPE_POINTER:
				{
					// Since it is impossible to know the context of the pointer, I assume these are instance objects
					[parse_support appendVaradicArgumentWithObjcEncodingType:_C_ID];
				}
				default:
				{
					NSLog(@"LuaFFISupport_ParseVariadicArgumentsInFFIArgs type not handled (unexpected type): %d", the_cif->arg_types[i]->type);
					break;
				}
					
			}
			number_of_found_variadic_arguments++;
		}
	}			
		
		
		
			
	return number_of_found_variadic_arguments;
}
