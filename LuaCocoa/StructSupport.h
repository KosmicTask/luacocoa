//
//  StructSupport.h
//  LuaCocoa
//
//  Created by Eric Wing on 10/14/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//
// This code is used to help walk through the elements of an arbitrary struct
// that isn't known until runtime with help from (BridgeSupport) metadata.
// Because size and alignments of elements aren't directly known at runtime,
// the code in this file is used to help figure out what they actually are.

#ifndef _STRUCT_SUPPORT_H_
#define _STRUCT_SUPPORT_H_

#include <stddef.h>


#ifdef __cplusplus
extern "C" {
#endif
	


ptrdiff_t StructSupport_AlignmentOfTypeEncoding(char objc_type_encoding);

/**
 * Returns an aligned pointer (at the address) of the passed in current pointer and encoding.
 */
void* StructSupport_AlignPointer(void* current_ptr, char objc_type_encoding);

/**
 * Returns a pointer to the next (struct element) location based on the current pointer and encoding.
 */
void* StructSupport_AdvancePointer(void* current_ptr, char objc_type_encoding);

	
#ifdef __cplusplus
}
#endif



#endif /* _STRUCT_SUPPORT_H_ */