//
//  CoreAnimationScriptabilityAppDelegate.m
//  CoreAnimationScriptability
//
//  Created by Eric Wing on 11/1/10.
//  Copyright 2010 PlayControl Software, LLC. All rights reserved.
//

#import "CoreAnimationScriptabilityAppDelegate.h"
#import <LuaCocoa/LuaCocoa.h>
#import "LCFileWatch.h"
#import "TextEditorSupport.h"

void Internal_LuaFolderChangedCallbackFunction(
	ConstFSEventStreamRef stream_ref,
	void* client_call_back_info,
	size_t num_events,
	void* event_paths,
	const FSEventStreamEventFlags event_flags[],
	const FSEventStreamEventId event_ids[])
{
#if 0
	int i;
	char** the_paths = event_paths;

	NSLog(@"Callback called, num_events=%d\n", num_events);
	for (i=0; i<num_events; i++)
	{
        /* flags are unsigned long, IDs are uint64_t */
        printf("Change %llu in %s, flags %lu\n", event_ids[i], the_paths[i], event_flags[i]);
	}
#endif
	CoreAnimationScriptabilityAppDelegate* lua_controller = (CoreAnimationScriptabilityAppDelegate*)client_call_back_info;
	[lua_controller stopFSEvents];
	
	bool needs_reload = false;
	for(LCFileWatch* file_watch in lua_controller.watchedFiles)
	{
		if([file_watch fileHasBeenChanged])
		{
			needs_reload = true;
			[file_watch updateTimeStat];
		}
	}

	if(needs_reload)
	{	
		[lua_controller reloadLuaFile];
	}

	[lua_controller startFSEvents];
}
	
	
@implementation CoreAnimationScriptabilityAppDelegate

@synthesize theWindow;
@synthesize animatableLayer;
@synthesize watchedFiles;

- (void) startFSEvents
{
    FSEventStreamContext callback_info =
	{
		0,
		self,
		CFRetain,
		CFRelease,
		NULL
	};
	eventStream = FileWatch_StartMonitoringFolder([[NSBundle mainBundle] resourcePath], &Internal_LuaFolderChangedCallbackFunction, &callback_info);
}

- (void) stopFSEvents
{
	FileWatch_StopMonitoringFolder(eventStream);
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
	
	NSString* lua_file = [[NSBundle mainBundle] pathForResource:@"MyAnimationDescription" ofType:@"lua"];
	NSInteger the_choice = NSRunAlertPanel(@"Lua Error", error_string, @"Open File", @"Ignore", nil);
	if(NSAlertDefaultReturn == the_choice)
	{
		TextEditorSupport_LaunchTextEditorWithFile(lua_file, line_number);
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
	
	the_path = [[NSBundle mainBundle] pathForResource:@"MyAnimationDescription" ofType:@"lua"];


	[self startFSEvents];
	
	LCFileWatch* file_watch = [[[LCFileWatch alloc] initWithFile:the_path] autorelease];
	self.watchedFiles = [NSArray arrayWithObject:file_watch];


	
	the_error = luaL_loadfile(lua_state, [the_path fileSystemRepresentation]);
	if(0 != the_error)
	{
		//			NSLog(@"error");
		NSLog(@"luaL_loadfile failed: %s", lua_tostring(lua_state, -1));
//		[luaCocoa error:"luaL_loadfile failed: %s", lua_tostring(lua_state, -1)];
		[self promptUserToOpenLuaFileAtError:[NSString stringWithUTF8String:lua_tostring(lua_state, -1)]];
		lua_pop(lua_state, 1); /* pop error message from stack */
		return;
	}
	
	the_error = lua_pcall(lua_state, 0, 0, 0);
	if(0 != the_error)
	{
		//			NSLog(@"error");
		NSLog(@"Lua parse load failed: %s", lua_tostring(lua_state, -1));
		[self promptUserToOpenLuaFileAtError:[NSString stringWithUTF8String:lua_tostring(lua_state, -1)]];
		lua_pop(lua_state, 1); /* pop error message from stack */
		return;
	}
	
	
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnLoadFinished" withSignature:""];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
	isLoaded = true;
	
}

- (void) reloadLuaFile
{
	if(isLoaded)
	{
		NSString* error_string = [luaCocoa pcallLuaFunction:"OnUnloadBeforeReload" withSignature:""];
		if(nil != error_string)
		{
			[self promptUserToOpenLuaFileAtError:error_string];
		}		
	}
	[luaCocoa release];
	luaCocoa = nil;
	isLoaded = false;
	[LuaCocoa collectExhaustivelyWaitUntilDone:true];
	[self setupLuaCocoa];
}

// TODO: Figure out how to simply set the view class to SimpleLuaView and have this all work without code.
// Currently, the nib complains on launch that the class doesn't exist.
- (void) setupView
{
	CALayer* animatable_layer = [CALayer layer];
	
//	CGColorSpaceRef rgb_color_space = CGColorSpaceCreateDeviceRGB();
//	CGFloat rgb_values[4] = {1.0, 0.0, 0.0, 1.0}; 
//	CGColorRef layer_color = CGColorCreate(rgb_color_space, rgb_values); 
	
	animatable_layer.backgroundColor = (CGColorRef)[NSMakeCollectable(CGColorCreateGenericRGB(1.0, 0.0, 0.0, 1.0)) autorelease];

//	CGColorSpaceRelease(rgb_color_space);

	animatable_layer.frame = CGRectMake(50.0, 80.0, 150.0, 150.0);
	
	[[self.theWindow.contentView layer] addSublayer:animatable_layer];
	self.animatableLayer = animatable_layer;

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


- (void) dealloc
{
	[luaCocoa release];
	[super dealloc];	
}



- (void) applicationDidFinishLaunching:(NSNotification*)the_notification
{
	[self setupView];
}

- (void) applicationWillTerminate:(NSNotification*)the_notification
{
	[self stopFSEvents];
}

- (void) animationDidStop:(CAAnimation*)the_animation finished:(BOOL)reached_natural_end
{
//	NSLog(@"animationDidStop: %@, normally=%d, valueForNameKey=%@", the_animation, reached_natural_end, [the_animation valueForKey:@"name"]);
	if(isLoaded)
	{
		NSString* error_string = [luaCocoa pcallLuaFunction:"OnAnimationDidStop" withSignature:"@@b", self.animatableLayer, the_animation, reached_natural_end];
		if(nil != error_string)
		{
			[self promptUserToOpenLuaFileAtError:error_string];
		}		
	}
}


- (IBAction) action1:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction1" withSignature:"@@", self.animatableLayer, self];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action2:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction2" withSignature:"@@", self.animatableLayer, self];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action3:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction3" withSignature:"@@", self.animatableLayer, self];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action4:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction4" withSignature:"@@", self.animatableLayer, self];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action5:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction5" withSignature:"@@", self.animatableLayer, self];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) openLuaFile:(id)the_sender
{
	NSString* lua_file = [[NSBundle mainBundle] pathForResource:@"MyAnimationDescription" ofType:@"lua"];
	TextEditorSupport_LaunchTextEditorWithFile(lua_file, 0);
}


@end
