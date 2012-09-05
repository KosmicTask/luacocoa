//
//  AppDelegate.h
//  PrototypeLauncher
//
//  Created by Eric Wing on 3/14/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class LuaCocoa;

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
    NSWindow* theWindow;
	LuaCocoa* luaCocoa;
	NSArray* watchedFiles;
	FSEventStreamRef eventStream;
	bool isLoaded;
	NSString* currentLuaFile;
}

@property (assign) IBOutlet NSWindow* theWindow;
@property (copy) NSArray* watchedFiles;
@property (copy) NSString* currentLuaFile;

- (void) startFSEvents;
- (void) stopFSEvents;
- (void) reloadLuaFile;

- (IBAction) action1:(id)the_sender;
- (IBAction) action2:(id)the_sender;
- (IBAction) action3:(id)the_sender;
- (IBAction) action4:(id)the_sender;
- (IBAction) action5:(id)the_sender;
- (IBAction) openLuaFile:(id)the_sender;

@end
