/* NOTE: LuaCocoaProxyObject is now obsolete and will be removed. */

//
//  LuaCocoaProxyObject.m
//  LuaCocoa
//
//  Created by Eric Wing on 11/14/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "LuaCocoaProxyObject.h"
#include "lua.h"
#include "lauxlib.h"
#import "LuaSubclassBridge.h"
#import "LuaObjectBridge.h"
#include "LuaCocoaStrongTable.h"
#include "LuaCocoaWeakTable.h"
#import "LuaSelectorBridge.h"
#include "LuaCUtils.h"
#import "LuaClassDefinitionMap.h"
#import <objc/runtime.h>

@implementation LuaCocoaProxyObject

/*
- (void) createEnvironmentTableInLua
{
	// There is a strong table of key=self => object=environment_table
	// that holds all the essential per-instance data for a LuaCocoa object.
	// This environmental table entry must be removed so memory can finally be released on the lua side
	
	// First extract the lua state from the luaCocoaObject
	
}
*/

- (void) destroyEnvironmentTableInLua
{
//	NSLog(@"destroyEnvironmentTableInLua");
	// There is a strong table of key=self => object=environment_table
	// that holds all the essential per-instance data for a LuaCocoa object.
	// This environmental table entry must be removed so memory can finally be released on the lua side

	// Remember not to depend on luaCocoaObject being valid because finalize may collect things out of order.
	if(NULL != luaState)
	{
		LuaCocoaStrongTable_RemoveLuaSubclassEnvironmentTableInGlobalStrongTable(luaState, self);		
	}
}

// Don't need to call [super init] for NSProxy
- (id) initWithProxiedObject:(id)the_object
{
//	NSLog(@"LuaCocoaProxyObject:0x%x initWithProxiedObject: 0x%x", self, the_object);

//	NSLog(@"[proxy.init]\n");
	luaCocoaObject = the_object;
	if(NULL != luaState)
	{
		LuaSubclassBridge_SetLuaStateFromLuaSubclassObject(luaState, luaCocoaObject);
		LuaSubclassBridge_InitializeNewLuaObject(self, luaState);
	}

//	[luaCocoaObject retain];
//	[self createEnvironmentTableInLua];
	return self;
}

- (id) luaCocoaObject
{
	return luaCocoaObject;
}

- (void) setLuaStateForLuaCocoaProxyObject:(lua_State*)lua_state
{
	// Not sure if I should support setting lua_state to NULL
	if(NULL == lua_state)
	{
		if(NULL != luaState)
		{
			LuaCocoaStrongTable_RemoveLuaSubclassEnvironmentTableInGlobalStrongTable(luaState, self);			
		}
		LuaSubclassBridge_SetLuaStateFromLuaSubclassObject(NULL, luaCocoaObject);
		luaState = NULL;
		return;
	}
	
	bool is_class_defined_in_lua_state = [[LuaClassDefinitionMap sharedDefinitionMap] isClassDefined:[luaCocoaObject class] inLuaState:lua_state];
	if(false == is_class_defined_in_lua_state)
	{
		// This is an invalid state. I don't throw an error because my over-aggressive code is trying to find a default state.
		// Instead, grab one from the map
		lua_state = [[LuaClassDefinitionMap sharedDefinitionMap] firstLuaStateForClass:[luaCocoaObject class]];
	}

	if(nil != luaState)
	{
		if(lua_state != luaState)
		{
			// state change...evil.
			luaState = lua_state;

			if(nil != luaCocoaObject)
			{
				lua_State* old_lua_state = LuaSubclassBridge_GetLuaStateFromLuaSubclassObject(self);
				if(old_lua_state != luaState)
				{
					LuaCocoaStrongTable_RemoveLuaSubclassEnvironmentTableInGlobalStrongTable(old_lua_state, self);
				}
				// FYI: calling on the luaCocoaObject will set the ivar directly.
				// Do not pass self, or it calls back here and gets stuck in infinite recursion
				LuaSubclassBridge_SetLuaStateFromLuaSubclassObject(lua_state, luaCocoaObject);
				LuaSubclassBridge_InitializeNewLuaObject(self, lua_state);	
			}
			return;
			
		}
		else
		{
			// else, luaState is unchanged.
			// Make sure the luaCocoaObject is actually set
			lua_State* old_lua_state = LuaSubclassBridge_GetLuaStateFromLuaSubclassObject(self);
			if(old_lua_state == luaState)
			{
				return;
			}
			else
			{
				// FYI: calling on the luaCocoaObject will set the ivar directly.
				// Do not pass self, or it calls back here and gets stuck in infinite recursion
				LuaSubclassBridge_SetLuaStateFromLuaSubclassObject(lua_state, luaCocoaObject);
				LuaSubclassBridge_InitializeNewLuaObject(self, lua_state);	
			}
		}

	}
	// else, first time setting luaState, or somebody cleared it previously
	luaState = lua_state;
	if(nil != luaCocoaObject)
	{
		lua_State* old_lua_state = LuaSubclassBridge_GetLuaStateFromLuaSubclassObject(self);
		if(old_lua_state == luaState)
		{
			// don't need to do anything
			return;
		}
		else
		{
			// FYI: calling on the luaCocoaObject will set the ivar directly.
			// Do not pass self, or it calls back here and gets stuck in infinite recursion
			LuaSubclassBridge_SetLuaStateFromLuaSubclassObject(lua_state, luaCocoaObject);
			LuaSubclassBridge_InitializeNewLuaObject(self, lua_state);	
		}
	}


}

