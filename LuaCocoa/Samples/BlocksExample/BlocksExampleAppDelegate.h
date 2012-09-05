//
//  BlocksExampleAppDelegate.h
//  BlocksExample
//
//  Created by Eric Wing on 3/10/12.
//  Copyright (c) 2012 PlayControl Software, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class LuaCocoa;

@interface BlocksExampleAppDelegate : NSObject <NSApplicationDelegate>
{
	LuaCocoa* luaCocoa;
	IBOutlet NSWindow* window;
}
@property (assign) IBOutlet NSWindow* window;

@end


// Subclassing NSArray so I can test calling a block method that does not callback on the main thread.
// I use an existing class so I can utilize the BridgeSupport metadata for blocks.
@interface MySpecialArray : NSArray
{
	NSArray* realArray;
}

- (id) initWithArray:(NSArray*)the_array;

@end
