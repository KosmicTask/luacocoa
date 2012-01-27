//
//  LuaClassDefinitionMap.m
//  LuaCocoa
//
//  Created by Eric Wing on 11/25/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "LuaClassDefinitionMap.h"
#include "lua.h"

static LuaClassDefinitionMap* s_luaClassDefinitionMap = nil;

@implementation LuaClassDefinitionMap

+ (id) sharedDefinitionMap
{
	@synchronized(self)
	{
		if(nil == s_luaClassDefinitionMap)
		{
			s_luaClassDefinitionMap = [[LuaClassDefinitionMap alloc] init];
		}
	}
	return s_luaClassDefinitionMap;
}

- (id) init
{
	self = [super init];
	if(nil != self)
	{
		// I don't think classes ever get collected, but we also don't want them to be retained
		// We want the map to retain the pointer arrays
		classToLuaStateMap = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsOpaqueMemory|NSPointerFunctionsOpaquePersonality valueOptions:NSPointerFunctionsStrongMemory capacity:16];

//		classToLuaStateMap = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void) dealloc
{
	[classToLuaStateMap release];
	[super dealloc];
}

- (void) addLuaState:(lua_State*)lua_state forClass:(Class)the_class
{
	if(NULL == lua_state || NULL == the_class)
	{
		return;
	}
	// First: find out if an array already exists for this key
	NSPointerArray* list_of_lua_states = [classToLuaStateMap objectForKey:the_class];
	if(nil == list_of_lua_states)
	{
		// We need to create a new pointer array to hold the new lua state.
		list_of_lua_states = [[[NSPointerArray alloc] initWithOptions:NSPointerFunctionsOpaqueMemory|NSPointerFunctionsOpaquePersonality] autorelease];
		[list_of_lua_states addPointer:lua_state];
		[classToLuaStateMap setObject:list_of_lua_states forKey:the_class];

	}
	else
	{
		// Make sure the lua_state is not already in the list
		bool already_in_list = false;
		NSUInteger number_of_array_elements = [list_of_lua_states count];

		for(NSUInteger i = 0; i < number_of_array_elements; i++)
		{
			if([list_of_lua_states pointerAtIndex:i] == lua_state)
			{
				already_in_list = true;
				break;
			}
		}
		if(false == already_in_list)
		{
			// Add the lua state to the list
			[list_of_lua_states addPointer:lua_state];
		}
	}
}


- (NSPointerArray*) pointerArrayOfLuaStatesForClass:(Class)the_class
{
	if(NULL == the_class)
	{
		return nil;
	}
	return [classToLuaStateMap objectForKey:the_class];
}

- (lua_State*) firstLuaStateForClass:(Class)the_class
{
	if(NULL == the_class)
	{
		return NULL;
	}
	NSPointerArray* list_of_lua_states = [classToLuaStateMap objectForKey:the_class];
	if(nil != list_of_lua_states)
	{
		return [list_of_lua_states pointerAtIndex:0];
	}
	else
	{
		return NULL;
	}
}

- (bool) isClassDefined:(Class)the_class inLuaState:(lua_State*)lua_state
{
	if(NULL == the_class)
	{
		return false;
	}
	NSPointerArray* list_of_lua_states = [self pointerArrayOfLuaStatesForClass:the_class];
	if(nil == list_of_lua_states)
	{
		return false;
	}
	NSUInteger number_of_array_elements = [list_of_lua_states count];
	
	for(NSUInteger i = 0; i < number_of_array_elements; i++)
	{
		if([list_of_lua_states pointerAtIndex:i] == lua_state)
		{
			return true;
		}
	}
	return false;
}

// I don't expect this to be useful since there is no way to unregister a class from Objective-C
- (void) removeLuaStateFromMap:(lua_State*)lua_state
{
	for(Class current_class in classToLuaStateMap)
	{
		NSPointerArray* list_of_lua_states = [classToLuaStateMap objectForKey:current_class];
		NSUInteger number_of_array_elements = [list_of_lua_states count];
		for(NSUInteger i = number_of_array_elements; i != 0; i--)
		{
			if([list_of_lua_states pointerAtIndex:i-1] == lua_state)
			{
				[list_of_lua_states removePointerAtIndex:i-1];
			}
		}
	}
}

@end
