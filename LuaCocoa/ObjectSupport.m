//
//  ClassSupport.m
//  LuaCocoa
//
//  Created by Eric Wing on 10/22/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "ObjectSupport.h"
#import "ParseSupport.h"
#import <Foundation/Foundation.h>
#import <objc/objc.h>
#import <objc/runtime.h>
#import <objc/objc-runtime.h>
#import "NSStringHelperFunctions.h"

/* No longer in use? Should remove. Doesn't always work */
// I couldn't find an official method to figure out if an id was a class or instance
/*
bool ObjectSupport_IsClass(id the_ptr)
{
	if(nil == the_ptr)
	{
		return false;
	}
	if((void*)[the_ptr class] == (void*)[the_ptr self])
	{
		return true;
	}
	else
	{
		return false;
	}
}
*/

// I couldn't find an official method to figure out if an id was a class or instance
bool ObjectSupport_IsInstance(id the_ptr)
{
	if(nil == the_ptr)
	{
		return false;
	}
	if((void*)[the_ptr class] != (void*)[the_ptr self])
	{
		return true;
	}
	else
	{
		return false;
	}
}


//
// From PyObjC and JSCocoa: when to call objc_msgSend_stret, for structure return
//		Depending on structure size & architecture, structures are returned as function first argument (done transparently by ffi) or via registers
//
#if defined(__ppc__)
#   define SMALL_STRUCT_LIMIT	4
#elif defined(__ppc64__)
#   define SMALL_STRUCT_LIMIT	8
#elif defined(__i386__) 
#   define SMALL_STRUCT_LIMIT 	8
#elif defined(__x86_64__) 
#   define SMALL_STRUCT_LIMIT	16
#elif TARGET_OS_IPHONE
// TOCHECK
#   define SMALL_STRUCT_LIMIT	4
#else
#   error "Unsupported MACOSX platform"
#endif


bool ObjectSupport_NeedsStret(NSString* return_value_objc_encoding_type)
{
	int resultSize = 0;
	if(nil == return_value_objc_encoding_type)
	{
		return false;
	}
	char returnEncoding = [return_value_objc_encoding_type UTF8String][0];
	if (returnEncoding == _C_STRUCT_B)
	{
		resultSize = [ParseSupport sizeOfStructureFromArrayOfPrimitiveObjcTypes:[ParseSupport typeEncodingsOfStructureFromStructureTypeEncoding:return_value_objc_encoding_type]];		
	}
	if (returnEncoding == _C_STRUCT_B && 
		//#ifdef  __ppc64__
		//			ffi64_stret_needs_ptr(signature_to_ffi_return_type(rettype), NULL, NULL)
		//
		//#else /* !__ppc64__ */
		(resultSize > SMALL_STRUCT_LIMIT
#ifdef __i386__
		 /* darwin/x86 ABI is slightly odd ;-) */
		 || (resultSize != 1 
			 && resultSize != 2 
			 && resultSize != 4 
			 && resultSize != 8)
#endif
#ifdef __x86_64__
		 /* darwin/x86-64 ABI is slightly odd ;-) */
		 || (resultSize != 1 
			 && resultSize != 2 
			 && resultSize != 4 
			 && resultSize != 8
			 && resultSize != 16
			 )
#endif
		 )
		//#endif /* !__ppc64__ */
		) {
		//					callAddress = objc_msgSend_stret;
		//					usingStret = YES;
		return true;
	}
	return false;				
}

