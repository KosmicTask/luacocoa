//
//  AppDelegate.m
//  OpenSavePanelBlocksPattern
//
//  Created by Eric Wing on 3/14/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//


#import "AppDelegate.h"
#import "LuaCocoa.h"
//#import "TextEditorSupport.h"

@implementation AppDelegate

@synthesize window;

- (void)dealloc
{
    [super dealloc];
}



- (bool) promptUserToOpenLuaFileAtError:(NSString*)error_string
{
	NSLog(@"%@", error_string);
	
	int line_number = 0;
	// returned file_name is untrustworthy because Lua truncates long file names.
	NSString* file_name = LuaCocoa_ParseForErrorFilenameAndLineNumber(error_string, &line_number);
	
	if(line_number < 0)
	{
		line_number = 0;
	}
	
	NSString* lua_file = [[NSBundle mainBundle] pathForResource:@"OpenSavePanelBlocks" ofType:@"lua"];
	NSInteger the_choice = NSRunAlertPanel(@"Lua Error", error_string, @"Open File", @"Ignore", nil);
	if(NSAlertDefaultReturn == the_choice)
	{
		//		TextEditorSupport_LaunchTextEditorWithFile(lua_file, line_number);
		return true;
	}
	
	return false;
}

- (void) setupLuaCocoa
{
	LuaCocoa* lua_cocoa = [[LuaCocoa alloc] init];
	luaCocoa = lua_cocoa;
	struct lua_State* lua_state = [lua_cocoa luaState];
	NSString* the_path;
	int the_error;
	
	the_path = [[NSBundle mainBundle] pathForResource:@"OpenSavePanelBlocks" ofType:@"lua"];
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
	[LuaCocoa collectExhaustivelyWaitUntilDone:false];
}


- (IBAction) openDocument:(id)thesender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OpenDocument" withSignature:"@@", thesender, [self window]];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) saveDocument:(id)thesender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"SaveDocument" withSignature:"@@", thesender, [self window]];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

@end
