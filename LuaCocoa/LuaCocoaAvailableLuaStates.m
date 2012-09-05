//
//  LuaCocoaAvailableLuaStatesSet.m
//  LuaCocoa
//
//  Created by Eric Wing on 2/28/12.
//  Copyright (c) 2012 PlayControl Software, LLC. All rights reserved.
//

#import "LuaCocoaAvailableLuaStates.h"
#include "lua.h"

static LuaCocoaAvailableLuaStates* s_luaCocoaAvailableLuaStates = nil;

@implementation LuaCocoaAvailableLuaStates

+ (id) sharedAvailableLuaStates
{
	@synchronized(self)
	{
		if(nil == s_luaCocoaAvailableLuaStates)
		{
			s_luaCocoaAvailableLuaStates = [[LuaCocoaAvailableLuaStates alloc] init];
		}
	}
	return s_luaCocoaAvailableLuaStates;
}

- (id) init
{
	self = [super init];
	if(nil != self)
	{
		// The documentation doesn't list NSPointerFunctionsOpaquePersonality as a supported option,
		// but the others don't seem correct (crash) for void* pointers.
		// The documentation implicitly says void* pointers are allowed through the C-API functions.
		// But the C creation function seems to be marked 'legacy'. 
		// I am under the impression that this is the correct way to do this.
		// This seems to work so far for me (10.7). 
		// If this is a problem, I might need to use NSSet and wrap pointers in NSValue.
		luaStatesTable = [[NSHashTable alloc] initWithOptions:NSPointerFunctionsOpaquePersonality capacity:0];
	}
	return self;
}

- (void) dealloc
{
	[luaStatesTable release];
	[super dealloc];
}


- (void) addLuaState:(struct lua_State*)lua_state
{
	NSHashInsert(luaStatesTable, lua_state);
}

- (_Bool) containsLuaState:(struct lua_State*)lua_state
{
	void* ret_val = NSHashGet(luaStatesTable, lua_state);
	if(NULL == ret_val)
	{
		return false;
	}
	else
	{
		return true;
	}
}

- (void) removeLuaState:(struct lua_State*)lua_state
{
	NSHashRemove(luaStatesTable, lua_state);

}

- (void) removeAllStates
{
//	[luaStatesTable removeAllObjects];
	NSResetHashTable(luaStatesTable);
}

@end