//
//	Return the correct objc_msgSend* variety according to encodings
//
void* ObjectSupport_GetObjcMsgSendCallAddress(NSString* return_value_objc_encoding_type, bool is_super)
{
	bool needs_stret = ObjectSupport_NeedsStret(return_value_objc_encoding_type);
	void* call_address = NULL;

	if(is_super)
	{
		if(needs_stret)
		{
			call_address = objc_msgSendSuper_stret;
		}
		else
		{
			call_address = objc_msgSendSuper;
		}
	}
	else
	{
		if(needs_stret)
		{	
			call_address = objc_msgSend_stret;
		}
#if defined(__i386__)
		else if(!strncmp([return_value_objc_encoding_type UTF8String], @encode(float), 1) || !strncmp([return_value_objc_encoding_type UTF8String], @encode(double), 1) || !strncmp([return_value_objc_encoding_type UTF8String], @encode(long double), 1))
		{
			call_address = objc_msgSend_fpret;
		}
#elif defined(__x86_64__)
		else if(!strncmp([return_value_objc_encoding_type UTF8String], @encode(long double), 1))
		{
			call_address = objc_msgSend_fpret;
		}
#endif
		else
		{
			call_address = objc_msgSend;
		}
	}
	
	return call_address;
}


// Assumes NULL terminated string
int ObjectSupport_CountNumberOfColonsInString(const char* the_string)
{
	size_t string_length = strlen(the_string);
	size_t character_counter = 0;
	for(size_t char_index=0; char_index<string_length; char_index++)
	{
		if(':' == the_string[char_index])
		{
			character_counter++;
		}
	}
	return character_counter;
}

// Uses class_getSuperclass. Will not be fooled by NSProxy.
// If class is the parent class, it is considered to be a subclass of it.
bool ObjectSupport_IsSubclassOfClass(Class your_subclass_class, Class parent_class)
{
	do
	{
//		NSLog(@"your_subclass_class:%s, parent_class:%s", class_getName(your_subclass_class), class_getName(parent_class));
		if(your_subclass_class == parent_class)
		{
			return true;
		}
//		your_subclass_class = class_getSuperclass(your_subclass_class);
		
	} while(nil != (your_subclass_class = class_getSuperclass(your_subclass_class)));
//	} while(NULL != your_subclass_class);
	return false;
}

bool ObjectSupport_IsSubclassOrProtocolOf(Class your_subclass_class, const char* parent_class_or_protocol_name)
{
	if(class_conformsToProtocol(your_subclass_class, objc_getProtocol(parent_class_or_protocol_name)))
	{
		return true;
	}
	else if(ObjectSupport_IsSubclassOfClass(your_subclass_class, objc_getClass(parent_class_or_protocol_name)))
	{
		return true;
	}
	else
	{
		return false;
	}
}

// Intended to be "fooled" by NSProxy
Class ObjectSupport_GetSuperClassFromClass(Class the_class)
{
	Class return_class;
	if(ObjectSupport_IsSubclassOfClass(the_class, objc_getClass("NSProxy")))
	{
		return_class = [the_class superclass];
	}
	else
	{
		return_class = class_getSuperclass(the_class);

	}
	return return_class;
}

// Intended to be "fooled" by NSProxy
Class ObjectSupport_GetSuperClassFromObject(id the_object)
{
	Class return_class;
	if(ObjectSupport_IsSubclassOfClass(object_getClass(the_object), objc_getClass("NSProxy")))
	{
		return_class = [the_object superclass];
	}
	else
	{
		return_class = class_getSuperclass(object_getClass(the_object));
		
	}
	return return_class;
}

// Intended to be "fooled" by NSProxy
Class ObjectSupport_GetClassFromClass(Class the_class)
{
	Class return_class;
	if(ObjectSupport_IsSubclassOfClass(the_class, objc_getClass("NSProxy")))
	{
		return_class = [the_class class];
	}
	else
	{
		return_class = the_class;
		
	}
	return the_class;
}

// Intended to be "fooled" by NSProxy
Class ObjectSupport_GetClassFromObject(id the_object)
{
	Class return_class;
	if(ObjectSupport_IsSubclassOfClass(object_getClass(the_object), objc_getClass("NSProxy")))
	{
		return_class = [the_object class];
	}
	else
	{
		return_class = object_getClass(the_object);
		
	}
	return return_class;
}

