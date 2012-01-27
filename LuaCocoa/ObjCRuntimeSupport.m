//
//  ObjCRuntimeSupport.m
//  LuaCocoa
//
//  Created by Eric Wing on 10/24/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "ObjCRuntimeSupport.h"
#import <objc/objc.h>
#import <objc/runtime.h>



size_t ObjCRuntimeSupport_SizeOfTypeEncoding(char objc_type_encoding)
{
	switch(objc_type_encoding)
	{
		case	_C_ID:		return	sizeof(id);
		case	_C_CLASS:	return	sizeof(Class);
		case	_C_SEL:		return	sizeof(SEL);
		case	_C_CHR:		return	sizeof(char);
		case	_C_UCHR:	return	sizeof(unsigned char);
		case	_C_SHT:		return	sizeof(short);
		case	_C_USHT:	return	sizeof(unsigned short);
		case	_C_INT:		return	sizeof(int);
		case	_C_UINT:	return	sizeof(unsigned int);
		case	_C_LNG:		return	sizeof(long);
		case	_C_ULNG:	return	sizeof(unsigned long);
		case	_C_LNG_LNG:	return	sizeof(long long);
		case	_C_ULNG_LNG:return	sizeof(unsigned long long);
		case	_C_FLT:		return	sizeof(float);
		case	_C_DBL:		return	sizeof(double);
		case	_C_BOOL:	return	sizeof(BOOL);
		case	_C_VOID:	return	sizeof(void);
		case	_C_PTR:		return	sizeof(void*);
		case	_C_CHARPTR:	return	sizeof(char*);
	}
	return 0; // assuming no type can return 0
}
