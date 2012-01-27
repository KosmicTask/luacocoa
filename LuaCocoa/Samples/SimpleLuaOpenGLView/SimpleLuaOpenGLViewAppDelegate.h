//
//  SimpleLuaOpenGLViewAppDelegate.h
//  SimpleLuaOpenGLView
//
//  Created by Eric Wing on 10/9/10.
//  Copyright 2010 PlayControl Software, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class LuaCocoa;

@interface SimpleLuaOpenGLViewAppDelegate : NSObject
{
    NSWindow *window;
	LuaCocoa* luaCocoa;
}

@property (assign) IBOutlet NSWindow *window;

@end