// FIXME: May not handle class vs instance methods correctly.
bool ObjectSupport_ConvertUnderscoredSelectorToObjCForProxy(char objc_dst_string[], const char* underscored_src_string, size_t max_buffer_size, id the_object, bool is_instance, SEL* the_selector)
{
	
	size_t method_string_length = strlen(underscored_src_string);
	// Add 2: 1 for null character, 1 for possible last underscore that was omitted by scripter
	//	char objc_method_name[method_string_length+2];
	
	strlcpy(objc_dst_string, underscored_src_string, max_buffer_size);
	
	// Replace all underscores with colons
	for(size_t char_index=0; char_index<method_string_length; char_index++)
	{
		if('_' == objc_dst_string[char_index])
		{
			objc_dst_string[char_index] = ':';
		}
	}
	
	Class the_class;
	
	*the_selector = sel_registerName(objc_dst_string);
	BOOL found_method = NO;

	if(is_instance)
	{
		found_method = [the_object respondsToSelector:*the_selector];
	}
	else
	{
		the_class = [the_object class];
//		NSLog(@"class: %s", class_getName(the_class));

		found_method = [the_class instancesRespondToSelector:*the_selector];

	}

	// Special check/handling for omitting final underscore. Is this wise? I hear PyObjC frowns upon this.
	if(false == found_method)
	{
		objc_dst_string[method_string_length] = ':';
		objc_dst_string[method_string_length+1] = '\0';
		*the_selector = sel_registerName(objc_dst_string);
		
		if(is_instance)
		{
			found_method = [the_object respondsToSelector:*the_selector];
		}
		else
		{
			the_class = [the_object class];
			//		NSLog(@"class: %s", class_getName(the_class));
			
			found_method = [the_class instancesRespondToSelector:*the_selector];
			
		}
		// undo the : append if we still didn't find the method
		if(NO == found_method)
		{
			objc_dst_string[method_string_length] = '\0';
			*the_selector = sel_registerName(objc_dst_string);			
		}

		
	}
	
	if(NO == found_method)
	{
		return false;
		//			return luaL_error(lua_state, "Receiver %s does not implement method %s", class_getName(the_object->isa), objc_method_name);
	}
	else
	{
		return true;
	}
}

bool ObjectSupport_ConvertUnderscoredSelectorToObjC(char objc_dst_string[], const char* underscored_src_string, size_t max_buffer_size, id the_object, bool is_instance, SEL* the_selector, bool is_class_method)
{
	Method ret_method = ObjectSupport_ConvertUnderscoredSelectorToObjCAndGetMethod(objc_dst_string, underscored_src_string, max_buffer_size, the_object, is_instance, the_selector, is_class_method);
	if(NULL == ret_method)
	{
		return false;
	}
	else
	{
		return true;
	}
}


Method ObjectSupport_ConvertUnderscoredSelectorToObjCAndGetMethod(char objc_dst_string[], const char* underscored_src_string, size_t max_buffer_size, id the_object, bool is_instance, SEL* the_selector, bool is_class_method)
{
	Class the_class;
	Method the_method = NULL;

	if(is_instance)
	{
		the_class = object_getClass(the_object);
	}
	else
	{
		the_class = the_object;
	}
	
	bool is_proxy = ObjectSupport_IsSubclassOfClass(the_class, objc_getClass("NSProxy"));
	if(true == is_proxy)
	{
		// FIXME: May not handle class vs instance methods correctly.
		bool did_find = ObjectSupport_ConvertUnderscoredSelectorToObjCForProxy(objc_dst_string, underscored_src_string, max_buffer_size, the_object, is_instance, the_selector);
		if(true == did_find)
		{
			if(is_class_method)
			{
				the_method = class_getClassMethod(the_class, *the_selector);
			}
			else
			{
				the_method = class_getInstanceMethod(the_class, *the_selector);
			}
			return the_method;
		}
		else
		{
			return NULL;
		}

	}
	
	size_t method_string_length = strlen(underscored_src_string);
	// Add 2: 1 for null character, 1 for possible last underscore that was omitted by scripter
	//	char objc_method_name[method_string_length+2];
	
	strlcpy(objc_dst_string, underscored_src_string, max_buffer_size);
	
	// Replace all underscores with colons
	for(size_t char_index=0; char_index<method_string_length; char_index++)
	{
		if('_' == objc_dst_string[char_index])
		{
			objc_dst_string[char_index] = ':';
		}
	}
	
	
	*the_selector = sel_registerName(objc_dst_string);
	
	if(is_class_method)
	{
		the_method = class_getClassMethod(the_class, *the_selector);
	}
	else
	{
		the_method = class_getInstanceMethod(the_class, *the_selector);
	}

	
	// Special check/handling for omitting final underscore. Is this wise? I hear PyObjC frowns upon this.
	if(NULL == the_method)
	{
		objc_dst_string[method_string_length] = ':';
		objc_dst_string[method_string_length+1] = '\0';
		*the_selector = sel_registerName(objc_dst_string);
		if(is_class_method)
		{
			the_method = class_getClassMethod(the_class, *the_selector);
		}
		else
		{
			the_method = class_getInstanceMethod(the_class, *the_selector);
		}	
		
		// undo the : append if we still didn't find the method
		if(NULL == the_method)
		{
			objc_dst_string[method_string_length] = '\0';
			*the_selector = sel_registerName(objc_dst_string);			
		}
	}
	
	return the_method;
}