- (struct lua_State*) luaStateForLuaCocoaProxyObject
{
	return luaState;
}


- (NSUInteger) retainCount
{
	return [luaCocoaObject retainCount];
}

- (id) retain
{
	return [luaCocoaObject retain];
}

- (void) release
{
	if([luaCocoaObject retainCount]-1==0)
	{
		// NSLog(@"final release for %@", self);
		// Don't release luaCocoaObject yet. Do release in dealloc which gives me a chance to use the pointer.
//		[luaCocoaObject release];
		[self dealloc];
	}
	else
	{
		[luaCocoaObject release];
	}
}

- (id) autorelease
{
	// Not sure if I am supposed to autorelease the object or not.
	// Example from http://borkware.com/rants/agentm/collection-subclassing/
	// shows the line commented out
	//	[luaCocoaObject autorelease];
	[NSAutoreleasePool addObject:self];
	return self;
}

- (void) dealloc
{
//	NSLog(@"LuaCocoaProxyObject delloc");
	[self destroyEnvironmentTableInLua];
	[luaCocoaObject release];
	luaCocoaObject = nil;
	luaState = NULL;
	[super dealloc]; // Do I call this or not for a proxy object?
}


- (void) finalize
{
//	NSLog(@"LuaCocoaProxyObject finalize: 0x%x", self);
	[self destroyEnvironmentTableInLua];
	[super finalize]; // Do I call this or not for a proxy object?
}


- (NSZone*) the_zone
{
	return [luaCocoaObject zone];
}

// Might just consider retaining
- (id) copyWithZone:(NSZone*)the_zone
{
    LuaCocoaProxyObject* object_copy = [[LuaCocoaProxyObject allocWithZone:the_zone] initWithProxiedObject:[luaCocoaObject copyWithZone:the_zone]];
    return object_copy;
}

// Might just consider retaining
- (id) copy
{
    LuaCocoaProxyObject* object_copy = [[LuaCocoaProxyObject alloc] initWithProxiedObject:[luaCocoaObject copy]];
    return object_copy;
}


- (id) mutableCopyWithZone:(NSZone*)the_zone
{
    LuaCocoaProxyObject* object_copy = [[LuaCocoaProxyObject allocWithZone:the_zone] initWithProxiedObject:[luaCocoaObject mutableCopyWithZone:the_zone]];
    return object_copy;
}

- (id) mutableCopy
{
    LuaCocoaProxyObject* object_copy = [[LuaCocoaProxyObject alloc] initWithProxiedObject:[luaCocoaObject mutableCopy]];
    return object_copy;
}

