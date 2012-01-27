//
//  CoreAnimationScriptabilityAppDelegate.h
//  CoreAnimationScriptability
//
//  Created by Eric Wing on 11/1/10.
//  Copyright 2010 PlayControl Software, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class LuaCocoa;

@interface CoreAnimationScriptabilityAppDelegate : NSObject <NSApplicationDelegate>
{
    NSWindow* theWindow;
	LuaCocoa* luaCocoa;
	CALayer* animatableLayer;
	NSArray* watchedFiles;
	FSEventStreamRef eventStream;
	bool isLoaded;
}

@property (assign) IBOutlet NSWindow* theWindow;
@property (retain) CALayer* animatableLayer;
@property (copy) NSArray* watchedFiles;

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
