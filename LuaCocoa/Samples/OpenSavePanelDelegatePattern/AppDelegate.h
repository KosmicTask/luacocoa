//
//  AppDelegate.h
//  OpenSavePanelDelegatePattern
//
//  Created by Eric Wing on 2/15/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
@class LuaCocoa;

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
	LuaCocoa* luaCocoa;
	IBOutlet NSWindow* window;
}
@property (assign) IBOutlet NSWindow* window;

@end