- (NSMethodSignature*) methodSignatureForSelector:(SEL)sel
{
//	NSLog(@"[proxy.msfs] methodSignatureForSelector \"%@\"\n",NSStringFromSelector(sel));
	NSMethodSignature* sig = nil;

	
	const char* selector_name = sel_getName(sel);
	if(!strcmp("initWithLuaCocoaState:", selector_name))
	{
		sig = [NSMethodSignature signatureWithObjCTypes:"@@:^v"];
		return sig;
		
	}

//	NSLog(@"luaCocoaObject is %@", luaCocoaObject);
	sig = [luaCocoaObject methodSignatureForSelector:sel];
	if(sig) {
//		NSLog(@"[proxy.msfs] recognized by proxied_object: methodReturnType=%s\n", [sig methodReturnType]);
		return sig;
	}

	// That didn't work. Try Lua next.
	lua_State* lua_state = LuaSubclassBridge_GetLuaStateFromLuaSubclassObject(luaCocoaObject);
	if(NULL == lua_state)
	{
		NSLog(@"FIXME: Falling back to global table for lua_State");
		lua_state = [[LuaClassDefinitionMap sharedDefinitionMap] firstLuaStateForClass:[luaCocoaObject class]];
		//			object_setInstanceVariable(luaCocoaObject, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, (void*)lua_state);
		[self setLuaStateForLuaCocoaProxyObject:lua_state];
	}			

	int stack_top = lua_gettop(lua_state);
	
	LuaUserDataContainerForObject* ret_object = (LuaUserDataContainerForObject*)LuaCocoaWeakTable_GetObjectInGlobalWeakTable(lua_state, luaCocoaObject);
	if(NULL == ret_object)
	{
		ret_object = (LuaUserDataContainerForObject*)LuaCocoaStrongTable_GetObjectInGlobalStrongTable(lua_state, [luaCocoaObject class]);
	}
	const char* lua_signature = LuaSubclassBridge_FindLuaSignature(lua_state, ret_object, selector_name);
	if(NULL != lua_signature)
	{
		sig = [NSMethodSignature signatureWithObjCTypes:lua_signature];
//		NSLog(@"[proxy.msfs] found in lua methodReturnType=%s\n", [sig methodReturnType]);

		lua_settop(lua_state, stack_top); // pop the string and the container

		return sig;
	}
	lua_settop(lua_state, stack_top); // reset the stack

	sig = [NSObject methodSignatureForSelector:@selector(self)];
//	NSLog(@"[proxy.msfs] ERROR: selector not recognized, absorbing!\n");
	return sig;
}
/*
+ (IMP) instanceMethodForSelector:(SEL)the_selector
{
	NSLog(@"[proxy.msfs] instanceMethodForSelector \"%@\"\n", NSStringFromSelector(the_selector));
	
	NSMethodSignature* method_signature = nil;
	method_signature = [[luaCocoaObject class] instanceMethodForSelector:the_selector];
	if(method_signature) {
		NSLog(@"[proxy.msfs] recognized by proxied_object: methodReturnType=%s\n", [method_signature methodReturnType]);
		return method_signature;
	}
	
	method_signature = [NSObject instanceMethodForSelector:@selector(self)];
	NSLog(@"[proxy.msfs] ERROR: selector not recognized, absorbing!\n");
	return method_signature;
}
*/


