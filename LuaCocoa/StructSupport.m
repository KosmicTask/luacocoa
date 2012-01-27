//
//  StructSupport.m
//  LuaCocoa
//
//  Created by Eric Wing on 10/14/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//
// A lot of ideas and code in this file were taken from JSCocoa.


#import "StructSupport.h"
#include <objc/objc.h>
#include <objc/runtime.h>
#include "ObjCRuntimeSupport.h"
#include <stdio.h>

#pragma mark Encoding size, alignment, FFI


/*
 __alignOf__ returns 8 for double, but its struct align is 4
 
 use dummy structures to get struct alignment, each having a byte as first element
 */
typedef	struct { char a; id b;			} struct_C_ID;
typedef	struct { char a; char b;		} struct_C_CHR;
typedef	struct { char a; short b;		} struct_C_SHT;
typedef	struct { char a; int b;			} struct_C_INT;
typedef	struct { char a; long b;		} struct_C_LNG;
typedef	struct { char a; long long b;	} struct_C_LNG_LNG;
typedef	struct { char a; float b;		} struct_C_FLT;
typedef	struct { char a; double b;		} struct_C_DBL;
typedef	struct { char a; BOOL b;		} struct_C_BOOL;

ptrdiff_t StructSupport_AlignmentOfTypeEncoding(char objc_type_encoding)
{
	switch(objc_type_encoding)
	{
		case	_C_ID:		return	offsetof(struct_C_ID, b);
		case	_C_CLASS:	return	offsetof(struct_C_ID, b);
		case	_C_SEL:		return	offsetof(struct_C_ID, b);
		case	_C_CHR:		return	offsetof(struct_C_CHR, b);
		case	_C_UCHR:	return	offsetof(struct_C_CHR, b);
		case	_C_SHT:		return	offsetof(struct_C_SHT, b);
		case	_C_USHT:	return	offsetof(struct_C_SHT, b);
		case	_C_INT:		return	offsetof(struct_C_INT, b);
		case	_C_UINT:	return	offsetof(struct_C_INT, b);
		case	_C_LNG:		return	offsetof(struct_C_LNG, b);
		case	_C_ULNG:	return	offsetof(struct_C_LNG, b);
		case	_C_LNG_LNG:	return	offsetof(struct_C_LNG_LNG, b);
		case	_C_ULNG_LNG:return	offsetof(struct_C_LNG_LNG, b);
		case	_C_FLT:		return	offsetof(struct_C_FLT, b);
		case	_C_DBL:		return	offsetof(struct_C_DBL, b);
		case	_C_BOOL:	return	offsetof(struct_C_BOOL, b);
		case	_C_PTR:		return	offsetof(struct_C_ID, b);
		case	_C_CHARPTR:	return	offsetof(struct_C_ID, b);
	}
	return	-1;
}

/*
+ (ffi_type*)ffi_typeForTypeEncoding:(char)encoding
{
	switch (encoding)
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
*/

#pragma mark Structure encoding, size



// Returns an aligned pointer (at the address) of the passed in current pointer and encoding
void* StructSupport_AlignPointer(void* current_ptr, char objc_type_encoding)
{
	ptrdiff_t align_on_size = StructSupport_AlignmentOfTypeEncoding(objc_type_encoding);
	size_t aligned_address;
	if(align_on_size < 0)
	{
		// Error: Invalid encoding
		fprintf(stderr, "Error in StructSupport_AlignPointer: Invalid ObjC type encoding: %c\n", objc_type_encoding);
		return current_ptr;
	}
	
	aligned_address = (size_t)current_ptr;
	
	if( (aligned_address % align_on_size) != 0)
	{
		aligned_address = (aligned_address+(size_t)align_on_size) & ~(align_on_size-1);
	}
	return (void*)aligned_address;
}

// Returns a pointer to the next (struct element) location based on the current pointer and encoding
void* StructSupport_AdvancePointer(void* current_ptr, char objc_type_encoding)
{
	size_t next_address = (size_t)current_ptr;
	next_address += ObjCRuntimeSupport_SizeOfTypeEncoding(objc_type_encoding);
	return (void*)next_address;
}
