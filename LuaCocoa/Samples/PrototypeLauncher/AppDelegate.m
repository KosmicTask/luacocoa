//
//  AppDelegate.m
//  PrototypeLauncher
//
//  Created by Eric Wing on 3/14/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "AppDelegate.h"

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
	AppDelegate* lua_controller = (AppDelegate*)client_call_back_info;
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

@implementation AppDelegate

@synthesize theWindow;
@synthesize watchedFiles;
@synthesize currentLuaFile;

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
	eventStream = FileWatch_StartMonitoringFolder([[self currentLuaFile] stringByDeletingLastPathComponent], &Internal_LuaFolderChangedCallbackFunction, &callback_info);
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
	
//	NSString* lua_file = [[NSBundle mainBundle] pathForResource:@"MyAnimationDescription" ofType:@"lua"];
	NSString* lua_file = [self currentLuaFile];
	NSInteger the_choice = NSRunAlertPanel(@"Lua Error", error_string, @"Open File", @"Ignore", nil);
	if(NSAlertDefaultReturn == the_choice)
	{
		TextEditorSupport_LaunchTextEditorWithFile(lua_file, line_number);
		return true;
	}
	
	return false;
}


// For the Open menu item
- (IBAction) openDocument:(id)thesender
{
	NSOpenPanel* panel = [NSOpenPanel openPanel];
	[panel setCanChooseDirectories:NO];
	[panel setCanChooseFiles:YES];
	[panel setAllowsMultipleSelection:NO];
	[panel setAllowedFileTypes:[NSArray arrayWithObjects:@"lua", @"olua", nil]];

	[panel beginSheetModalForWindow:[self theWindow] completionHandler:^(NSInteger returncode)
		{
			if(NSFileHandlingPanelOKButton == returncode)
			{
				NSURL* url = [[panel URLs] objectAtIndex:0];
				[self loadLuaFile:[url path]];
			}
		}
	];
	
}

// For both Open Recents and launching documents via Finder (dragging on to the Dock, double-clicking, etc.)
- (BOOL) application:(NSApplication*)the_sender openFile:(NSString*)file_name
{
	return [self loadLuaFile:file_name];
}

- (bool) loadLuaFile:(NSString*)the_path
{
	if(isLoaded)
	{
		lua_State* lua_state = [luaCocoa luaState];
		lua_getglobal(lua_state, "OnUnloadBeforeReload");  /* get function */
		if(lua_isfunction(lua_state, -1 ))
		{		
			lua_pop(lua_state, 1);
			NSString* error_string = [luaCocoa pcallLuaFunction:"OnUnloadBeforeReload" withSignature:""];
			if(nil != error_string)
			{
				[self promptUserToOpenLuaFileAtError:error_string];
			}
		}
		else
		{
			lua_pop(lua_state, 1);
		}
	}
	[luaCocoa release];
	luaCocoa = nil;
	isLoaded = false;
	[LuaCocoa collectExhaustivelyWaitUntilDone:true];
	[self setCurrentLuaFile:the_path];
	[self setupLuaCocoa:[self currentLuaFile]];

	// Add the file to the recents list
	NSDocumentController* doccontroller = [NSDocumentController sharedDocumentController];
	[doccontroller noteNewRecentDocumentURL:[NSURL fileURLWithPath:the_path]];
	
	// Change the title to show the current loaded file. 
	// It should only be the base name. (See TextEdit)
	[theWindow setTitle:[the_path lastPathComponent]];
	// Set the proxy icon for the file because we want to be a good Mac citizen and I think the proxy stuff is a real conveniece to use.
	[theWindow setRepresentedFilename:the_path];
		
	return true;
}

- (void) setupLuaCocoa:(NSString*)the_path
{
	LuaCocoa* lua_cocoa = [[LuaCocoa alloc] init];
	luaCocoa = lua_cocoa;
	struct lua_State* lua_state = [lua_cocoa luaState];
	int the_error;
	


	
	LCFileWatch* file_watch = [[[LCFileWatch alloc] initWithFile:the_path] autorelease];
	self.watchedFiles = [NSArray arrayWithObject:file_watch];
	[self startFSEvents];	

	
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
	
	
	lua_getglobal(lua_state, "OnLoadFinished");  /* get function */
	if(lua_isfunction(lua_state, -1 ))
	{
		lua_pop(lua_state, 1);
		NSString* error_string = [luaCocoa pcallLuaFunction:"OnLoadFinished" withSignature:""];
		if(nil != error_string)
		{
			[self promptUserToOpenLuaFileAtError:error_string];
		}
	}
	else
	{
		lua_pop(lua_state, 1);
	}
	isLoaded = true;
}

- (void) reloadLuaFile
{
	[self loadLuaFile:[self currentLuaFile]];
}

/*
- (id) init
{
	self = [super init];
	if(nil != self)
	{
		NSString* the_path = [[NSBundle mainBundle] pathForResource:@"Default" ofType:@"lua"];
		[self loadLuaFile:the_path];
	}
	return self;
}
*/


- (void) dealloc
{
	[luaCocoa release];
	[super dealloc];	
}



- (void) applicationDidFinishLaunching:(NSNotification*)the_notification
{
	NSDocumentController* doccontroller = [NSDocumentController sharedDocumentController];
	NSArray* recentlist = [doccontroller recentDocumentURLs];
	NSString* the_path = nil;
	if([recentlist count] > 0)
	{
		the_path = [[recentlist objectAtIndex:0] path];
	}
	else
	{
		the_path = [[NSBundle mainBundle] pathForResource:@"Default" ofType:@"lua"];		
	}
	[self loadLuaFile:the_path];
}

- (void) applicationWillTerminate:(NSNotification*)the_notification
{
	[self stopFSEvents];
}

- (IBAction) action1:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction1" withSignature:"@@", the_sender, self];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action2:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction2" withSignature:"@@", the_sender, self];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action3:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction3" withSignature:"@@", the_sender, self];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action4:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction4" withSignature:"@@", the_sender, self];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action5:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction5" withSignature:"@@", the_sender, self];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) openLuaFile:(id)the_sender
{
//	NSString* lua_file = [[NSBundle mainBundle] pathForResource:@"MyAnimationDescription" ofType:@"lua"];
	NSString* lua_file = [self currentLuaFile];
	TextEditorSupport_LaunchTextEditorWithFile(lua_file, 0);
}


@end