- (void) invokeLuaFromInvocation:(NSInvocation*)the_invocation luaState:(lua_State*)lua_state
{
	NSMethodSignature* method_signature = [the_invocation methodSignature];
	NSUInteger number_of_arguments = [method_signature numberOfArguments];
//	NSLog(@"gettop at invokeLuaFromInvocation: %d", lua_gettop(lua_state));

	lua_checkstack(lua_state, number_of_arguments);
	// start at 2 because we know the first two arguments are the receiver and selector
	
	
	LuaObjectBridge_Pushid(lua_state, self);
	
	for(NSUInteger i=2; i<number_of_arguments; i++)
	{
		const char* argument_type = [method_signature getArgumentTypeAtIndex:i];
		switch(argument_type[0])
		{
			case _C_ID:
			{
				id the_argument = nil;
				[the_invocation getArgument:&the_argument atIndex:i];
				LuaObjectBridge_Pushid(lua_state, the_argument);
				break;
			}
				
			case _C_CLASS:
			{
				Class the_argument = nil;
				[the_invocation getArgument:&the_argument atIndex:i];
				LuaObjectBridge_PushClass(lua_state, the_argument);
				break;
			}
				
			case _C_SEL:
			{
				SEL the_argument = NULL;
				[the_invocation getArgument:&the_argument atIndex:i];
				LuaSelectorBridge_pushselector(lua_state, the_argument);
				break;
			}
			case _C_CHR:
			{
				char the_argument = 0;
				[the_invocation getArgument:&the_argument atIndex:i];
				lua_pushinteger(lua_state, (lua_Integer)(the_argument));
				break;
			}
			case _C_UCHR:
			{
				unsigned char the_argument = 0;
				[the_invocation getArgument:&the_argument atIndex:i];
				lua_pushinteger(lua_state, (lua_Integer)(the_argument));
				break;
			}
			case _C_SHT:
			{
				short the_argument = 0;
				[the_invocation getArgument:&the_argument atIndex:i];
				lua_pushinteger(lua_state, (lua_Integer)(the_argument));
				break;
			}
			case _C_USHT:
			{
				unsigned short the_argument = 0;
				[the_invocation getArgument:&the_argument atIndex:i];
				lua_pushinteger(lua_state, (lua_Integer)(the_argument));
				break;
			}
			case _C_INT:
			{
				int the_argument = 0;
				[the_invocation getArgument:&the_argument atIndex:i];
				lua_pushinteger(lua_state, (lua_Integer)(the_argument));				
				break;
			}
			case _C_UINT:
			{
				unsigned int the_argument = 0;
				[the_invocation getArgument:&the_argument atIndex:i];
				lua_pushinteger(lua_state, (lua_Integer)(the_argument));				
				break;
			}
			case _C_LNG:
			{
				long the_argument = 0;
				[the_invocation getArgument:&the_argument atIndex:i];
				lua_pushinteger(lua_state, (lua_Integer)(the_argument));				
				break;
			}
			case _C_ULNG:
			{
				unsigned long the_argument = 0;
				[the_invocation getArgument:&the_argument atIndex:i];
				lua_pushinteger(lua_state, (lua_Integer)(the_argument));				
				break;
			}
			case _C_LNG_LNG:
			{
				long long the_argument = 0;
				[the_invocation getArgument:&the_argument atIndex:i];
				lua_pushinteger(lua_state, (lua_Integer)(the_argument));				
				break;
			}
			case _C_ULNG_LNG:
			{
				unsigned long long the_argument = 0;
				[the_invocation getArgument:&the_argument atIndex:i];
				lua_pushinteger(lua_state, (lua_Integer)(the_argument));				
				break;
			}
			case _C_FLT:
			{
				float the_argument = 0.0;
				[the_invocation getArgument:&the_argument atIndex:i];
				lua_pushnumber(lua_state, (lua_Number)(the_argument));				
				break;
			}
			case _C_DBL:
			{
				double the_argument = 0.0;
				[the_invocation getArgument:&the_argument atIndex:i];
				lua_pushnumber(lua_state, (lua_Number)(the_argument));				
				break;
			}
				
			case _C_BOOL:
			{
				bool the_argument = false;
				[the_invocation getArgument:&the_argument atIndex:i];
				lua_pushboolean(lua_state, the_argument);				
				break;
			}
				
			case _C_VOID:
			{
				// no return value (probably an error if I get here)
				break;
			}
				
			case _C_PTR:
			{
				void* the_argument = nil;
				[the_invocation getArgument:&the_argument atIndex:i];
				lua_pushlightuserdata(lua_state, the_argument);
				break;
			}
				
			case _C_CHARPTR:
			{
				const char* the_argument = nil;
				[the_invocation getArgument:&the_argument atIndex:i];
				lua_pushstring(lua_state, (const char*)the_argument);
				break;
			}
				
				// compositeType check prevents reaching this case, handled in else
				/*
				 case _C_STRUCT_B:
				 {
				 
				 }
				 */
			case _C_STRUCT_B:
			case _C_ATOM:
			case _C_ARY_B:
			case _C_UNION_B:
			case _C_BFLD:
				
			default:
			{
				luaL_error(lua_state, "Unhandled/unimplemented type %s in invokeLuaFromInvocation", argument_type);
				NSLog(@"Unhandled type %s in invokeLuaFromInvocation", argument_type);
				// Probably should throw exception
			}
		}
	}
	const char* return_argument_type = [method_signature methodReturnType];
	NSUInteger number_of_return_arguments = 1;
	if(0 == return_argument_type[0] || _C_VOID == return_argument_type[0])
	{
		number_of_return_arguments = 0;
	}
//	NSLog(@"number_of_arguments: %d, number_of_return_arguments: %d", number_of_arguments, number_of_return_arguments);

//	NSLog(@"gettop before lua_call: %d", lua_gettop(lua_state));

	lua_call(lua_state, number_of_arguments-1, number_of_return_arguments);
	
//	NSLog(@"gettop after lua_call: %d", lua_gettop(lua_state));
//	NSLog(@"-1 typename: %s, %d", lua_typename(lua_state, lua_type(lua_state, -1)), lua_type(lua_state, -1));
//	NSLog(@"-2 typename: %s, %d", lua_typename(lua_state, lua_type(lua_state, -2)), lua_type(lua_state, -2));

	int stack_position_for_value = -1;
	switch(return_argument_type[0])
	{
		case _C_ID:
		{
			id return_value = (id)LuaObjectBridge_checkid(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
		case _C_CLASS:
		{
			Class return_value = (Class)LuaObjectBridge_checkid(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
		case _C_SEL:
		{
			SEL return_value = LuaSelectorBridge_checkselector(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
			
		case _C_CHR:
		{
			char return_value = (char)luaL_checkinteger(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
		case _C_UCHR:
		{
			unsigned char return_value = (char)luaL_checkinteger(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
		case _C_SHT:
		{
			short return_value = (char)luaL_checkinteger(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			
		}
		case _C_USHT:
		{
			unsigned short return_value = (char)luaL_checkinteger(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
		case _C_INT:
		{
			int return_value = (char)luaL_checkinteger(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
		case _C_UINT:
		{
			unsigned int return_value = (char)luaL_checkinteger(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
		case _C_LNG:
		{
			long return_value = (char)luaL_checkinteger(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
		case _C_ULNG:
		{
			unsigned long return_value = (char)luaL_checkinteger(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
		case _C_LNG_LNG:
		{
			long long return_value = (char)luaL_checkinteger(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
		case _C_ULNG_LNG:
		{
			unsigned long long return_value = (char)luaL_checkinteger(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
		case _C_FLT:
		{
			float return_value = (float)luaL_checknumber(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
		case _C_DBL:
		{
			double return_value = (float)luaL_checknumber(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
			
		case _C_BOOL:
		{
			_Bool return_value = (_Bool)LuaCUtils_checkboolean(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
			
		case _C_VOID:
		{
			// no value 
			break;
		}
			
		case _C_PTR:
		{
			const void* return_value = LuaCUtils_checklightuserdata(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
			
		case _C_CHARPTR:
		{
			NSLog(@"Warning: assigning Lua string to _C_CHARPTR. Not sure how to handle this...strcpy or pointer assign.");
			// strcpy seems really dangerous for overflow reasons.
			// Do pointer assign instead?
			const char* return_value = LuaCUtils_checklightuserdata(lua_state, stack_position_for_value);
			[the_invocation setReturnValue:&return_value];
			break;
		}
			
			// compositeType check prevents reaching this case, handled in else
			/*
			 case _C_STRUCT_B:
			 {
			 
			 }
			 */
		case _C_STRUCT_B:
		case _C_ATOM:
		case _C_ARY_B:
		case _C_UNION_B:
		case _C_BFLD:
			
		default:
		{
			luaL_error(lua_state, "Unhandled/unimplemented type %s in invokeLuaFromInvocation", return_argument_type);
			NSLog(@"Unhandled type %s in invokeLuaFromInvocation", return_argument_type);	
		}
	}
	
}

/*
 There are several special cases.
 init*: In alloc, I swapped the return pointer with this proxy class. I hold the pointer to the luaCocoaObject,
 but it is possible that calling init on the object returned a new/different object (i.e. NSPlaceholder).
 In this case, I want to update my pointer. I also may need to update some retain counts.
 
 Method exists only in Lua: In this case, there is no method signature. I'm not sure how to deal with this. 
 Maybe variadic parameters of all id?
 
 Method responds to selector. The method is officially registered in the runtime. It may be defined in Lua or may be a superclass.
 If it is in Lua, I need to invoke it somehow. Whether I can transparently call it or need to do it manually depends on my
 implementation. 
 (If I used ffi_prep_closure, this would be more transparent, of course if I was using ffi_prep_closure, I might forgo
 the whole Proxy approach.)
*/
- (void) forwardInvocation:(NSInvocation*)the_invocation
{
	SEL the_selector = [the_invocation selector];
//	NSLog(@"[proxy.fi] forwardInvocation \"%@\"\n",	NSStringFromSelector(the_selector));
	const char* selector_name = sel_getName(the_selector);
	
	if(!strcmp("initWithLuaCocoaState:", selector_name))
	{
		lua_State* lua_state = NULL;
		[the_invocation getArgument:&lua_state atIndex:2];
//		void* existing_lua_state = NULL;

		[self setLuaStateForLuaCocoaProxyObject:lua_state];
/*
		luaState = lua_state;

		NSLog(@"lua_state: 0x%x", lua_state);
			object_setInstanceVariable(luaCocoaObject, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, lua_state);	
*/			
		[the_invocation setSelector:@selector(init)];
		[the_invocation invokeWithTarget:luaCocoaObject];
		id return_object = nil;
		[the_invocation getReturnValue:&return_object];
		if(luaCocoaObject == return_object)
		{
			NSLog(@"init returned same object");
		}
		else
		{
			NSLog(@"init returned different object, new_object=%@", return_object);
			luaCocoaObject = return_object;
			[luaCocoaObject retain];
		}
		// For init functions, I need to return the proxy as "self", not the proxied object.
		// So I must override what NSInvocation is returning.
		[the_invocation setReturnValue:&self];
				
	}
	else
	{
		// That didn't work. Try Lua next.
		
		lua_State* lua_state = LuaSubclassBridge_GetLuaStateFromLuaSubclassObject(luaCocoaObject);
		if(NULL == lua_state)
		{
			NSLog(@"FIXME: Falling back to global table for lua_State");
			lua_state = [[LuaClassDefinitionMap sharedDefinitionMap] firstLuaStateForClass:[luaCocoaObject class]];
//			object_setInstanceVariable(luaCocoaObject, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, (void*)lua_state);
			[self setLuaStateForLuaCocoaProxyObject:lua_state];
		}			
		if(NULL == lua_state)
		{	
			NSLog(@"Failed to retrieve lua_state");
			NSLog(@"[proxy.fi] ERROR: absorbing!\n");
			return;
		}

		
		int stack_top = lua_gettop(lua_state);
//		NSLog(@"stack_top: %d", stack_top);
		LuaUserDataContainerForObject* ret_object = (LuaUserDataContainerForObject*)LuaCocoaWeakTable_GetObjectInGlobalWeakTable(lua_state, luaCocoaObject);
		lua_pop(lua_state, 1);
		if(NULL == ret_object)
		{
			ret_object = (LuaUserDataContainerForObject*)LuaCocoaStrongTable_GetObjectInGlobalStrongTable(lua_state, [luaCocoaObject class]);
			lua_pop(lua_state, 1);
		}
		Class which_class_found = NULL;
		bool is_instance_defined = false;
		bool found_lua_method = LuaSubclassBridge_FindLuaMethod(lua_state, ret_object, selector_name, &which_class_found, &is_instance_defined);
		if(true == found_lua_method)
		{
			// FIXME: Use signature to figure out argument numbers and returns
//			lua_call(lua_state, 0, 0);

			[self invokeLuaFromInvocation:the_invocation luaState:lua_state];
			lua_settop(lua_state, stack_top); // reset the stack


		}
		else if([luaCocoaObject respondsToSelector:the_selector])
		{
			lua_settop(lua_state, stack_top); // reset the stack

			//		NSLog(@"[proxy.fi] invoking with proxy\n");
			[the_invocation invokeWithTarget:luaCocoaObject];
			
			if(!strncmp(selector_name, "init", 4))
			{
				//			NSLog(@"Found init method, need to do proxy stuff");
				id return_object = nil;
				[the_invocation getReturnValue:&return_object];
				if(luaCocoaObject == return_object)
				{
					//				NSLog(@"init returned same object");
				}
				else
				{
					NSLog(@"init returned different object, new_object=%@", return_object);
					luaCocoaObject = return_object;
					[luaCocoaObject retain];
				}
				// For init functions, I need to return the proxy as "self", not the proxied object.
				// So I must override what NSInvocation is returning.
				[the_invocation setReturnValue:&self];
				
			}

			return;
		}
		else
		{
			NSLog(@"[proxy.fi] ERROR: absorbing!\n");
			lua_settop(lua_state, stack_top); // reset the stack


		}

		
		
	}
}

- (id) self
{
	return self;
}

- (Class) class
{
//	NSLog(@"[proxy.class]: %@", NSStringFromClass([luaCocoaObject class]));
	return [luaCocoaObject class];
}



-(Class) superclass
{
//	NSLog(@"[proxy.superclass]\n");
	return [luaCocoaObject superclass];
}

@end
