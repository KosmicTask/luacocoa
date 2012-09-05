/*
 *  TextEditorSupport.h
 *  LuaCocoa
 *
 *  Copyright 2008 Eric Wing. All rights reserved.
 *
 */

#ifndef _TextEditorSupport_H_
#define _TextEditorSupport_H_

#import <Cocoa/Cocoa.h>

#ifdef __cplusplus
extern "C" {
#endif
	
void TextEditorSupport_LaunchTextEditorWithFile(NSString* file_name, NSInteger line_number);
	
#ifdef __cplusplus
}
#endif

#endif //_TextEditorSupport_H_