SEL ObjectSupport_ConvertUnderscoredSelectorToObjCWithSignatureStringForMethod(char objc_dst_string[], const char* underscored_src_string, size_t max_buffer_size, const char* signature_string)
{
	
	size_t method_string_length = strlen(underscored_src_string);
	// Add 2: 1 for null character, 1 for possible last underscore that was omitted by scripter
	//	char objc_method_name[method_string_length+2];
	
	strlcpy(objc_dst_string, underscored_src_string, max_buffer_size);
	
	
	const char* signature_string_char_ptr = signature_string;
	size_t signature_string_length = 0;
	size_t current_signature_string_index = 0;
	if(NULL != signature_string)
	{
		signature_string_length = strlen(signature_string);
		if(signature_string_length < 3)
		{
			NSLog(@"Invalid signature for method");
			signature_string_length = 0;
			signature_string_char_ptr = NULL;
			return NULL;
		}
		else
		{
			signature_string_char_ptr++; // advance the pointer to skip the return value
			signature_string_char_ptr++; // advance the pointer to skip the self parameter
			signature_string_char_ptr++; // advance the pointer to skip the selector
			current_signature_string_index = 3;				
		}
	}
	
//	size_t count_of_replacements = 0;
	bool found_invalid_name = false;
	// Replace all underscores with colons
	for(size_t char_index=0; char_index<method_string_length; char_index++)
	{
		if('_' == objc_dst_string[char_index])
		{
			objc_dst_string[char_index] = ':';
			if(NULL != signature_string_char_ptr && '\0' != signature_string_char_ptr[0])
			{
//				count_of_replacements++;
				signature_string_char_ptr++;
				current_signature_string_index++;
			}
			else
			{
				signature_string_char_ptr = NULL;
				found_invalid_name = true;
				break;
			}
		}
	}

	if(true == found_invalid_name)
	{
		return NULL;
	}
	// Check to see if we need another underscore
	if(current_signature_string_index == signature_string_length)
	{
		// all is good
	}
	else if((current_signature_string_index+1) == signature_string_length)
	{
		objc_dst_string[signature_string_length] = ':';
		objc_dst_string[signature_string_length+1] = '\0';
	}
	else
	{
		NSLog(@"incorrect number of underscores for signature");
		return NULL;
	}

	
	
	return sel_registerName(objc_dst_string);
}


