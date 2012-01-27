//
//  SimpleLuaViewAppDelegate.h
//  SimpleLuaView
//
//  Created by Eric Wing on 9/18/10.
//  Copyright 2010 PlayControl Software, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class LuaCocoa;

@interface SimpleLuaViewAppDelegate : NSObject
{
    NSWindow *window;
	LuaCocoa* luaCocoa;
}

@property (assign) IBOutlet NSWindow *window;

@end
