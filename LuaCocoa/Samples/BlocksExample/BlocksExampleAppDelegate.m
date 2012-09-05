//
//  BlocksExampleAppDelegate.h
//  BlocksExample
//
//  Created by Eric Wing on 3/10/12.
//  Copyright (c) 2012 PlayControl Software, LLC. All rights reserved.
//

#import "BlocksExampleAppDelegate.h"
#import <LuaCocoa/LuaCocoa.h>




@implementation BlocksExampleAppDelegate

@synthesize window;

- (void) promptUserToOpenLuaFileAtError:(NSString*)error_string
{
	NSLog(@"Error: %@", error_string);
}

- (void) setupLuaCocoa
{
	LuaCocoa* lua_cocoa = [[LuaCocoa alloc] init];
	luaCocoa = lua_cocoa;
	struct lua_State* lua_state = [lua_cocoa luaState];
	NSString* the_path;
	int the_error;
	
	the_path = [[NSBundle mainBundle] pathForResource:@"BlocksExample" ofType:@"lua"];
	
	the_error = luaL_loadfile(lua_state, [the_path fileSystemRepresentation]);
	if(0 != the_error)
	{
		//			NSLog(@"error");
		NSLog(@"luaL_loadfile failed: %s", lua_tostring(lua_state, -1));
		//		[luaCocoa error:"luaL_loadfile failed: %s", lua_tostring(lua_state, -1)];
		lua_pop(lua_state, 1); /* pop error message from stack */
		return;
	}
	
	the_error = lua_pcall(lua_state, 0, 0, 0);
	if(0 != the_error)
	{
		//			NSLog(@"error");
		NSLog(@"Lua parse load failed: %s", lua_tostring(lua_state, -1));
		lua_pop(lua_state, 1); /* pop error message from stack */
		return;
	}
	
	
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnLoadFinished" withSignature:""];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
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


- (void) dealloc
{
	[luaCocoa release];
	[super dealloc];	
}



- (void) applicationDidFinishLaunching:(NSNotification*)the_notification
{
}

- (void) applicationWillTerminate:(NSNotification*)the_notification
{
}

- (IBAction) action1:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction1" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action2:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction2" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action3:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction3" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action4:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction4" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action5:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction5" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action6:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction6" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action7:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction7" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action8:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction8" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action9:(id)the_sender
{
	id obj_block = ^ bool (id obj, NSInteger int_num)
	{
		NSLog(@"An Obj-C defined block: %@, %d", obj, int_num);
		return true;

	}; 
	// I don't think the bridge will support stack blocks
	obj_block = [[obj_block copy] autorelease];

	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction9" withSignature:"@", obj_block];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
}

- (IBAction) action10:(id)the_sender
{
	/*
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction10" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}
	 */	
	lua_State* lua_state = [luaCocoa luaState];

	
	lua_getglobal(lua_state, "OnAction10");  /* get function */
//	CGPoint the_point = CGPointMake(1, 2);
	CGRect the_point = CGRectMake(1, 2, 3, 4);
//	LuaCocoa_PushStruct(lua_state, &the_point, "CGPoint");
	LuaCocoa_PushStruct(lua_state, &the_point, "CGRect");
	
	if (lua_pcall(lua_state, 1, 0, 0) != 0)  /* do the call */
	{
		
		
		//		[self error:"Error running function '%s': %s",
		//			  lua_function_name, lua_tostring(lua_state, -1)];
		NSString* error_string = [NSString stringWithUTF8String:lua_tostring(lua_state, -1)];
		[self promptUserToOpenLuaFileAtError:error_string];
		lua_pop(lua_state, -1);
	}
}


- (IBAction) action11:(id)the_sender
{
	id obj_block = ^ CGRect (CGPoint point, CGSize size)
	{
		NSLog(@"making rect block");
		CGRect return_rect = CGRectMake(point.x, point.y, size.width, size.height);
		return return_rect;		
	};
	// I don't think the bridge will support stack blocks
	obj_block = [[obj_block copy] autorelease];
	
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction11" withSignature:"@", obj_block];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}	
}

- (IBAction) action12:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction12" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}	
}

