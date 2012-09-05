//
//  AppDelegate.h
//  OpenSavePanelBlocksPattern
//
//  Created by Eric Wing on 3/14/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class LuaCocoa;

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
	LuaCocoa* luaCocoa;
	IBOutlet NSWindow* window;
}

@property (assign) IBOutlet NSWindow *window;

@end
