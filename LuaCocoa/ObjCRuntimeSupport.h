//
//  ObjCRuntimeSupport.h
//  LuaCocoa
//
//  Created by Eric Wing on 10/24/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//



#ifndef _OBJCRUNTIME_SUPPORT_H_
#define _OBJCRUNTIME_SUPPORT_H_

#include <stddef.h>


#ifdef __cplusplus
extern "C" {
#endif

size_t ObjCRuntimeSupport_SizeOfTypeEncoding(char objc_type_encoding);
	
#ifdef __cplusplus
}
#endif



#endif /* _OBJCRUNTIME_SUPPORT_H_ */