- (IBAction) action13:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction13" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}	
}

- (IBAction) action14:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction14" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}	
}

- (IBAction) action15:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction15" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}	
}

- (IBAction) action16:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction16" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}	
}
- (IBAction) action17:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction17" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}	
}

- (IBAction) action18:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction18" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}	
}

- (IBAction) action19:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction19" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}	
}

- (IBAction) action20:(id)the_sender
{
	NSString* error_string = [luaCocoa pcallLuaFunction:"OnAction20" withSignature:"@", the_sender];
	if(nil != error_string)
	{
		[self promptUserToOpenLuaFileAtError:error_string];
	}	
}

@end



@implementation MySpecialArray

- (id)initWithArray: (NSArray *)array
{
	if((self = [self init]))
	{
		realArray = [array copy];
	}
	return self;
}

- (void)dealloc
{
	[realArray release];
	[super dealloc];
}

- (NSUInteger)count
{
	return [realArray count];
}

- (id)objectAtIndex: (NSUInteger)index
{
	id obj = [realArray objectAtIndex: index];
	// do some processing with obj
	return obj;
}


// Apple does not guarantee which thread their stuff calls back on. Even using the concurrent option,
// I still seemed to be getting called on the main thread.
// So this code will force a call on a different thread.
- (void)enumerateObjectsUsingBlock:(void (^)(id obj, NSUInteger idx, BOOL *stop))block
{
	NSLog(@"in override enumerateObjectsUsingBlock");
	
	NSUInteger i = 0;
	BOOL* stop_ptr;
	BOOL should_stop = NO;
	stop_ptr = &should_stop;
	
	for(id obj in realArray)
	{
		// There are several permutations I can test.
		// separate queues as serial
		// separate queues as concurrent
		// same queue as serial
		// same queue as concurrent
		// All of these seem to work in my simple test
		dispatch_queue_t background_queue;
		NSString* name = [NSString stringWithFormat:@"%@%d", @"net.playcontrol.blocksexample.backgroundqueue", i];
//		background_queue = dispatch_queue_create([name UTF8String], DISPATCH_QUEUE_SERIAL);
		background_queue = dispatch_queue_create([name UTF8String], DISPATCH_QUEUE_CONCURRENT);
//		background_queue = dispatch_queue_create("net.playcontrol.blocksexample.backgroundqueue", DISPATCH_QUEUE_SERIAL);
//		background_queue = dispatch_queue_create("net.playcontrol.blocksexample.backgroundqueue", DISPATCH_QUEUE_CONCURRENT);        

		dispatch_async(background_queue, ^(void)
		{
			block(obj, i, stop_ptr);
		}); 
		i++;
		dispatch_release(background_queue);
	}	
	NSLog(@"done override enumerateObjectsUsingBlock");
	
}

@end

/*
 @interface MyArray : NSArray
 {
 }
 - (void)enumerateObjectsUsingBlock:(void (^)(id obj, NSUInteger idx, BOOL *stop))block NS_AVAILABLE(10_6, 4_0);
 
 @end
 */
/*
 @implementation NSArray (override)
 
 - (void)enumerateObjectsUsingBlock:(void (^)(id obj, NSUInteger idx, BOOL *stop))block
 {
 NSLog(@"in override enumerateObjectsUsingBlock");
 
 dispatch_queue_t backgroundQueue;
 
 backgroundQueue = dispatch_queue_create("com.razeware.imagegrabber.bgqueue", NULL);        
 
 dispatch_async(backgroundQueue, ^(void) {
 block(self, 0, nil);
 });    
 
 NSLog(@"done override enumerateObjectsUsingBlock");
 
 }
 @end
 */
