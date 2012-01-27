//
//  SimpleLuaOpenGLViewAppDelegate.m
//  SimpleLuaOpenGLView
//
//  Created by Eric Wing on 10/9/10.
//  Copyright 2010 PlayControl Software, LLC. All rights reserved.
//

#import "SimpleLuaOpenGLViewAppDelegate.h"

#import <LuaCocoa/LuaCocoa.h>
#include <LuaCocoa/lua.h>
#include <LuaCocoa/lualib.h>
#include <LuaCocoa/lauxlib.h>


@implementation SimpleLuaOpenGLViewAppDelegate

@synthesize window;

- (void) setupLuaCocoa
{
	LuaCocoa* lua_cocoa = [[LuaCocoa alloc] init];
	luaCocoa = lua_cocoa;
	struct lua_State* lua_state = [lua_cocoa luaState];
	NSString* the_path;
	int the_error;
	
	the_path = [[NSBundle mainBundle] pathForResource:@"SimpleLuaOpenGLView" ofType:@"lua"];
	the_error = luaL_loadfile(lua_state, [the_path fileSystemRepresentation]);
	if(the_error)
	{
		//			NSLog(@"error");
		NSLog(@"luaL_loadfile failed: %s", lua_tostring(lua_state, -1));
		lua_pop(lua_state, 1); /* pop error message from stack */
		exit(0);
	}
	
	the_error = lua_pcall(lua_state, 0, 0, 0);
	if(the_error)
	{
		//			NSLog(@"error");
		NSLog(@"Lua parse load failed: %s", lua_tostring(lua_state, -1));
		lua_pop(lua_state, 1); /* pop error message from stack */
		exit(0);
	}	
}

// TODO: Figure out how to simply set the view class to SimpleLuaView and have this all work without code.
// Currently, the nib complains on launch that the class doesn't exist.
- (void) setupSimpleLuaView
{
	Class new_class = NSClassFromString(@"SimpleLuaOpenGLView");
	id simple_lua_view = [[[new_class alloc] initWithFrame:[self.window.contentView frame]] autorelease];
	self.window.contentView = simple_lua_view;
}

- (id) init
{
	self = [super init];
	if(nil != self)
	{
		[self setupLuaCocoa];
	}
	return self;
}


- (void) applicationDidFinishLaunching:(NSNotification *)the_notification
{
	[self setupSimpleLuaView];
}

- (void) applicationWillTerminate:(NSNotification*)the_notification
{
	LuaCocoa* lua_cocoa = luaCocoa;
	
	// probably a good idea to call collectExhaustively before closing the lua state due to race condition potential
	[lua_cocoa release];
	luaCocoa = nil;
	// Interesting race condition bug:
	// I think the lua_State can be closed (via luaobjc_bridge finalize) before a LuaCocoaProxyObject is finalized leading to a bad access to the lua_State.
	// I'm not sure how to deal with this. I suspect closing the lua_State at the latest possible time of shutting down
	// your application and not instructing the garbage
	// collector to collect will maximize your chance of not hitting this condition.
	// Alternatively, if there is a way you can guarantee all LuaCocoaProxyObjects are collected before you shutdown the lua_State,
	// then you probably will avoid this situation.
	// ALERT: 10.7 bug. collectExhaustivelyWaitUntilDone:true will cause the application to hang on quit.
	// My suspicion is that it is connected to subclassing in Lua because the 
	// CoreAnimationScriptability example does not hang.
	// For now, I am changing true to false.
	// Filed rdar://10660280
	//	[LuaCocoa collectExhaustivelyWaitUntilDone:true];
	[LuaCocoa collectExhaustivelyWaitUntilDone:false];
}

@end
