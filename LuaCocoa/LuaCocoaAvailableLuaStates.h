//
//  LuaCocoaAvailableLuaStates.h
//  LuaCocoa
//
//  Created by Eric Wing on 2/28/12.
//  Copyright (c) 2012 PlayControl Software, LLC. All rights reserved.
//


#ifndef _LUACOCOA_AVAILABLELUASTATES_H
#define _LUACOCOA_AVAILABLELUASTATES_H


#import <Foundation/Foundation.h>

struct lua_State;

// Keep track of Lua states that are available.
// This is intended to guard against asynchronous block callbacks from invoking dead Lua states.
// This may have other uses (e.g. regular function pointer callbacks). 
// (Subclass bridge has a different mechanism for tracking because of the single class definition and multiple Lua states problem.)
@interface LuaCocoaAvailableLuaStates : NSObject
{
	NSHashTable* luaStatesTable;
}

+ (id) sharedAvailableLuaStates;

- (void) addLuaState:(struct lua_State*)lua_state;
- (_Bool) containsLuaState:(struct lua_State*)lua_state;
- (void) removeLuaState:(struct lua_State*)lua_state;
- (void) removeAllStates;


@end

#endif /* _LUACOCOA_AVAILABLELUASTATES_H */