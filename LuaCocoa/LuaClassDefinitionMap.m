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
		classToSelectorMap = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsOpaquePersonality valueOptions:NSMapTableStrongMemory capacity:0];
		
		// optimized reverse mapping to help removal and is defined checks
		luaToClassToSelectorMap = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsOpaquePersonality valueOptions:NSMapTableStrongMemory capacity:0];

	}
	return self;
}

- (void) dealloc
{
	// I think I can just delete the top level objects and don't need to iterate through each.
	[luaToClassToSelectorMap release];
	[classToSelectorMap release];
	
	[super dealloc];
}

- (void) addLuaState:(lua_State*)lua_state forClass:(Class)the_class forSelector:(SEL)the_selector
{
	// Should I allow NULL selectors to be a key?
	// This would allow for CreateClass which has no selector.
	if(NULL == lua_state || NULL == the_class || NULL == the_selector)
	{
		return;
	}
	
	// The documentation doesn't list NSPointerFunctionsOpaquePersonality as a supported option,
	// but the others don't seem correct (crash) for void* pointers.
	// The documentation implicitly says void* pointers are allowed through the C-API functions.
	// But the C creation function seems to be marked 'legacy'. 
	// I am under the impression that this is the correct way to do this.
	// This seems to work so far for me (10.7). 
	// If this is a problem, I might need to use NSSet and wrap pointers in NSValue.

	
	// Does this mapping already exist?
	NSMapTable* selector_map = (NSMapTable*)NSMapGet(classToSelectorMap, the_class);
	if(nil == selector_map)
	{
		// There is no map which means this is a new entry and we need to allocate a new map
		selector_map = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsOpaquePersonality valueOptions:NSMapTableStrongMemory capacity:0];
		NSMapInsert(classToSelectorMap, the_class, selector_map);
		[selector_map release];
	}
	
	// Does this mapping already exist?
	NSHashTable* lua_set = (NSHashTable*)NSMapGet(selector_map, the_selector);
	if(nil == lua_set)
	{
		// There is no map which means this is a new entry and we need to allocate a new map
		lua_set = [[NSHashTable alloc] initWithOptions:NSPointerFunctionsOpaquePersonality capacity:0];
		NSMapInsert(selector_map, the_selector, lua_set);
		[lua_set release];
	}
	
	// Can just insert the pointer since we don't have to allocate any data structures unlike above
	NSHashInsert(lua_set, lua_state);


	// Add lua reverse mapping to help optimize reverse searches for existence and removal
	NSMapInsert(luaToClassToSelectorMap, lua_state, selector_map);
}

- (lua_State*) anyLuaStateForSelector:(SEL)the_selector inClass:(Class)the_class
{
	NSMapTable* selector_map = (NSMapTable*)NSMapGet(classToSelectorMap, the_class);
	if(nil != selector_map)
	{
		NSHashTable* lua_set = (NSHashTable*)NSMapGet(selector_map, the_selector);
		if(nil != lua_set)
		{
			if(NSCountHashTable(lua_set) > 0)
			{
				// Drat, there doesn't seem to be an anyObject in the C-API and I don't trust the Obj-C API for pointer types.
				NSHashEnumerator enumerator = NSEnumerateHashTable(lua_set);
				return (lua_State*)NSNextHashEnumeratorItem(&enumerator);
			}
		}
	}
	return NULL;
}

- (bool) isSelectorDefined:(SEL)the_selector inClass:(Class)the_class inLuaState:(lua_State*)lua_state
{
	NSMapTable* selector_map = (NSMapTable*)NSMapGet(classToSelectorMap, the_class);
	if(nil != selector_map)
	{
		NSHashTable* lua_set = (NSHashTable*)NSMapGet(selector_map, the_selector);
		if(nil != lua_set)
		{
			return (bool)NSHashGet(lua_set, lua_state);
		}
	}
	return false;
}


// Originally, I didn't think this would be useful, but it turns out it is important because of relaunching scenarios
// like in HybridCoreAnimationScriptability. The OS's memory allocator may recycle memory addresses so there is a possibility
// I get the same pointer back which causes assertion errors elsewhere in the code. So removing dead lua states from the map is important.
- (void) removeLuaStateFromMap:(lua_State*)lua_state
{
	NSMapTable* selector_map = (NSMapTable*)NSMapGet(luaToClassToSelectorMap, lua_state);
	if(nil != selector_map)
	{
		// Iterate through all selectors
		NSMapEnumerator selector_map_enumerator = NSEnumerateMapTable(selector_map);
//		SEL current_selector_key;
		void* current_selector_key;
		NSHashTable* current_luaset_value;
		while(YES==NSNextMapEnumeratorPair(&selector_map_enumerator, &current_selector_key, (void*)&current_luaset_value))
		{
			
			NSHashRemove(current_luaset_value, lua_state);
		}

	}
	
	NSMapRemove(luaToClassToSelectorMap, lua_state);
	
}

@end