bool ObjectSupport_IsGetterPropertyEquivalent(const char* property_name, id the_object, bool is_instance, SEL* the_selector)
{
	bool found_property = false;
	// +1 for NULL and another +1 for optional omitted underscore
	size_t max_str_length = strlen(property_name)+2;
	
	char objc_dst_string[max_str_length];
	ObjectSupport_ConvertUnderscoredSelectorToObjC(objc_dst_string, property_name, max_str_length, the_object, is_instance, the_selector, !is_instance);

	// do this after the Convert so we have a filled selector/method before returning
	objc_property_t the_property = class_getProperty(the_object->isa, property_name);
	if(NULL != the_property)
	{
		return true;
	}
	// Fallback. It not declared as a property.
	// But if there is a corresponding setter, then I feel it will be safe enough to be considered a property
	
	
	NSString* property_string = [NSString stringWithUTF8String:property_name];
	NSString* setter_name = [[@"set" stringByAppendingString:NSStringHelperFunctions_CapitalizeFirstCharacter(property_string)] stringByAppendingString:@":"];
	
	// +1 for NULL and another +1 for optional omitted underscore
	size_t setter_max_str_length = [setter_name length]+2;
	
	
	char setter_objc_dst_string[setter_max_str_length];
	SEL setter_selector;
	if(ObjectSupport_ConvertUnderscoredSelectorToObjC(setter_objc_dst_string, [setter_name UTF8String], setter_max_str_length, the_object, is_instance, &setter_selector, !is_instance))
	{
		// Looks like we found something.
		// Additional check: make sure getter (not setter) has no parameters
		size_t number_of_colons = ObjectSupport_CountNumberOfColonsInString(objc_dst_string);
		if(0 == number_of_colons)
		{
			found_property = true;
		}
	}

	return found_property;
}

NSString* ObjectSupport_GetMethodReturnType(id the_receiver, SEL the_selector, bool is_instance)
{
	Class the_class;
	if(is_instance)
	{
		the_class = object_getClass(the_receiver);
	}
	else
	{
		the_class = the_receiver;
	}
//	NSLog(@"class_getName: %s", class_getName(the_class));
	if(ObjectSupport_IsSubclassOrProtocolOf(the_class, "NSObject"))
	{
		if(is_instance)
		{
			// use 
			// - (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector;
			NSMethodSignature* method_signature = [the_receiver methodSignatureForSelector:the_selector];
			NSString* ret_string = [NSString stringWithUTF8String:[method_signature methodReturnType]];
			return ret_string;
		}
		else
		{
			the_class = [the_class class];
			
			Method the_method = class_getClassMethod(the_class, the_selector);
			char* the_return_type = method_copyReturnType(the_method);
			NSString* ret_string = [NSString stringWithUTF8String:the_return_type];
			free(the_return_type);
			return ret_string;
		}
	}
	else
	{
		// Fallback. This is some weird object.
		Method the_method = class_getClassMethod(the_class, the_selector);
		char* the_return_type = method_copyReturnType(the_method);
		NSString* ret_string = [NSString stringWithUTF8String:the_return_type];
		free(the_return_type);
		return ret_string;
	}
}

bool ObjectSupport_ConvertObjCSelectorToUnderscoredString(char dst_string[], size_t max_buffer_size, SEL the_selector)
{
	const char* selector_name = sel_getName(the_selector);
	size_t copy_length = strlen(selector_name);
	bool encountered_error = false;
	if(max_buffer_size <= copy_length)
	{
		encountered_error = true;
		copy_length = max_buffer_size - 1;

	}
	for(int i=0; i<copy_length; i++)
	{
		if(':' == selector_name[i])
		{		
			dst_string[i] = '_';
		}
		else
		{
			dst_string[i] = selector_name[i];
		}
	}
	dst_string[copy_length] = '\0';
	return encountered_error;
}

bool ObjectSupport_ConvertObjCStringToUnderscoredString(char dst_string[], const char* objc_string, size_t max_buffer_size)
{
	size_t copy_length = strlen(objc_string);
	bool encountered_error = false;
	if(max_buffer_size <= copy_length)
	{
		encountered_error = true;
		copy_length = max_buffer_size - 1;
		
	}
	for(int i=0; i<copy_length; i++)
	{
		if(':' == objc_string[i])
		{		
			dst_string[i] = '_';
		}
		else
		{
			dst_string[i] = objc_string[i];
		}
	}
	dst_string[copy_length] = '\0';
	return encountered_error;
}