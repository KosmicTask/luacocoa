//
//  main.m
//  LuaCocoa
//
//  Created by Eric Wing on 10/10/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#include <Foundation/Foundation.h>
#include "LuaCocoa.h"
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#import <objc/runtime.h>

@interface MyBasicObject : NSObject
{
}

+ (id) basicObject;
- (void) doSomething;
//- (NSString*) decimalSeparator;
//- (NSString*) currencyDecimalSeparator;

// Properties can test DOT_NOTATION
@property(readonly, copy) NSString* decimalSeparator;
@property(readonly, copy) NSString* currencyDecimalSeparator;

@property(readonly, assign) NSInteger someInteger;

@end

@implementation MyBasicObject

+ (id) basicObject
{
	return [[[[self class] alloc] init] autorelease];
}

- (void) dealloc
{
	NSLog(@"In MyBasicObject base dealloc %@", self);
	[super dealloc];
}

- (void) finalize
{
	NSLog(@"In MyBasicObject base finalize %@", self);
	[super finalize];
}

- (void) doSomething
{
	NSLog(@"In MyBasicObject base doSomething");
}

- (NSString*) decimalSeparator
{
	NSLog(@"In MyBasicObject base decimalSeparator");
	return @"Hello Base";
}

- (NSString*) currencyDecimalSeparator
{
	NSLog(@"In MyBasicObject base currencyDecimalSeparator");
	return @"Hello Base";
}

- (NSInteger) someInteger
{
	return 1234;
}

- (void) doSomething4withPointer:(void*)the_pointer
{
	NSLog(@"In MyBasicObject base doSomething4withPointer");
	NSString* foo = (NSString*)the_pointer;
	NSLog(@"the_pointer: %@", foo);
}


@end

// On 10.7.3, I am experiencing crashes on [autorelease_pool] drain after I call collectExhaustively (false or true).
// If I move the variable to the global space, the crashes go away.
// It seems almost like the Obj-C garbage collector is deleting the pointer incorrectly.
// This would be an Apple bug if true.
// Fortunately, this kind of usage pattern is atypical for most programs.
//#define AVOID_GARBAGE_COLLECTION_CRASH 1
#if AVOID_GARBAGE_COLLECTION_CRASH
NSAutoreleasePool* autorelease_pool = nil;
#endif

int main(int argc, char* argv[])
{
#if AVOID_GARBAGE_COLLECTION_CRASH
	autorelease_pool = [[NSAutoreleasePool alloc] init];
#else
	NSAutoreleasePool* autorelease_pool = [[NSAutoreleasePool alloc] init];
#endif

	if([NSGarbageCollector defaultCollector])
	{
		NSLog(@"Using Garbage Collection");
	}
	else
	{
		NSLog(@"Not using Garbage Collection");
	}
	
//	NSApplicationMain(argv, argv);

	LuaCocoa* luaobjc_bridge = [[LuaCocoa alloc] init];
	struct lua_State* lua_state = [luaobjc_bridge luaState];
//	struct lua_State* lua_state = luaL_newstate();
	NSString* the_path;
	int the_error;
	
	the_path = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"lua"];
	//		the_error = luaL_loadfile(luaState, [the_path fileSystemRepresentation]);
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
	lua_gc(lua_state, LUA_GCCOLLECT, 0);
	[[NSGarbageCollector defaultCollector] collectExhaustively];

	NSLog(@"stack_top: %d", lua_gettop(lua_state));
	
	SEL theSelector = @selector(transform);
	NSMethodSignature* aSignature = [CALayer instanceMethodSignatureForSelector:theSelector];
	NSLog(@"returnType: %s", [aSignature methodReturnType]);
#if 1

	NSLog(@"Creating class");

	Class new_class = NSClassFromString(@"MyLuaClass");
//	Class new_class = objc_getClass("MyLuaClass");
	NSLog(@"stack_top: %d", lua_gettop(lua_state));

	id new_instance = [new_class alloc];
	NSLog(@"passed alloc: %@", new_instance);
	NSLog(@"real class is: %s", class_getName(object_getClass(new_instance)));
	NSLog(@"stack_top: %d", lua_gettop(lua_state));

//	[new_instance doSomething2];



//	new_instance = [new_instance initWithLuaCocoaState:lua_state];
//	id new_instance = [[new_class alloc] initWithLuaCocoaState:lua_state];
	new_instance = [new_instance init];
	NSLog(@"passed init: %@", new_instance);
	NSLog(@"stack_top: %d", lua_gettop(lua_state));

	NSLog(@"setting lua_state: %x", lua_state);
	[new_instance setLuaCocoaState:lua_state];
	NSLog(@"stack_top: %d", lua_gettop(lua_state));

	NSLog(@"getting lua_state: %x", [new_instance luaCocoaState]);
	
	NSLog(@"stack_top: %d", lua_gettop(lua_state));


	NSLog(@"passed initWithLuaCocoaState: %@", [new_instance description]);
	NSLog(@"stack_top: %d", lua_gettop(lua_state));
	
	NSLog(@"real class is: %s", class_getName(object_getClass(new_instance)));
	
	[new_instance doSomething2];
	NSLog(@"stack_top: %d", lua_gettop(lua_state));

	NSString* ret_string = [new_instance doSomething3withaBool:true aDouble:2.0 anInteger:3 aString:"hello world" anId:the_path];
	NSLog(@"Ret string: %@", ret_string);
	
	[new_instance doSomething4withPointer:@"a fake pointer"];
	[new_instance release];
	new_instance = nil;
#endif
//	lua_gc(lua_state, LUA_GCCOLLECT, 0);
//	[[NSGarbageCollector defaultCollector] collectExhaustively];

	// probably a good idea to call collectExhaustively before closing the lua state due to race condition potential
//	[luaobjc_bridge collectExhaustivelyWaitUntilDone:true];
	[luaobjc_bridge release];
	luaobjc_bridge = nil;
	// Interesting race condition bug:
	// I think the lua_State can be closed (via luaobjc_bridge finalize) before a LuaCocoaProxyObject is finalized leading to a bad access to the lua_State.
	// I'm not sure how to deal with this. I suspect closing the lua_State at the latest possible time of shutting down
	// your application and not instructing the garbage
	// collector to collect will maximize your chance of not hitting this condition.
	// Alternatively, if there is a way you can guarantee all LuaCocoaProxyObjects are collected before you shutdown the lua_State,
	// then you probably will avoid this situation.
	[LuaCocoa collectExhaustivelyWaitUntilDone:false];

	[LuaCocoa purgeParseSupportCache];
	[[NSGarbageCollector defaultCollector] collectExhaustively];

	[autorelease_pool drain];
	NSLog(@"autorelease_pool: %@", autorelease_pool);
	autorelease_pool = nil;
	return 0;
}