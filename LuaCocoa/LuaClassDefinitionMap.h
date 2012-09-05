//
//  LuaClassDefinitionMap.h
//  LuaCocoa
//
//  Created by Eric Wing on 11/25/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//
#ifndef _LUACOCOA_CLASSDEFINITIONMAP_H
#define _LUACOCOA_CLASSDEFINITIONMAP_H


#import <Foundation/Foundation.h>

// Forward declaration so I don't need to #include "lua.h" here. (I don't have to worry about the search path of Lua for the public header.)
// But I have to use the formal "struct" version of the name instead of the typedef, i.e. "struct lua_State" instead of just "lua_State"
struct lua_State;

@interface LuaClassDefinitionMap : NSObject
{
	// For now, I am going to claim that it is possible to define categories or Lua classes in multiple lua states
	// (Case is that the same definition exists and is just repeated because of duplicate module imports.)
	
	// map[class][selector] = { set of lua_States }
	NSMapTable* classToSelectorMap;

	// for partial reverse mapping
	NSMapTable* luaToClassToSelectorMap;
}

+ (id) sharedDefinitionMap;

//- (void) addLuaState:(struct lua_State*)lua_state forClass:(Class)the_class;
- (void) addLuaState:(struct lua_State*)lua_state forClass:(Class)the_class forSelector:(SEL)the_selector;

- (struct lua_State*) anyLuaStateForSelector:(SEL)the_selector inClass:(Class)the_class;

- (bool) isSelectorDefined:(SEL)the_selector inClass:(Class)the_class inLuaState:(struct lua_State*)lua_state;

- (void) removeLuaStateFromMap:(struct lua_State*)lua_state;


@end

#endif /* _LUACOCOA_CLASSDEFINITIONMAP_H */