//
//  ClassSupport.h
//  LuaCocoa
//
//  Created by Eric Wing on 10/22/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#ifndef _OBJECT_SUPPORT_H_
#define _OBJECT_SUPPORT_H_

#include <stddef.h>
#import <objc/objc.h>
#import <objc/runtime.h>
#include <stdbool.h>

@class NSString;

#ifdef __cplusplus
extern "C" {
#endif
	
// Use these sparingly. They don't always work. I think NSProxy classes will crash (NSCFType base types).
bool ObjectSupport_IsInstance(id the_ptr);
//bool ObjectSupport_IsClass(id the_ptr);

	bool ObjectSupport_NeedsStret(NSString* return_value_objc_encoding_type);

	void* ObjectSupport_GetObjcMsgSendCallAddress(NSString* return_value_objc_encoding_type, bool is_super);
	
	
	// Assumes NULL terminated string
	int ObjectSupport_CountNumberOfColonsInString(const char* the_string);
	bool ObjectSupport_IsSubclassOfClass(Class your_subclass_class, Class parent_class);
	bool ObjectSupport_IsSubclassOrProtocolOf(Class your_subclass_class, const char* parent_class_or_protocol_name);

	Class ObjectSupport_GetSuperClassFromClass(Class the_class);
	Class ObjectSupport_GetSuperClassFromObject(id the_object);
	Class ObjectSupport_GetClassFromClass(Class the_class);
	Class ObjectSupport_GetClassFromObject(id the_object);


	bool ObjectSupport_ConvertUnderscoredSelectorToObjC(char objc_dst_string[], const char* underscored_src_string, size_t max_buffer_size, id the_object, bool is_instance, SEL* the_selector, bool is_class_method);
	SEL ObjectSupport_ConvertUnderscoredSelectorToObjCWithSignatureStringForMethod(char objc_dst_string[], const char* underscored_src_string, size_t max_buffer_size, const char* signature_string);
	Method ObjectSupport_ConvertUnderscoredSelectorToObjCAndGetMethod(char objc_dst_string[], const char* underscored_src_string, size_t max_buffer_size, id the_object, bool is_instance, SEL* the_selector, bool is_class_method);

	bool ObjectSupport_IsGetterPropertyEquivalent(const char* property_name, id the_object, bool is_instance, SEL* the_selector);

	NSString* ObjectSupport_GetMethodReturnType(id the_receiver, SEL the_selector, bool is_instance);


	bool ObjectSupport_ConvertObjCSelectorToUnderscoredString(char dst_string[], size_t max_buffer_size, SEL the_selector);
	bool ObjectSupport_ConvertObjCStringToUnderscoredString(char dst_string[], const char* objc_string, size_t max_buffer_size);
	
#ifdef __cplusplus
}
#endif



#endif /* _OBJECT_SUPPORT_H_ */