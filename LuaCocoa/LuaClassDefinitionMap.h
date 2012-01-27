//
//  LuaClassDefinitionMap.h
//  LuaCocoa
//
//  Created by Eric Wing on 11/25/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

// Forward declaration so I don't need to #include "lua.h" here. (I don't have to worry about the search path of Lua for the public header.)
// But I have to use the formal "struct" version of the name instead of the typedef, i.e. "struct lua_State" instead of just "lua_State"
struct lua_State;

@interface LuaClassDefinitionMap : NSObject
{
	// For now, I am going to claim that it is possible to define categories or Lua classes in multiple lua states
	// (Case is that the same definition exists and is just repeated because of duplicate module imports.)
	// Hence, the key will be a pointer, but values will be an array containing lua states.
	NSMapTable* classToLuaStateMap;
}

+ (id) sharedDefinitionMap;

- (void) addLuaState:(struct lua_State*)lua_state forClass:(Class)the_class;
- (NSPointerArray*) pointerArrayOfLuaStatesForClass:(Class)the_class;
- (struct lua_State*) firstLuaStateForClass:(Class)the_class;
- (bool) isClassDefined:(Class)the_class inLuaState:(struct lua_State*)lua_state;

- (void) removeLuaStateFromMap:(struct lua_State*)lua_state;


@end
