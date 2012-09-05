//
//  LuaSubclassBridge.m
//  LuaCocoa
//
//  Created by Eric Wing on 11/13/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//
#define MACOSX  // for fficonfig.h on Darwin

#import "LuaSubclassBridge.h"
#include <objc/objc.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <Foundation/Foundation.h>
#include "LuaObjectBridge.h"
#include "lua.h"
#include "lauxlib.h"
//#import "LuaCocoaProxyObject.h"
#include "LuaCocoaStrongTable.h"
#import "ObjectSupport.h"
#import "LuaClassDefinitionMap.h"
#include "LuaCocoaWeakTable.h"
#include <ffi/ffi.h>
#include <sys/mman.h>   // for mmap()

#include "LuaFFIClosure.h"
#import "ParseSupportMethod.h"
#import "ParseSupportStruct.h"
#include "LuaFFISupport.h"
#include "LuaSelectorBridge.h"
#include "LuaStructBridge.h"
#include "LuaObjectBridge.h"
#include "LuaBlockBridge.h" // used for common return-value/out argument implementation
#import "ObjCRuntimeSupport.h"
#import "LuaObjectBridge.h"

//const char* LUACOCOA_SUBCLASS_METATABLE_ID = "LuaCocoa.Subclass";


//typedef struct LuaSubClassBridge_LuaClassProxy
//{
//	Class objcClassPtr; // backpointer to class registered in Objective-C	
//} LuaSubClassBridge_LuaClassProxy;



#define LUA_SUBCLASS_BRIDGE_IVAR_FOR_ORIGIN_THREAD "luaCocoaOriginThreadWithHardToClashName"

static NSThread* LuaSubclassBridge_GetOriginThreadFromLuaSubclassObject(id the_object);
static void LuaSubclassBridge_SetOriginThreadFromLuaSubclassObject(NSThread* origin_thread, id the_object);

static void LuaSubclassBridge_InvokeDeallocFinalizeClosureCallback(id self_arg, SEL selector_arg, Class class_type, lua_State* lua_state, LuaFFIClosureUserDataContainer* closure_user_data);


// These hold ivars needed to deal with the finalize on the origin thread.
// These are raw pointers that do not retain in order to avoid resurrection issues.
@interface LuaCocoaSubclassDataForThreadDellocFinalize : NSObject
{
@private
	void* selfArg; // declaring as void* to avoid resurrection issues with garbage collector
	SEL selectorArg;
	Class classType;
	lua_State* luaState;
	LuaFFIClosureUserDataContainer* closureUserData;	
}
- (id) initWithSelfArg:(id)self_arg 
	selectorArg:(SEL)selector_arg
	classType:(Class)class_type
	luaState:(lua_State*)lua_state
	closureUserData:(LuaFFIClosureUserDataContainer*)closure_user_data
;

@end

@implementation LuaCocoaSubclassDataForThreadDellocFinalize

- (id) initWithSelfArg:(id)self_arg 
	selectorArg:(SEL)selector_arg
	classType:(Class)class_type
	luaState:(lua_State*)lua_state
	closureUserData:(LuaFFIClosureUserDataContainer*)closure_user_data
{
	self = [super init];
	if(nil != self)
	{
		selfArg = self_arg;
		selectorArg = selector_arg;
		classType = class_type;
		luaState = lua_state;
		closureUserData = closure_user_data;
	}
	return self;
}

// Callback for performSelector:onThread:
- (void) invokeCleanup:(id)the_object
{
	LuaSubclassBridge_InvokeDeallocFinalizeClosureCallback(selfArg, selectorArg, classType, luaState, closureUserData);
}

@end


static void LuaSubclassBridge_internalSetLuaStateFromLuaSubclassObject(lua_State* lua_state, id the_object)
{
	object_setInstanceVariable(the_object, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, lua_state);		
}

// Return: Table is on top of the stack.
// Note: This isn't really an environment table until lua_setfenv() is called on the userdata holding the LuaSubclass object
static void LuaSubclassBridge_CreateNewLuaSubclassEnvironmentTable(lua_State* lua_state)
{
	// I want a clean environment table
	// Make the new table the new environment table
	// setfenv pops
	lua_newtable(lua_state); // create new table for environment table
	
	lua_newtable(lua_state); // create new table for methods table
	lua_setfield(lua_state, -2, "__methods"); // environment_table["__methods"] = new_table
	
	lua_newtable(lua_state); // create new table for method signature table
	lua_setfield(lua_state, -2, "__signatures"); // environment_table["__signatures"] = new_table
	
	lua_newtable(lua_state); // create new table for ivars table
	lua_setfield(lua_state, -2, "__ivars"); // environment_table["__ivars"] = new_table
	
	lua_newtable(lua_state); // create new table for ivars table
	lua_setfield(lua_state, -2, "__fficlosures"); // environment_table["__ivars"] = new_table
	
//	lua_setfenv(lua_state, -2); // set the new table as the environment table
	
}

void LuaSubclassBridge_InitializeNewLuaObject(id the_object, lua_State* lua_state)
{

/*
	// Check to make sure that the values don't already exist.
	// (Might be relevant for a subclass of a Lua class.)
	void* existing_lua_state = NULL;
	object_getInstanceVariable(the_object, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, &existing_lua_state);
	if(NULL == existing_lua_state)
	{
		NSLog(@"LuaSubclassBridge_InitializeNewLuaObject: Setting luaState");
		object_setInstanceVariable(the_object, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, lua_state);		
		
		// We need to create an environmental table for the object in Lua which will hold the Lua specifc data.
		// This will be held in a strong global table.
		// When the object is dealloc'd/finalized, it will be responsible for cleaning this entry.
		bool table_already_exists = LuaCocoaStrongTable_GetLuaSubclassEnvironmentTableInGlobalStrongTable(lua_state, the_object);
		// I'm not expecting the table to already exist.
		if(table_already_exists)
		{
			NSLog(@"Assertion failure: Environment table for this object already exists...maybe it was created in super?");
			lua_pop(lua_state, 1); // pop the return value of LuaCocoaStrongTable_GetLuaSubclassEnvironmentTableInGlobalStrongTable
			return;
		}
		lua_pop(lua_state, 1); // pop the return value of LuaCocoaStrongTable_GetLuaSubclassEnvironmentTableInGlobalStrongTable

		// Creates a new table and leaves it on the stack
		NSLog(@"creating new environment table");
		LuaSubclassBridge_CreateNewLuaSubclassEnvironmentTable(lua_state);
		// Add the table to the global strong table
		LuaCocoaStrongTable_InsertLuaSubclassEnvironmentTableInGlobalStrongTable(lua_state, -1, the_object);

		// Pop the new table now that it stored in the global table
		lua_pop(lua_state, 1);		
	}
*/

	// Do I really need this check?
	if(!LuaSubclassBridge_IsObjectSubclassInLua(the_object))
	{
		NSLog(@"FIXME in LuaSubclassBridge_InitializeNewLuaObject: Expecting a subclass written in Lua. Bailing");
		return;
	}
	
	// I changed the class definition map to be per-selector to deal with categories. 
	// Since this is initialization, I just need to know if a Lua state exists for this class.
	// I use 'alloc' as a placeholder for this case.
	if(![[LuaClassDefinitionMap sharedDefinitionMap] isSelectorDefined:@selector(alloc) inClass:[the_object class] inLuaState:lua_state])
	{
		// This is an invalid Lua state, so I'm going to grab a different one
		lua_state = [[LuaClassDefinitionMap sharedDefinitionMap] anyLuaStateForSelector:@selector(alloc) inClass:[the_object class]];
	}

//	[the_object setLuaStateForLuaCocoaProxyObject:lua_state];
//	LuaSubclassBridge_SetLuaStateFromLuaSubclassObject(lua_state, the_object);
	// need to avoid infinite recursion
	LuaSubclassBridge_internalSetLuaStateFromLuaSubclassObject(lua_state, the_object);
	
	// I'm concerned about finalizers not being called on the origin thread. So I'm saving the current thread.
	LuaSubclassBridge_SetOriginThreadFromLuaSubclassObject([NSThread currentThread], the_object);
	
	// We need to create an environmental table for the object in Lua which will hold the Lua specifc data.
	// This will be held in a strong global table.
	// When the object is dealloc'd/finalized, it will be responsible for cleaning this entry.
	bool table_already_exists = LuaCocoaStrongTable_GetLuaSubclassEnvironmentTableInGlobalStrongTable(lua_state, the_object);
	// I'm not expecting the table to already exist.
	if(table_already_exists)
	{
		if (NO) {
			NSLog(@"(Backing off...new changes make this much easier to hit... (Old warning: Assertion failure: Environment table for this object already exists...maybe it was created in super?)");
		}
		lua_pop(lua_state, 1); // pop the return value of LuaCocoaStrongTable_GetLuaSubclassEnvironmentTableInGlobalStrongTable
		return;
	}
	lua_pop(lua_state, 1); // pop the return value of LuaCocoaStrongTable_GetLuaSubclassEnvironmentTableInGlobalStrongTable
		
	// Creates a new table and leaves it on the stack
//	NSLog(@"creating new environment table");
	LuaSubclassBridge_CreateNewLuaSubclassEnvironmentTable(lua_state);
	// Add the table to the global strong table
/*
	if(lua_istable(lua_state, -1))
	{
		NSLog(@"verified table");
	}
	else
	{
		NSLog(@"not table:BAD");
	}
*/
	LuaCocoaStrongTable_InsertLuaSubclassEnvironmentTableInGlobalStrongTable(lua_state, -1, the_object);
	
	// Pop the new table now that it stored in the global table
	lua_pop(lua_state, 1);		
}
/*
static id LuaSubclassBridge_alloc(Class self, SEL _cmd)
{
	NSLog(@"self:%@, _cmd:%@", self, NSStringFromSelector(_cmd));
	NSLog(@"self_class is %s", object_getClassName(self));

	Class parent_class = class_getSuperclass(self);

	NSLog(@"parent_class is %s", object_getClassName(parent_class));

	Class current_class = self;
	NSLog(@"current_class is %s", object_getClassName(current_class));

	bool is_lua_subclass = true;
	while(is_lua_subclass)
	{
		is_lua_subclass = class_getInstanceMethod(current_class, @selector(initWithLuaCocoaState:));
		if(true == is_lua_subclass)
		{
			current_class = class_getSuperclass(current_class);
		}
		else
		{
			is_lua_subclass = false;
			parent_class = current_class;
		}

	}
	
	NSLog(@"parent_class is %s", object_getClassName(parent_class));
//	struct objc_super super_data = { self, parent_class };
	struct objc_super super_data = { self, parent_class->isa };
	self = objc_msgSendSuper(&super_data, @selector(alloc));
//	self = objc_msgSend(parent_class, @selector(alloc));
	if(nil != self)
	{
		NSLog(@"adding luaState (if I can)");
	}
//	return self;
	LuaCocoaProxyObject* proxy_container = [[LuaCocoaProxyObject alloc] initWithProxiedObject:self];
//	[self release]; // want to release since the proxy is holding it now
	
	return proxy_container;
}
*/
static id LuaSubclassBridge_allocWithZone(Class self, SEL _cmd, NSZone* the_zone)
{
	if (NO) NSLog(@"self:%@, _cmd:%@", self, NSStringFromSelector(_cmd));
	
	Class parent_class = class_getSuperclass(self);
	Class current_class = object_getClass(self);
#pragma unused(current_class)	
/* // FIXME: No more initWithLuaCocoaState:
	bool is_lua_subclass = true;
	while(is_lua_subclass)
	{
		is_lua_subclass = class_getInstanceMethod(current_class, @selector(initWithLuaCocoaState:));
		if(true == is_lua_subclass)
		{
			current_class = class_getSuperclass(current_class);
		}
		else
		{
			is_lua_subclass = false;
			parent_class = current_class;
		}
		
	}
*/	
	if (NO) NSLog(@"parent_class is %s", object_getClassName(parent_class));
//	struct objc_super super_data = { self, parent_class };
	struct objc_super super_data = { self, parent_class->isa };

	self = objc_msgSendSuper(&super_data, @selector(allocWithZone:), the_zone);
	if(nil != self)
	{
//		NSLog(@"adding luaState (if I can)");
	}
	return self;
}
/*
static id LuaSubclassBridge_init(id self, SEL _cmd)
{
	NSLog(@"self:%@, _cmd:%@", self, NSStringFromSelector(_cmd));
	NSLog(@"self_class is %s", object_getClassName(self));

	Class parent_class = class_getSuperclass(object_getClass(self));
	NSLog(@"parent_class is %s", object_getClassName(parent_class));
	struct objc_super super_data = { self, parent_class };
	self = objc_msgSendSuper(&super_data, @selector(init));
	if(nil != self)
	{
		NSLog(@"adding luaState (if I can)");
	}
	return self;
//	LuaCocoaProxyObject* proxy_container = [[LuaCocoaProxyObject alloc] initWithProxiedObject:self];
//	[self release]; // want to release since the proxy is holding it now
	
//	return proxy_container;
}

id LuaSubclassBridge_initWithLuaCocoaState(id self, SEL _cmd, lua_State* lua_state)
{
	NSLog(@"self:%@, _cmd:%@", self, NSStringFromSelector(_cmd));
	
	self = LuaSubclassBridge_init(self, _cmd);
//	self = [self init];
	
	//	lua_State* existing_lua_state = NULL;
	//	object_getInstanceVariable(self, "luaState", &existing_lua_state);
	//	if(NULL == existing_lua_state)
	//	{
	LuaSubclassBridge_InitializeNewLuaObject(self, lua_state);		
	//	}
	return self;
}
*/


// Lots of assumptions in this function
// 1) Lua subclassed object is on top of stack
// 2) Retain count on Lua subclassed object is 1 via alloc/init (for GC, not relevant)
// 3) This is run before
/*
bool LuaSubclassBridge_InitializeNewLuaObjectIfSubclassInLua(LuaUserDataContainerForObject* the_container, lua_State* lua_state)
{
	id the_object = the_container->theObject;
#if 0
	void* existing_lua_state = NULL;
	
	object_getInstanceVariable(the_object, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, &existing_lua_state);
	if(NULL == existing_lua_state)
	{
		NSLog(@"LuaSubclassBridge_InitializeNewLuaObject: Setting luaState");
		object_setInstanceVariable(the_object, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, lua_state);		
	}
#else
	bool is_lua_subclass = class_getInstanceMethod(object_getClass(the_object), @selector(initWithLuaCocoaState:));
	if(true == is_lua_subclass)
	{
		the_container->isLuaSubclass = true;
		LuaSubclassBridge_InitializeNewLuaObject(the_object, lua_state);
	}
	return is_lua_subclass;
#endif
}
*/
bool LuaSubclassBridge_IsClassSubclassInLua(Class the_class)
{
	Ivar the_ivar = class_getInstanceVariable(the_class, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER);
	if(NULL != the_ivar)
	{
		return true;
	}
	else
	{
		return false;
	}
}

bool LuaSubclassBridge_IsObjectSubclassInLua(id the_object)
{
	lua_State* lua_state = NULL;
	Ivar the_ivar = object_getInstanceVariable(the_object, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, (void**)&lua_state);
	if(NULL != the_ivar)
	{
		return true;
	}
	else
	{
		return false;
	}
}

// Lots of assumptions in this function
// 1) Lua subclassed object is on top of stack
// 2) Retain count on Lua subclassed object is 1 via alloc/init (for GC, not relevant)
// 3) This is run before
bool LuaSubclassBridge_InitializeNewLuaObjectIfSubclassInLua(id the_object, lua_State* lua_state)
{
	bool is_lua_subclass = LuaSubclassBridge_IsObjectSubclassInLua(the_object);
	if(true == is_lua_subclass)
	{
		LuaSubclassBridge_InitializeNewLuaObject(the_object, lua_state);
	}
	return is_lua_subclass;
}

/*
static void LuaSubclassBridge_dealloc(id self, SEL _cmd)
{
	NSLog(@"self:%@, _cmd:%@", self, NSStringFromSelector(_cmd));
	
	Class parent_class = class_getSuperclass(object_getClass(self));
	struct objc_super super_data = { self, parent_class };
	objc_msgSendSuper(&super_data, @selector(dealloc));	
}

static void LuaSubclassBridge_finalize(id self, SEL _cmd)
{
	NSLog(@"self:%@, _cmd:%@", self, NSStringFromSelector(_cmd));
	
	Class parent_class = class_getSuperclass(object_getClass(self));
	struct objc_super super_data = { self, parent_class };
	objc_msgSendSuper(&super_data, @selector(finalize));	
}


static void LuaSubclassBridge_forwardInvocation(id self, SEL _cmd, NSInvocation* the_invocation)
{
	NSLog(@"self:%@, _cmd:%@, the_invocation:%@", self, NSStringFromSelector(_cmd), the_invocation);

	NSLog(@"the selector: %@", NSStringFromSelector([the_invocation selector]));
}

static NSMethodSignature* LuaSubclassBridge_methodSignatureForSelector(id self, SEL _cmd, SEL the_selector) 
{
	NSLog(@"self:%@, _cmd:%@, the_selector:%@", self, NSStringFromSelector(_cmd), NSStringFromSelector(the_selector));
	return nil;
}
*/

NSThread* LuaSubclassBridge_GetOriginThreadFromLuaSubclassObject(id the_object)
{
	NSThread* origin_thread = NULL;
	object_getInstanceVariable(the_object, LUA_SUBCLASS_BRIDGE_IVAR_FOR_ORIGIN_THREAD, (void**)&origin_thread);
	return origin_thread;
}


void LuaSubclassBridge_SetOriginThreadFromLuaSubclassObject(NSThread* origin_thread, id the_object)
{
	NSThread* old_origin_thread = LuaSubclassBridge_GetOriginThreadFromLuaSubclassObject(the_object);
	if([origin_thread isEqualTo:old_origin_thread])
	{
		return;
	}
	if(nil != old_origin_thread)
	{
		CFRelease(old_origin_thread);
	}
	object_setInstanceVariable(the_object, LUA_SUBCLASS_BRIDGE_IVAR_FOR_ORIGIN_THREAD, origin_thread);
	if(nil != origin_thread)
	{
		CFRetain(origin_thread);
	}
}



lua_State* LuaSubclassBridge_GetLuaStateFromLuaSubclassObject(id the_object)
{
	lua_State* lua_state = NULL;
	object_getInstanceVariable(the_object, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, (void**)&lua_state);
	return lua_state;
}


void LuaSubclassBridge_SetLuaStateFromLuaSubclassObject(lua_State* lua_state, id the_object)
{
	LuaSubclassBridge_internalSetLuaStateFromLuaSubclassObject(lua_state, the_object);
//	object_setInstanceVariable(the_object, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, lua_state);		
	LuaSubclassBridge_InitializeNewLuaObject(the_object, lua_state);
}

static void LuaSubclassBridge_setLuaCocoaState(id self, SEL _cmd, lua_State* lua_state) 
{
	if (NO) NSLog(@"self:%@, _cmd:%@", self, NSStringFromSelector(_cmd));
	LuaSubclassBridge_internalSetLuaStateFromLuaSubclassObject(lua_state, self);
	//	object_setInstanceVariable(self, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, lua_state);
	// HACK: I assume this must be called as initialization. 
	// So this is my chance to put the object in the global strong table.
	LuaSubclassBridge_InitializeNewLuaObject(self, lua_state);
}

static lua_State* LuaSubclassBridge_luaCocoaState(id self, SEL _cmd) 
{
	if (NO) NSLog(@"self:%@, _cmd:%@", self, NSStringFromSelector(_cmd));
	//	lua_State* lua_state = NULL;
	return LuaSubclassBridge_GetLuaStateFromLuaSubclassObject(self);
//	void* lua_state = NULL;
//	object_getInstanceVariable(self, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, &lua_state);
//	return (lua_State*)lua_state;
}


// Not named "init" because init may trigger the InvokeMethod special handling code for "init"
// Disabled because on second thought, this might not be useful since you need the lua state.
// For now, setLuaCocoaState will trigger this setup code too so this is not needed.
/*
static void LuaSubclassBridge_setupLuaCocoaInstance(id self, SEL _cmd) 
{
	NSLog(@"self:%@, _cmd:%@", self, NSStringFromSelector(_cmd));
	void* lua_state = NULL;
	object_getInstanceVariable(self, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, &lua_state);
	if(NULL == lua_state)
	{
		NSLog(@"Assertion Failure: This method has no effect unless a lua_State has already been set");
	}
	LuaSubclassBridge_InitializeNewLuaObject(self, lua_state);
}


*/

// This one might be more useful. Might want to activate.
// Uses would include people needing to subclass dealloc/finalize
static void LuaSubclassBridge_cleanupLuaCocoaInstance(id self, SEL _cmd) 
{
	if (NO) NSLog(@"self:%@, _cmd:%@", self, NSStringFromSelector(_cmd));
	
	lua_State* lua_state = LuaSubclassBridge_GetLuaStateFromLuaSubclassObject(self);
	if(NULL != lua_state)
	{
		// I need to guard against cases where the Lua state has already been closed.
		// This is particularly a problem with Obj-C garbage collection where finalize may be invoked some time later.
		if([[LuaClassDefinitionMap sharedDefinitionMap] isSelectorDefined:_cmd inClass:[self class] inLuaState:lua_state])
		{
			LuaCocoaStrongTable_RemoveLuaSubclassEnvironmentTableInGlobalStrongTable(lua_state, self);		
		}
	}
	else
	{
		NSLog(@"Warning/AssertionFailure: dealloc/finalize has a NULL lua_State which implies the Lua-side was never properly initialized.");
	}
}

void LuaSubclassBridge_ParseFFIArgumentAndPushToLua(unsigned int i, ParseSupportFunction* parse_support, lua_State* lua_state, void** args_from_ffi)
{
	ParseSupportArgument* current_parse_support_argument = [parse_support.argumentArray objectAtIndex:i];
	
    if(false == current_parse_support_argument.isStructType)
    {
        
        char objc_encoding_type = [current_parse_support_argument.objcEncodingType UTF8String][0];
        // START COPY AND PASTE HERE
        switch(objc_encoding_type)
        {
            case _C_ID:
            {
                id the_argument = *(id*)args_from_ffi[i];
                LuaObjectBridge_Pushid(lua_state, the_argument);
                break;
            }
            case _C_CLASS:
            {
                Class the_argument = *(Class*)args_from_ffi[i];
                LuaObjectBridge_PushClass(lua_state, the_argument);
                break;
            }
            case _C_SEL:
            {
                SEL the_argument = *(SEL*)args_from_ffi[i];
                LuaSelectorBridge_pushselector(lua_state, the_argument);
                break;
            }
            case _C_CHR:
            {
                char the_argument = *(char*)args_from_ffi[i];
                lua_pushinteger(lua_state, (lua_Integer)(the_argument));
                break;
            }
            case _C_UCHR:
            {
                unsigned char the_argument = *(unsigned char*)args_from_ffi[i];
                lua_pushinteger(lua_state, (lua_Integer)(the_argument));
                break;
            }
            case _C_SHT:
            {
                short the_argument = *(short*)args_from_ffi[i];
                lua_pushinteger(lua_state, (lua_Integer)(the_argument));
                break;
            }
            case _C_USHT:
            {
                unsigned short the_argument = *(unsigned short*)args_from_ffi[i];
                lua_pushinteger(lua_state, (lua_Integer)(the_argument));
                break;
            }
            case _C_INT:
            {
                int the_argument = *(int*)args_from_ffi[i];
                lua_pushinteger(lua_state, (lua_Integer)(the_argument));				
                break;
            }
            case _C_UINT:
            {
                unsigned int the_argument = *(unsigned int*)args_from_ffi[i];
                lua_pushinteger(lua_state, (lua_Integer)(the_argument));				
                break;
            }
            case _C_LNG:
            {
                long the_argument = *(long*)args_from_ffi[i];
                lua_pushinteger(lua_state, (lua_Integer)(the_argument));				
                break;
            }
            case _C_ULNG:
            {
                unsigned long the_argument = *(unsigned long*)args_from_ffi[i];
                lua_pushinteger(lua_state, (lua_Integer)(the_argument));				
                break;
            }
            case _C_LNG_LNG:
            {
                long long the_argument = *(long long*)args_from_ffi[i];
                lua_pushinteger(lua_state, (lua_Integer)(the_argument));				
                break;
            }
            case _C_ULNG_LNG:
            {
                unsigned long long the_argument = *(unsigned long long*)args_from_ffi[i];
                lua_pushinteger(lua_state, (lua_Integer)(the_argument));				
                break;
            }
            case _C_FLT:
            {
                float the_argument = *(float*)args_from_ffi[i];
                lua_pushnumber(lua_state, (lua_Number)(the_argument));				
                break;
            }
            case _C_DBL:
            {
                double the_argument = *(double*)args_from_ffi[i];
                lua_pushnumber(lua_state, (lua_Number)(the_argument));				
                break;
            }
            case _C_BOOL:
            {
                bool the_argument = *(bool*)args_from_ffi[i];
                lua_pushboolean(lua_state, the_argument);				
                break;
            }
            case _C_VOID:
            {
                // no return value (probably an error if I get here)
                break;
            }
            case _C_CHARPTR:
            {
                const char* the_argument = *(const char**)args_from_ffi[i];
                lua_pushstring(lua_state, (const char*)the_argument);
                break;
            }
            case _C_PTR:
            {
                // We might want to look for in/out modifiers, but in the Blocks implementation, the block information is lacking so I just do it.
                // For consistency, I just do it here too.
                // Try to dereference pointer to something that is easily used in Lua since getting lightuserdata pointer in Lua isn't easy to do anything with.
                if([[current_parse_support_argument objcEncodingType] length] <= 1)
                {
                    void* the_argument = *(void**)args_from_ffi[i];
                    lua_pushlightuserdata(lua_state, the_argument);
                    break;
                }
                
                char pointer_to_objc_encoding_type = [current_parse_support_argument.objcEncodingType UTF8String][1];
                
                switch(pointer_to_objc_encoding_type)
                {
                    case _C_ID:
                    {
                        id* the_argument = *(id**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        LuaObjectBridge_Pushid(lua_state, *the_argument);
                        break;
                    }
                    case _C_CLASS:
                    {
                        Class* the_argument = *(Class**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        LuaObjectBridge_PushClass(lua_state, *the_argument);
                        break;
                    }
                    case _C_CHARPTR:
                    {
                        const char** the_argument = *(const char***)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        lua_pushstring(lua_state, *the_argument);
                        break;
                    }
                    case _C_SEL:
                    {
                        SEL* the_argument = *(SEL**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        LuaSelectorBridge_pushselector(lua_state, *the_argument);
                        break;
                    }
                    case _C_CHR:
                    {
                        char* the_argument = *(char**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        lua_pushinteger(lua_state, (lua_Integer)(*the_argument));
                        break;
                    }
                    case _C_UCHR:
                    {
                        unsigned char* the_argument = *(unsigned char**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        lua_pushinteger(lua_state, (lua_Integer)(*the_argument));
                        break;
                    }
                    case _C_SHT:
                    {
                        short* the_argument = *(short**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        lua_pushinteger(lua_state, (lua_Integer)(*the_argument));
                        break;
                    }
                    case _C_USHT:
                    {
                        unsigned short* the_argument = *(unsigned short**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        lua_pushinteger(lua_state, (lua_Integer)(*the_argument));
                        break;
                    }
                    case _C_INT:
                    {
                        int* the_argument = *(int**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        lua_pushinteger(lua_state, (lua_Integer)(*the_argument));				
                        break;
                    }
                    case _C_UINT:
                    {
                        unsigned int* the_argument = *(unsigned int**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        lua_pushinteger(lua_state, (lua_Integer)(*the_argument));				
                        break;
                    }
                    case _C_LNG:
                    {
                        long* the_argument = *(long**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        lua_pushinteger(lua_state, (lua_Integer)(*the_argument));				
                        break;
                    }
                    case _C_ULNG:
                    {
                        unsigned long* the_argument = *(unsigned long**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        lua_pushinteger(lua_state, (lua_Integer)(*the_argument));				
                        break;
                    }
                    case _C_LNG_LNG:
                    {
                        long long* the_argument = *(long long**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        lua_pushinteger(lua_state, (lua_Integer)(*the_argument));				
                        break;
                    }
                    case _C_ULNG_LNG:
                    {
                        unsigned long long* the_argument = *(unsigned long long**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        lua_pushinteger(lua_state, (lua_Integer)(*the_argument));				
                        break;
                    }
                    case _C_FLT:
                    {
                        float* the_argument = *(float**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        lua_pushnumber(lua_state, (lua_Number)(*the_argument));				
                        break;
                    }
                    case _C_DBL:
                    {
                        double* the_argument = *(double**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        lua_pushnumber(lua_state, (lua_Number)(*the_argument));				
                        break;
                    }
                    case _C_BOOL:
                    {
                        bool* the_argument = *(bool**)args_from_ffi[i];
                        if(NULL == the_argument)
                        {
                            lua_pushnil(lua_state);
                            break;
                        }
                        lua_pushboolean(lua_state, *the_argument);				
                        break;
                    }
                    case _C_PTR:
                    default:
                    {
                        // I'm not going to try to dereference multiple levels.
                        void* the_argument = *(void**)args_from_ffi[i];
                        lua_pushlightuserdata(lua_state, the_argument);
                    }
                }
                break;
            }
                
				
				// compositeType check prevents reaching this case, handled in else
				/*
				 case _C_STRUCT_B:
				 {
				 
				 }
				 */
            case _C_ATOM:
            case _C_ARY_B:
            case _C_UNION_B:
            case _C_BFLD:
                
            default:
            {
                // returns
                //					luaL_error(lua_state, "Unhandled/unimplemented type %c in LuaSubclassBridge_GenericClosureCallback", objc_encoding_type);
                [NSException raise:@"Unhandled/unimplemented type in LuaSubclassBridge_GenericClosureCallback" format:@"Unhandled/unimplemented type %c in LuaSubclassBridge_GenericClosureCallback: %c", objc_encoding_type];
            }
        }
    }
    else
    {
        // set correct struct metatable on new userdata
        NSString* struct_type_name = current_parse_support_argument.objcEncodingType;
        
        // set correct struct metatable on new userdata
        
        NSString* struct_struct_name = ParseSupport_StructureReturnNameFromReturnTypeEncoding(struct_type_name);
        
        // BUG:?? struct_struct_name may have a leading underscore on 32-bit ppc
        NSString* struct_keyname = [ParseSupportStruct keyNameFromStructName:struct_struct_name];
        
        // BUG:?? This breaks with the underscore
        //			size_t size_of_struct = [ParseSupport sizeOfStructureFromStructureName:struct_struct_name];
        size_t size_of_struct = [ParseSupport sizeOfStructureFromStructureName:struct_keyname];
        
        
        // pushes new userdata on top of stack
        void* struct_userdata = lua_newuserdata(lua_state, size_of_struct);
        
        // I'm confused: The_C_PTR further above requires on *(void**) or chokes.
        // But the _C_CHARPTR case above needs *(const char**) or it doesn't work.
        // But this case requires (void*) or I get NULL.
        void* the_argument = (void*)args_from_ffi[i];
        
        memcpy(struct_userdata, the_argument, size_of_struct);
        
        // Fetch the metatable for this struct type and apply it to the struct so the Lua scripter can access the fields
        LuaStructBridge_SetStructMetatableOnUserdata(lua_state, -1, struct_keyname, struct_struct_name);
    }
}

bool LuaSubclassBridge_SetFFIReturnValueFromLuaReturnValue(ffi_cif* the_cif, lua_State* lua_state, void* return_result, ParseSupportFunction* parse_support)
{
  	bool is_void_return = false;
	if(FFI_TYPE_VOID == the_cif->rtype->type)
	{
		is_void_return = true;
	}
	
	if(false == is_void_return)
	{
		int stack_index_return_value = lua_gettop(lua_state);
        
		if(FFI_TYPE_STRUCT == the_cif->rtype->type)
		{
			void* return_struct_ptr = lua_touserdata(lua_state, stack_index_return_value);
			memcpy(return_result, return_struct_ptr, the_cif->rtype->size);
		}
		else
		{
			switch(the_cif->rtype->type)
			{
				case FFI_TYPE_INT:
				case FFI_TYPE_SINT8:
				case FFI_TYPE_SINT16:
				case FFI_TYPE_SINT32:
				case FFI_TYPE_SINT64:
				{
					if(lua_isboolean(lua_state, stack_index_return_value))
					{
						// Copy the returned value into result. Because the return value of foo()
						// is smaller than sizeof(long), typecast it to ffi_arg. Use ffi_sarg
						// instead for signed types.
						*(ffi_sarg*)return_result = (ffi_sarg)lua_toboolean(lua_state, stack_index_return_value);
					}
					else
					{
						*(ffi_sarg*)return_result = (ffi_sarg)lua_tointeger(lua_state, stack_index_return_value);
					}
					break;
				}
				case FFI_TYPE_UINT8:
				case FFI_TYPE_UINT16:
				case FFI_TYPE_UINT32:
				case FFI_TYPE_UINT64:
				{
					if(lua_isboolean(lua_state, stack_index_return_value))
					{
						// Copy the returned value into result. Because the return value of foo()
						// is smaller than sizeof(long), typecast it to ffi_arg. Use ffi_sarg
						// instead for signed types.
						*(ffi_arg*)return_result = (ffi_arg)lua_toboolean(lua_state, stack_index_return_value);
					}
					else
					{
						*(ffi_arg*)return_result = (ffi_arg)lua_tointeger(lua_state, stack_index_return_value);
					}
					break;
				}
                    
#if FFI_TYPE_LONGDOUBLE != FFI_TYPE_DOUBLE
				case FFI_TYPE_LONGDOUBLE:
				{	
					*(ffi_sarg*)return_result = (ffi_sarg)lua_tonumber(lua_state, stack_index_return_value);
					break;
				}
#endif
					
				case FFI_TYPE_DOUBLE:
				case FFI_TYPE_FLOAT:
				{
					*(ffi_sarg*)return_result = (ffi_sarg)lua_tonumber(lua_state, stack_index_return_value);
					break;
				}
                    
				case FFI_TYPE_POINTER:
				{
					ParseSupportArgument* return_parse_support_argument = parse_support.returnValue;
                    
					char objc_encoding_type = [return_parse_support_argument.objcEncodingType UTF8String][0];
					
					switch(objc_encoding_type)
					{
						case _C_ID:
						case _C_CLASS:
						{
							if(lua_isnil(lua_state, stack_index_return_value))
							{
								*(id*)return_result = nil;
							}
							else
							{
								// Will auto-coerce numbers, strings, tables to Cocoa objects
								id the_object = LuaObjectBridge_topropertylist(lua_state, stack_index_return_value);
								*(id*)return_result = the_object;
							}
							break;
						}
						case _C_CHARPTR:
						{
							if(lua_isstring(lua_state, stack_index_return_value))
							{
								*(const char**)return_result = (const char*)lua_tostring(lua_state, stack_index_return_value);
							}
							else if(LuaObjectBridge_isnsstring(lua_state, stack_index_return_value))
							{
								*(const char**)return_result = [LuaObjectBridge_tonsstring(lua_state, stack_index_return_value) UTF8String];
							}
							else
							{
								*(const char**)return_result = NULL;
							}
							break;
						}
						case _C_SEL:
						{
							*(SEL*)return_result = LuaSelectorBridge_toselector(lua_state, stack_index_return_value);
							break;
						}
							
						case _C_PTR:
						default:
						{
							// This might be problematic if the userdata pointer is a Lua-only pointer
							// (not a generic lightuserdata pointer that can be useful outside of Lua)
							// especially in the cases where the caller is Obj-C.
							*(void**)return_result = lua_touserdata(lua_state, stack_index_return_value);
						}
					}
					break;
				}
				default:
				{
					NSLog(@"Unhandled return type in LuaSubclassBridge_GenericClsureCallback() (also used for Blocks)");
				}
			}
			
#ifdef __BIG_ENDIAN__
			// Seen in JSCocoa
			// As ffi always uses a sizeof(long) return value (even for chars and shorts), do some shifting
			char type_encoding_char = [parse_support.returnValue.objcEncodingType UTF8String][0];
			int data_size = ObjCRuntimeSupport_SizeOfTypeEncoding(type_encoding_char);
			int padded_size = sizeof(long);
			long v; 
			if(data_size > 0 && data_size < padded_size && padded_size == 4)
			{
				v = *(long*)return_result;
				v = CFSwapInt32(v);
				*(long*)return_result = v;
			}
#endif	
		}
		
	}
    return is_void_return;
}

void LuaSubclassBridge_ProcessExtraReturnValuesFromLuaAsPointerOutArguments(lua_State* lua_state, void** args_from_ffi, ParseSupportFunction* parse_support, int start_parse_support_index, int start_lua_return_index)
{
	
	int j = start_lua_return_index;
	
	// Start at 1 instead of 0 because we want to skip the block argument
	for(int i=start_parse_support_index ; i<[parse_support.argumentArray count]; i++)
	{
		ParseSupportArgument* current_parse_support_argument = [parse_support.argumentArray objectAtIndex:i];
		if(false == current_parse_support_argument.isStructType)
		{
			if([[current_parse_support_argument objcEncodingType] length] >= 2 
			   && _C_PTR == [current_parse_support_argument.objcEncodingType UTF8String][0])
			{
				char objc_encoding_type = [current_parse_support_argument.objcEncodingType UTF8String][1];
				
				switch(objc_encoding_type)
				{
					case _C_BOOL:
					{
						_Bool* the_argument = *(_Bool**)args_from_ffi[i];

						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = (_Bool)lua_toboolean(lua_state, j);
						}
						break;
					}
					case _C_CHR:
					{
						int8_t* the_argument = *(int8_t**)args_from_ffi[i];

						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = lua_tointeger(lua_state, j);
						}
						break;
					}
					case _C_SHT:
					{
						int16_t* the_argument = *(int16_t**)args_from_ffi[i];

						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = lua_tointeger(lua_state, j);
						}
						break;
					}
					case _C_INT:
					{    
						int* the_argument = *(int**)args_from_ffi[i];
						
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = lua_tointeger(lua_state, j);
						}
						break;			
					}
					case _C_LNG:
					{
						long* the_argument = *(long**)args_from_ffi[i];
						
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = lua_tointeger(lua_state, j);
						}
						break;
					}
					case _C_LNG_LNG:
					{
						long long* the_argument = *(long long**)args_from_ffi[i];
						
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = lua_tointeger(lua_state, j);
						}
						break;
					}
					case _C_UCHR:
					{
						uint8_t* the_argument = *(uint8_t**)args_from_ffi[i];
						
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = lua_tointeger(lua_state, j);
						}
						break;
					}
					case _C_USHT:
					{
						uint16_t* the_argument = *(uint16_t**)args_from_ffi[i];
						
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = lua_tointeger(lua_state, j);
						}
						break;
					}
					case _C_UINT:
					{
						unsigned int* the_argument = *(unsigned int**)args_from_ffi[i];
						
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = lua_tointeger(lua_state, j);
						}
						break;
					}
					case _C_ULNG:
					{
						unsigned long* the_argument = *(unsigned long**)args_from_ffi[i];
						
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = lua_tointeger(lua_state, j);
						}
						break;
					}
					case _C_ULNG_LNG:
					{
						unsigned long long* the_argument = *(unsigned long long**)args_from_ffi[i];
						
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = lua_tointeger(lua_state, j);
						}
						break;
					}
					case _C_DBL:
					{
						double* the_argument = *(double**)args_from_ffi[i];
						
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = lua_tonumber(lua_state, j);
						}
						break;
					}
					case _C_FLT:
					{
						float* the_argument = *(float**)args_from_ffi[i];
						
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = lua_tonumber(lua_state, j);
						}
						break;
					}
						
					case _C_STRUCT_B:
					{
						void** the_argument = *(void***)args_from_ffi[i];
						
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							// untested
							*the_argument = lua_touserdata(lua_state, j);
						}
						break;
					}
						
					case _C_ID:
					{
						id* the_argument = *(id**)args_from_ffi[i];
						
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = LuaObjectBridge_toid(lua_state, j);
						}
						break;
					}
					case _C_CLASS:
					{
						Class* the_argument = *(Class**)args_from_ffi[i];
						
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = LuaObjectBridge_toid(lua_state, j);
						}
						break;
					}
					case _C_CHARPTR:
					{
						char** the_argument = *(char***)args_from_ffi[i];

						// I don't expect this to work at all
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							const char* the_string = lua_tostring(lua_state, j);
							size_t length_of_string = strlen(the_string) + 1; // add one for \0
							
							*the_argument = alloca(sizeof(length_of_string));
							strlcpy(*the_argument, the_string, length_of_string);
						}
						break;
					}
					case _C_SEL:
					{
						SEL* the_argument = *(SEL**)args_from_ffi[i];
						
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							*the_argument = LuaSelectorBridge_toselector(lua_state, j);
						}
						break;
					}
						
					case _C_PTR:
					default:
					{
						void** the_argument = *(void***)args_from_ffi[i];
						
						if(NULL == the_argument || lua_isnil(lua_state, j))
						{
							the_argument = NULL;
						}
						else
						{
							// untested
							*the_argument = lua_touserdata(lua_state, j);
						}
						break;
					}
				}
				j++; // assume we used up this return value, move on to the next return value
			}
		}
	}
}


// Invoking the closure transfers control to this function.
static void LuaSubclassBridge_GenericClosureCallback(ffi_cif* the_cif, void* return_result, void** args_from_ffi, void* user_data)
{
	// FIXME: ParseSupport isn't going to have data for variadic arguments
	
	LuaFFIClosureUserDataContainer* closure_user_data = (LuaFFIClosureUserDataContainer*)user_data;
	unsigned int number_of_arguments = the_cif->nargs;

	
	// I actually expect a ParseSupportMethod, but I don't think I need any specific APIs from it.
	/*
	assert([closure_user_data->parseSupport isKindOfClass:[ParseSupportFunction class]]);
	ParseSupportFunction* parse_support = (ParseSupportFunction*)closure_user_data->parseSupport;
	*/
	ParseSupportMethod* parse_support = (ParseSupportMethod*)closure_user_data->parseSupport;
	Class the_class = closure_user_data->theClass;
	unsigned int i = 0;

	lua_State* lua_state = closure_user_data->luaState;

	int stack_top = 0;

	if([closure_user_data->parseSupport isKindOfClass:[ParseSupportMethod class]])
	{
		id the_receiver = *(id*)args_from_ffi[0];
		
		SEL the_selector = *(SEL*)args_from_ffi[1];
		
		
		// I need to guard against cases where the Lua state has already been closed.
		if(![[LuaClassDefinitionMap sharedDefinitionMap] isSelectorDefined:the_selector inClass:the_class inLuaState:lua_state])
		{
			// So there are different ways to hit this problem.
			// - The user closed the script, but due to some asynchronous method, this callback was invoked later.
			// - The user relaunched a script. They only need the implementation definition which is constant against relaunches, so calling a different lua state with the same implementation should work (provided there is no specific lua_state/per-instance info that needs to survive).
			// - The user screwed up.
			// Since there is a valid case of this, I will try to fetch a sibling lua state.
			lua_state = [[LuaClassDefinitionMap sharedDefinitionMap] anyLuaStateForSelector:the_selector inClass:the_class];
			if(NULL == lua_state)
			{
				NSLog(@"lua_State for subclass method invocation has been closed/removed. Aborting call.");
				
				// Abort function.
				return;
				
			}
			else
			{
				NSLog(@"lua_State for subclass method invocation has been closed/removed. Using alternative lua_State.");
			}
		}

		const char* selector_name = sel_getName(the_selector);
		size_t buffer_length = strlen(selector_name) + 1;
		char underscored_function_name[buffer_length];
		ObjectSupport_ConvertObjCStringToUnderscoredString(underscored_function_name, selector_name, buffer_length);
		
		
		stack_top = lua_gettop(lua_state);

		
		
		
		
		ParseSupportArgument* first_parse_support_argument = [parse_support.argumentArray objectAtIndex:0];
		char objc_encoding_type = [first_parse_support_argument.objcEncodingType UTF8String][0];
		if(_C_ID == objc_encoding_type)
		{
			Class which_class_found = nil;
			bool is_instance_defined;
			// Should leave method on stack
//			bool did_find_lua_method = LuaSubclassBridge_FindLuaMethodInClass(lua_state, [the_receiver class], underscored_function_name, &which_class_found, &is_instance_defined);
			bool did_find_lua_method = LuaSubclassBridge_FindLuaMethodInClass(lua_state, the_class, underscored_function_name, &which_class_found, &is_instance_defined);
#pragma unused(did_find_lua_method)
			LuaObjectBridge_Pushid(lua_state, the_receiver);

		}
		else // _C_CLASS
		{			
			Class which_class_found = nil;
			bool is_instance_defined; 
			// Should leave method on stack
//			bool did_find_lua_method = LuaSubclassBridge_FindLuaMethodInClass(lua_state, [the_receiver class], underscored_function_name, &which_class_found, &is_instance_defined);
			bool did_find_lua_method = LuaSubclassBridge_FindLuaMethodInClass(lua_state, the_class, underscored_function_name, &which_class_found, &is_instance_defined);
#pragma unused(did_find_lua_method)
			LuaObjectBridge_PushClass(lua_state, the_receiver);
		}


		
		i = 2;
	}
	/*
	else if([closure_user_data->parseSupport isKindOfClass:[ParseSupportFunction class]])
	{
		const char* selector_name = [parse_support.keyName UTF8String];
		size_t buffer_length = strlen(selector_name) + 1;
		char underscored_function_name[buffer_length];
		ObjectSupport_ConvertObjCStringToUnderscoredString(underscored_function_name, selector_name, buffer_length);
		lua_getglobal(lua_state, underscored_function_name);
	}
	*/
	else
	{
		NSLog(@"Unsupported ParseSupport type");
		luaL_error(lua_state, "Unsupported ParseSupport type");
	}


	// FIXME: Do variadic arguments here
	
	// Need to handle variadic arguments.
	// Since the ParseSupport is shared, I don't really want to modify the shared instance.
	if(number_of_arguments > [parse_support.argumentArray count])
	{
		NSLog(@"Warning in LuaSubclassBridge_GenericClosureCallback: Variadic arguments are untested"); 
		// replace parse_support pointer with a copy that we can change
		parse_support = [[parse_support mutableCopy] autorelease];
		LuaFFISupport_ParseVariadicArgumentsInFFIArgs(parse_support, the_cif, args_from_ffi, [parse_support.argumentArray count]);

	}

	/*	
	 if(number_of_arguments - NUMBER_OF_SUPPORT_ARGS - 1 > 0)
	 {
	 
	 // If there are variadic arguments, add them to the parse support information.
	 // Note that if there are variadic arguments, this parse_support instance cannot be reused/cached for different function calls
	 // Offset is 0-1 (0 for no internal use arguments, -1 because the first 2 arguments are supposed to be the receiver and selector,
	 // but the selector is not an argument on the stack (it is a upvalue), so we must subtract 1
	 LuaFFISupport_ParseVariadicArguments(lua_state, parse_support, NUMBER_OF_SUPPORT_ARGS-1);
	 }
	 */	
	
	// We already pushed self on the stack before this call.
	// Minus 1 for self, Plus 1 for function.
	lua_checkstack(lua_state, [parse_support.argumentArray count]);

		
//    for(ParseSupportArgument* current_parse_support_argument = [parse_support.argumentArray objectAtIndex:i]; i<[parse_support.argumentArray count]; current_parse_support_argument = [parse_support.argumentArray objectAtIndex:i], i++)
	for(i=2 ; i<[parse_support.argumentArray count]; i++)
//	for(ParseSupportArgument* current_parse_support_argument in parse_support.argumentArray)
	{
		LuaSubclassBridge_ParseFFIArgumentAndPushToLua(i, parse_support, lua_state, args_from_ffi);
	}
	
	// Not sure, pcall or call
#if 1
	int the_error = lua_pcall(lua_state, number_of_arguments-1, LUA_MULTRET, 0);
	if(0 != the_error)
	{
		// returns immediately
//		luaL_error(lua_state, "lua/ffi_prep_closure invocation failed: %s", lua_tostring(lua_state, -1));
		[NSException raise:@"lua/ffi_prep_closure invocation failed in LuaSubclassBridge callback:" format:@"lua/ffi_prep_closure invocation failed in LuaSubclassBridge callback: %s", lua_tostring(lua_state, -1)];
//		lua_pop(lua_state, 1); /* pop error message from stack */
		return;
	}

#else
	lua_call(lua_state, number_of_arguments-1, LUA_MULTRET);

#endif
	
	
	// Now that we just called Lua, figure out how many return values were set. 
	// Extra return values in addition to the C/Signature return value denotes out-values.
	int number_of_return_args = lua_gettop(lua_state);

	// Set the return FFI value from the first Lua return value
	bool is_void_return = LuaSubclassBridge_SetFFIReturnValueFromLuaReturnValue(the_cif, lua_state, return_result, parse_support);	
	
	/*  
	 I am reusing the same function for subclasses and blocks for dealing with out-values.
	 The bridge support data is missing out modifiers.
	 The base case I'm using is
	 array = LuaCocoa.toCocoa({"bar", "foo", "fee"})
	 array:enumerateObjectsUsingBlock_(function(id_obj, int_index, boolptr_stop) 
	 print("in block callback of array:enumerateObjectsUsingBlock_ ", id_obj, int_index, boolptr_stop)
	 boolptr_stop=true
	 end
	 )
	 The BOOL* stop is a problem.
	 I am going to assume all pointer values will be out-values.
	 I will use multiple return values to map to the pointers.
	 There cannot be any holes in the return values for each pointer.
	 */
	
	bool has_pointer_out_values = false;
	int j=0; // lua index of the return value we are looking at
	if(true == is_void_return && number_of_return_args > 0)
	{
		j=stack_top+1;
		has_pointer_out_values = true;
	}
	else if(false == is_void_return && number_of_return_args > 1)
	{
		has_pointer_out_values = true;
		j=stack_top+2;
	}
	
	if(true == has_pointer_out_values)
	{
		// Start at 2 instead of 0 because we want to skip the method and selector arguments
		LuaSubclassBridge_ProcessExtraReturnValuesFromLuaAsPointerOutArguments(lua_state, args_from_ffi, parse_support, 2, j);
	}
	
	
	
	
	lua_settop(lua_state, stack_top); // pop the string and the container

}

#if 0
/*
NSString* constFoo = @",";
// Invoking the closure transfers control to this function.
static void
foo_closure(ffi_cif* cif, void* result, void** args, void* userdata)
{
NSLog(@"foo_closure");
NSLog(@"sizeof(ffi_arg)=%d, sizeof(ffi_sarg)=%d, sizeof(long)=%d, sizeof(id)=%d", sizeof(ffi_arg), sizeof(ffi_sarg), sizeof(long), sizeof(id));
	NSLog(@"sizeof(cif->rtype->size)=%d", cif->rtype->size);
//cif->rtype->size = 0;
	// Access the arguments to be sent to foo().
//	float arg1 = *(float*)args[0];
//	unsigned int arg2 = *(unsigned int*)args[1];
	
	// Call foo() and save its return value.
//	unsigned char ret_val = ;
	
	// Copy the returned value into result. Because the return value of foo()
	// is smaller than sizeof(long), typecast it to ffi_arg. Use ffi_sarg
	// instead for signed types.
//	*(ffi_arg*)result = (ffi_arg)constFoo;
//	*(id*)result = (id)constFoo;
	*(id*)result = [NSString stringWithUTF8String:"__seperator__"];
}

IMP LuaSubclassBridge_CreateAndSetFFIClosureForSetMethod2(lua_State* lua_state, Class the_class, const char* method_name_in_objc, SEL the_selector, const char* method_signature, ParseSupport** return_parse_support, int stack_index_of_userdata)
{
//	ffi_cif cif;
	ffi_cif* new_cif = (ffi_cif*)calloc(1, sizeof(ffi_cif));
	ffi_closure *closure;
//	ffi_type *arg_types[2];
	ffi_type** arg_types = (ffi_type**)calloc(2, sizeof(ffi_type*));

	ffi_arg result;
	ffi_status status;
	
	// Specify the data type of each argument. Available types are defined
	// in <ffi/ffi.h>.
	arg_types[0] = &ffi_type_pointer;
	arg_types[1] = &ffi_type_pointer;
	
	// Allocate a page to hold the closure with read and write permissions.
	if ((closure = mmap(NULL, sizeof(ffi_closure), PROT_READ | PROT_WRITE,
						MAP_ANON | MAP_PRIVATE, -1, 0)) == (void*)-1)
	{
		// Check errno and handle the error.
		perror( "Error opening file" );
		fprintf( stderr, "Error opening file: %s\n", strerror( errno ) );
	}
	
	// Prepare the ffi_cif structure.
	if ((status = ffi_prep_cif(new_cif, FFI_DEFAULT_ABI,
							   2, &ffi_type_pointer, arg_types)) != FFI_OK)
//							   2, &ffi_type_void, arg_types)) != FFI_OK)
	{
		// Handle the ffi_status error.
		NSLog(@"Error: ffi_status error");

		
	}
	
	// Prepare the ffi_closure structure.
	if ((status = ffi_prep_closure(closure, new_cif, foo_closure, NULL)) != FFI_OK)
	{
		// Handle the ffi_status error.
		NSLog(@"Error: ffi_status error");

	}
	
	// Ensure that the closure will execute on all architectures.
	if (mprotect(closure, sizeof(closure), PROT_READ | PROT_EXEC) == -1)
	{
		// Check errno and handle the error.
		perror( "Error opening file" );
		fprintf( stderr, "Error opening file: %s\n", strerror( errno ) );

	}
	
	NSLog(@"sel=%@, method_signature=%s", NSStringFromSelector(the_selector), method_signature);
	// Will call addMethod or method_setImplementation depending on the situation
#if 1
//	IMP ret_imp = class_replaceMethod(the_class, the_selector, (IMP)closure, "@@:");
//	class_replaceMethod(the_class, the_selector, (IMP)closure, NULL);
//IMP ret_imp = 	class_replaceMethod(the_class, the_selector, (IMP)closure, "v@:");
	IMP ret_imp = class_replaceMethod(the_class, the_selector, (IMP)closure, method_signature);
	if(NULL == ret_imp)
	{
		NSLog(@"ret_imp was NULL");
	}
	else if(ret_imp == (IMP)closure)
	{
		NSLog(@"ret_imp was same as new method");
	}
#else
	// If successful, set it as method
	if(closure)
	{
		// First addMethod : use class_addMethod to set closure
		if(!class_addMethod(the_class, the_selector, (IMP)closure, method_signature))
		{
			// After that, we need to patch the method's implementation to set closure
			Method the_method = class_getInstanceMethod(the_class, the_selector);
			if (!the_method)	the_method = class_getClassMethod(the_class, the_selector);
			method_setImplementation(the_method, (IMP)closure);
		}
	}
	else
	{
		NSLog(@"Error: closure is NULL");
	}
#endif
	return (IMP)closure;
}
*/
#endif

// Invoking the closure transfers control to this function.
void LuaSubclassBridge_InvokeDeallocFinalizeClosureCallback(id self_arg, SEL selector_arg, Class class_type, lua_State* lua_state, LuaFFIClosureUserDataContainer* closure_user_data)
{
	// We need to be very careful when in a finalizer. 
	// For example, we don't want to do stuff on self that would trigger a resurrection error.
	// So the operations here only use the pointer for storing and hashing in maps which should be fine.
	if(NULL != lua_state)
	{
		// I need to guard against cases where the Lua state has already been closed.
		// This is particularly a problem with Obj-C garbage collection where finalize may be invoked some time later.
		if([[LuaClassDefinitionMap sharedDefinitionMap] isSelectorDefined:selector_arg inClass:class_type inLuaState:lua_state])
		{
			LuaCocoaStrongTable_RemoveLuaSubclassEnvironmentTableInGlobalStrongTable(lua_state, self_arg);
		}
	}
	else
	{
		NSLog(@"Warning/AssertionFailure: dealloc/finalize has a NULL lua_State which implies the Lua-side was never properly initialized.");
	}


	
//	Class parent_class = class_getSuperclass(object_getClass(self_arg));
//	NSLog(@"super:%@", NSStringFromClass(parent_class));
	

//	NSLog(@"super userdata:%@, super=%@", NSStringFromClass((Class)closure_user_data->parseSupport), class_getSuperclass(((Class)closure_user_data->parseSupport)));
//	struct objc_super super_data = { self_arg, parent_class };

	/* Question: Should the call to super be here or in the original background thread? */
/*	
	// This was tricky. Dynamically asking for the super class of the self object doesn't work for deep subclasses,
	// because you get into an infinite loop problem when calling intermediate super's.
	// In the super method, the self-object is still the same, and the super is relative to that original object,
	// so it stops traversing upward and gets stuck in an infinite loop.
	// My solution is to attach the class that this method/closure was created for as userdata,
	// and then use the super of that class. This should always provide me the correct class.
	struct objc_super super_data = { self_arg, class_getSuperclass(closure_user_data->theClass) };

	objc_msgSendSuper(&super_data, selector_arg);
*/		
}

static void LuaSubclassBridge_DeallocFinalizeClosureCallback(ffi_cif* the_cif, void* return_result, void** method_args, void* user_data)
{	
	// TODO: Add some kind of macro like LUA_LOCK or delegate or block system that users can define to validate if the lua_State is still alive/valid
	// so we can bailout if need be.
	// Example use case: You have a script reloading feature like HybridCoreAnimationScriptability where the lua_State* can get closed and reopened
	// without quiting the app. You do a asynchronous network connection which has a block completion handler like the Game Center APIs.
	// You close/reload your script before the network returns the data and triggers your completion handler.
	// The block is still alive on the Obj-C side, so this gets invoked. We have no general way of knowing that the lua_State is no longer good.
	// VALIDATE_LUA_STATE([closure_user_data luaState)
	
	
	// Because Lua is not compiled with thread locking by default,
	// we must take care to prevent calling Lua back on a different thread.
	// When the instance is created, we will get the current thread and presume this is the thread that is safe to call Lua back on.
	// TODO: Add define to disable this in case somebody does compile Lua with locking enabled and wants to try this.
	
	
	// Access the arguments to be sent to foo().
	id self_arg = *(id*)method_args[0];
	SEL selector_arg = *(SEL*)method_args[1];
	Class class_type = [self_arg class];
	lua_State* lua_state = LuaSubclassBridge_GetLuaStateFromLuaSubclassObject(self_arg);
	LuaFFIClosureUserDataContainer* closure_user_data = (LuaFFIClosureUserDataContainer*)user_data;
	
	NSThread* origin_thread = LuaSubclassBridge_GetOriginThreadFromLuaSubclassObject(self_arg);

	// Avoid calling dispatch_sync if I don't need to otherwise I deadlock.
	if([origin_thread isEqualTo:[NSThread currentThread]])
	{
		LuaSubclassBridge_InvokeDeallocFinalizeClosureCallback(self_arg, selector_arg, class_type, lua_state, closure_user_data);
	}
	else
	{
		NSLog(@"Block is not being called back on the same thread it was created.");
		// We don't want to block the thread execution. Fortunately, since dealloc/finalize are simple enough and don't return anything,
		// we can extract out the information we need here.
		LuaCocoaSubclassDataForThreadDellocFinalize* thread_callback = [[LuaCocoaSubclassDataForThreadDellocFinalize alloc] 
			initWithSelfArg:self_arg 
			selectorArg:selector_arg
			classType:class_type
			luaState:lua_state
			closureUserData:closure_user_data
		];
																		
		[thread_callback performSelector:@selector(invokeCleanup:) onThread:origin_thread withObject:nil waitUntilDone:NO]; 
		[thread_callback release];
	}

	// Release the NSThread in the hidden ivar by using the setter. (It will call CFRelease for us.)
	LuaSubclassBridge_SetOriginThreadFromLuaSubclassObject(nil, self_arg);
	
	/* Question: Should the call to super be here or in the original background thread? */
	
	// This was tricky. Dynamically asking for the super class of the self object doesn't work for deep subclasses,
	// because you get into an infinite loop problem when calling intermediate super's.
	// In the super method, the self-object is still the same, and the super is relative to that original object,
	// so it stops traversing upward and gets stuck in an infinite loop.
	// My solution is to attach the class that this method/closure was created for as userdata,
	// and then use the super of that class. This should always provide me the correct class.
	struct objc_super super_data = { self_arg, class_getSuperclass(closure_user_data->theClass) };

	objc_msgSendSuper(&super_data, selector_arg);
		
}


static IMP LuaSubclassBridge_CreateAndSetFFIClosureForDeallocFinalize(lua_State* lua_state, Class the_class, const char* method_name_in_objc, SEL the_selector, int stack_index_of_userdata)
{
	ffi_cif* new_cif = (ffi_cif*)calloc(1, sizeof(ffi_cif));
	ffi_closure* imp_closure;
	ffi_type** arg_types = (ffi_type**)calloc(2, sizeof(ffi_type*));
	
	ffi_status status;
	
	// Specify the data type of each argument. Available types are defined
	// in <ffi/ffi.h>.
	arg_types[0] = &ffi_type_pointer;
	arg_types[1] = &ffi_type_pointer;
	
	// Allocate a page to hold the closure with read and write permissions.
	if((imp_closure = mmap(NULL, sizeof(ffi_closure), PROT_READ | PROT_WRITE,
						   MAP_ANON | MAP_PRIVATE, -1, 0)) == (void*)-1)
	{
		// Check errno and handle the error.
		perror( "Error opening file" );
		fprintf( stderr, "Error opening file: %s\n", strerror( errno ) );
	}
	
	// Prepare the ffi_cif structure.
	if((status = ffi_prep_cif(new_cif, FFI_DEFAULT_ABI, 2, &ffi_type_void, arg_types)) != FFI_OK)
	{
		// Handle the ffi_status error.
		NSLog(@"Error: ffi_status error");
		
		
	}
	
	
	
	
	
	// Save the ffi_closure in the environment table (so it can be released later)
	// An additional benefit is that if we had an existing closure from a previous set,
	// then the old closure should be released from the table and lua __gc should properly release it.
	
	lua_getfenv(lua_state, stack_index_of_userdata); // get the environment table from the userdata object, [env_table new_function function_name class_userdata] 
	lua_getfield(lua_state, -1, "__fficlosures"); // [__fficlosures_table env_table new_function function_name class_userdata] 
	
	lua_pushstring(lua_state, method_name_in_objc); // function name, [function_name __fficlosures_table env_table new_function function_name class_userdata] 
	// creates a new userdata and leaves it on the stack
	LuaFFIClosureUserDataContainer* lua_ffi_closure_user_data = LuaFFIClosure_CreateNewLuaFFIClosure(lua_state, new_cif, arg_types, NULL, NULL, NULL, NULL, NULL, imp_closure, nil, the_class);
	// [imp_function function_name __fficlosures_table env_table new_function function_name class_userdata]
	
	lua_settable(lua_state, -3); // __methods[function_name] = function, [__fficlosures_table env_table new_function function_name class_userdata] 
	lua_pop(lua_state, 2); // pop __fficlosures and environment_table
	
	
	
	
	
	// Prepare the ffi_closure structure.
	if ((status = ffi_prep_closure(imp_closure, new_cif, LuaSubclassBridge_DeallocFinalizeClosureCallback, lua_ffi_closure_user_data)) != FFI_OK)
	{
		// Handle the ffi_status error.
		NSLog(@"Error: ffi_status error");
		
	}
	
	// Ensure that the closure will execute on all architectures.
	if (mprotect(imp_closure, sizeof(imp_closure), PROT_READ | PROT_EXEC) == -1)
	{
		// Check errno and handle the error.
		perror( "Error opening file" );
		fprintf( stderr, "Error opening file: %s\n", strerror( errno ) );
		
	}
	
	// Will call addMethod or method_setImplementation depending on the situation
	IMP ret_imp = class_replaceMethod(the_class, the_selector, (IMP)imp_closure, "v@:");
#pragma unused(ret_imp)
	/*
	 if(NULL == ret_imp)
	 {
	 NSLog(@"ret_imp was NULL");
	 }
	 else if(ret_imp == (IMP)imp_closure)
	 {
	 NSLog(@"ret_imp was same as new method");
	 }
	 */
	
	
	return (IMP)imp_closure;
	
	
}


// Implemention might work, but I need to think about the design decisions.
// I don't know which super init to call.
/*
static void LuaSubclassBridge_InitWithLuaCocoaStateClosureCallback(ffi_cif* cif_ptr, void* return_result, void** method_args, void* userdata)
{
	
	
	NSLog(@"LuaSubclassBridge_InitWithLuaCocoaStateClosureCallback");
	
	
	// Access the arguments to be sent to foo().
	id self_arg = *(id*)method_args[0];
	SEL selector_arg = *(SEL*)method_args[1];
	lua_State* lua_state = *(lua_State*)method_args[2];
	
	
	if(NULL != lua_state)
	{
		LuaSubclassBridge_InitializeNewLuaObject(self, lua_state);		

		LuaCocoaStrongTable_RemoveLuaSubclassEnvironmentTableInGlobalStrongTable(lua_state, self_arg);		
	}
	
	
	Class parent_class = class_getSuperclass(object_getClass(self_arg));
	struct objc_super super_data = { self_arg, parent_class };
	// Which init do I call?
	// initWithLuaCocoaState may or may not exist
	id super_result = objc_msgSendSuper(&super_data, @selector(init));
	
	*(id*)return_result = super_result;

	
}

static IMP LuaSubclassBridge_CreateAndSetFFIClosureForInitWithLuaCocoaState(lua_State* lua_state, Class the_class, const char* method_name_in_objc, SEL the_selector, int stack_index_of_userdata)
{
	ffi_cif* new_cif = (ffi_cif*)calloc(1, sizeof(ffi_cif));
	ffi_closure* imp_closure;
	ffi_type** arg_types = (ffi_type**)calloc(3, sizeof(ffi_type*));
	
	ffi_status status;
	
	// Specify the data type of each argument. Available types are defined
	// in <ffi/ffi.h>.
	arg_types[0] = &ffi_type_pointer;
	arg_types[1] = &ffi_type_pointer;
	arg_types[2] = &ffi_type_pointer;

	// Allocate a page to hold the closure with read and write permissions.
	if((imp_closure = mmap(NULL, sizeof(ffi_closure), PROT_READ | PROT_WRITE,
						   MAP_ANON | MAP_PRIVATE, -1, 0)) == (void*)-1)
	{
		// Check errno and handle the error.
		perror( "Error opening file" );
		fprintf( stderr, "Error opening file: %s\n", strerror( errno ) );
	}
	
	// Prepare the ffi_cif structure.
	if((status = ffi_prep_cif(new_cif, FFI_DEFAULT_ABI, 2, &ffi_type_pointer, arg_types)) != FFI_OK)
	{
		// Handle the ffi_status error.
		NSLog(@"Error: ffi_status error");
		
		
	}
	
	
	
	
	
	// Save the ffi_closure in the environment table (so it can be released later)
	// An additional benefit is that if we had an existing closure from a previous set,
	// then the old closure should be released from the table and lua __gc should properly release it.
	
	lua_getfenv(lua_state, stack_index_of_userdata); // get the environment table from the userdata object, [env_table new_function function_name class_userdata] 
	lua_getfield(lua_state, -1, "__fficlosures"); // [__fficlosures_table env_table new_function function_name class_userdata] 
	
	lua_pushstring(lua_state, method_name_in_objc); // function name, [function_name __fficlosures_table env_table new_function function_name class_userdata] 
	// creates a new userdata and leaves it on the stack
	LuaFFIClosureUserDataContainer* lua_ffi_closure_user_data = LuaFFIClosure_CreateNewLuaFFIClosure(lua_state, new_cif, arg_types, imp_closure, nil);
	// [imp_function function_name __fficlosures_table env_table new_function function_name class_userdata]
	
	lua_settable(lua_state, -3); // __methods[function_name] = function, [__fficlosures_table env_table new_function function_name class_userdata] 
	lua_pop(lua_state, 2); // pop __fficlosures and environment_table
	
	
	
	
	
	// Prepare the ffi_closure structure.
	if ((status = ffi_prep_closure(imp_closure, new_cif, LuaSubclassBridge_DeallocFinalizeClosureCallback, lua_ffi_closure_user_data)) != FFI_OK)
	{
		// Handle the ffi_status error.
		NSLog(@"Error: ffi_status error");
		
	}
	
	// Ensure that the closure will execute on all architectures.
	if (mprotect(imp_closure, sizeof(imp_closure), PROT_READ | PROT_EXEC) == -1)
	{
		// Check errno and handle the error.
		perror( "Error opening file" );
		fprintf( stderr, "Error opening file: %s\n", strerror( errno ) );
		
	}
	
	// Will call addMethod or method_setImplementation depending on the situation
	IMP ret_imp = class_replaceMethod(the_class, the_selector, (IMP)imp_closure, "@@:^");

	return (IMP)imp_closure;
	
	
}
*/


IMP LuaSubclassBridge_CreateAndSetFFIClosureForSetMethod(lua_State* lua_state, Class the_class, const char* method_name_in_objc, SEL the_selector, const char* method_signature, ParseSupport** return_parse_support, int stack_index_of_userdata)
{
#warning "FIXME: Need clue as to whether class or instance method"
	// Probably could optimize. Parse support is probably doing a lot more than we need.
	ParseSupportMethod* parse_support = [ParseSupportMethod 
					  parseSupportMethodFromClassName:NSStringFromClass(the_class)
					  methodName:[NSString stringWithUTF8String:method_name_in_objc] 
					  isInstance:false
					  theReceiver:the_class
					  isClassMethod:false
					  stringMethodSignature:method_signature
					  ];
	
	if(NULL != return_parse_support)
	{
		*return_parse_support = parse_support;
	}
	
	/* Creating a block of memory is a bit tricky.
	 We actually need separate blocks of memory:
	 1) Memory for the ffi_cif
	 2) Memory to describe the normal arguments
	 3) Memory to hold custom ffi_type(s) (as in the case that an argument is a struct)
	 4) Memory to describe the flattened arguments (i.e. if #2 is a struct, this contains memory for each individial element in the struct)
	 5) Memory to describe the return argument
	 6) Memory to hold custom ffi_type (as in the case that the return argument is a struct)
	 7) Memory to describe the flattened return argument
	 When using Lua userdata, it is easiest to treat this a single block of memory 
	 since we want garbage collection to clean it up at the same time.
	 But because the memory is for distinct things, we need to keep our pointers straight
	 and not clobber each section's memory.
	 All the structures also need their internal pointers set correctly to find the correct blocks of memory.
	 
	 Userdata is:
	 1) sizeof(cif)
	 2) sizeof(ffi_type*) * number_of_real_function_arguments // don't forget to count varadic
	 3) sizeof(ffi_type) * number_of_real_arguments_that_need_to_be_flattened
	 4) sizeof(ffi_type*) * number_of_flattened_function_arguments // don't forget to count NULL terminators
	 5) sizeof(ffi_type*)
	 6) sizeof(ffi_type) * number_of_return_arguments_that_need_to_be_flattened
	 7) sizeof(ffi_type*) * number_of_flattened_function_arguments // don't forget to count NULL terminators
	 
	 */
//	size_t size_of_cif = sizeof(ffi_cif);
	size_t size_of_real_args = sizeof(ffi_type*) * parse_support.numberOfRealArguments;
	size_t size_of_flattened_args = sizeof(ffi_type*) * parse_support.numberOfFlattenedArguments;
	size_t size_of_custom_type_args = sizeof(ffi_type) * parse_support.numberOfRealArgumentsThatNeedToBeFlattened;
	size_t size_of_real_return = sizeof(ffi_type*);
	size_t size_of_flattened_return = sizeof(ffi_type*) * parse_support.numberOfFlattenedReturnValues;
	size_t size_of_custom_type_return;
	if(0 == size_of_flattened_return)
	{
		size_of_custom_type_return = 0;
	}
	else
	{
		size_of_custom_type_return = sizeof(ffi_type);
	}
	
//	ffi_cif the_cif;
	// FIXME: Check for 0 length sizes and avoid
#define ARBITRARY_NONZERO_SIZE 1
	size_t size_of_real_args_proxy = size_of_real_args ? size_of_real_args : ARBITRARY_NONZERO_SIZE;
//	size_t size_of_flattened_args_proxy = size_of_flattened_args ? size_of_flattened_args : ARBITRARY_NONZERO_SIZE;
//	size_t size_of_custom_type_args_proxy = size_of_custom_type_args ? size_of_custom_type_args : ARBITRARY_NONZERO_SIZE;
	size_t size_of_real_return_proxy = size_of_real_return ? size_of_real_return : ARBITRARY_NONZERO_SIZE;
#pragma unused(size_of_real_return_proxy)
//	size_t size_of_flattened_return_proxy = size_of_flattened_return ? size_of_flattened_return : ARBITRARY_NONZERO_SIZE;
//	size_t size_of_custom_type_return_proxy = size_of_custom_type_return ? size_of_custom_type_return : ARBITRARY_NONZERO_SIZE;
#undef ARBITRARY_NONZERO_SIZE
	
/*	
	// use VLAs to use stack memory
//	int8_t real_args_array[size_of_real_args_proxy];
	int8_t flattened_args_array[size_of_flattened_args_proxy];
	int8_t custom_type_args_array[size_of_custom_type_args_proxy];
	int8_t real_return_array[size_of_real_return_proxy];
	int8_t flattened_return_array[size_of_flattened_return_proxy];
	int8_t custom_type_return_array[size_of_custom_type_return_proxy];
*/	
	
	// The ffi_prep_closure documentation (man page) is completely unclear about memory ownership.
	// I learned the hard way (lots of mysterious crashes and debugging for a week blindly)
	// that the ffi_cif and arguments memory must persist as long as the closure is in use.
	// So, I must also create these things on the heap and save the pointers so I can clean them up when
	// I clean up the closure.
	
	// Setup pointers to memory areas
	ffi_cif* cif_ptr = (ffi_cif*)calloc(1, sizeof(ffi_cif));
	ffi_type** real_args_ptr = NULL;
	ffi_type** flattened_args_ptr = NULL;
	ffi_type* custom_type_args_ptr = NULL;
	
	ffi_type* real_return_ptr = NULL;
	ffi_type* custom_type_return_ptr = NULL;
	ffi_type** flattened_return_ptr = NULL;


	
/*
	ffi_type* real_return_ptr = NULL;
	if(size_of_real_return_proxy > 0)
	{
		real_return_ptr = (ffi_type*)calloc(size_of_real_return_proxy, sizeof(ffi_type));
	}
*/	
	
/*	
	ffi_type* custom_type_args_ptr = (ffi_type*)&custom_type_args_array[0];
	ffi_type** flattened_args_ptr = (ffi_type**)&flattened_args_array[0];
	
	ffi_type* real_return_ptr = (ffi_type*)&real_return_array[0];
	ffi_type* custom_type_return_ptr = (ffi_type*)&custom_type_return_array[0];
	ffi_type** flattened_return_ptr = (ffi_type**)&flattened_return_array[0];
*/	
	char check_void_return;
	if(nil == parse_support.returnValue.objcEncodingType || 0 == [parse_support.returnValue.objcEncodingType length])
	{
		// FIXME:
		NSLog(@"no return type set. This is probably a bug");
		// Not sure if I should assume id or void
		check_void_return = _C_ID;
	}
	else
	{
		check_void_return = [parse_support.returnValue.objcEncodingType UTF8String][0];
	}
	bool is_void_return = false;
	if(_C_VOID == check_void_return)
	{
		is_void_return = true;
	}
	

/*
	if(size_of_real_args > 0)
	{
		real_args_ptr = (ffi_type**)calloc(size_of_real_args, sizeof(ffi_type*));
	}
*/
	// Think I might always need this even if no arguments
	real_args_ptr = (ffi_type**)calloc(size_of_real_args_proxy, sizeof(int8_t));

	if(size_of_flattened_args > 0)
	{
		flattened_args_ptr = (ffi_type**)calloc(size_of_flattened_args, sizeof(int8_t));
	}
	if(size_of_custom_type_args > 0)
	{
		custom_type_args_ptr = (ffi_type*)calloc(size_of_custom_type_args, sizeof(int8_t));
	}
	
	
	// Watch out! ffi_type_for_args in FFISupport_ParseSupportFunctionReturnValueToFFIType may return a different pointer which is bad if you malloc'd memory.
	bool used_dynamic_memory_for_return_type = false;
	if(parse_support.returnValue.isStructType)
	{
		used_dynamic_memory_for_return_type = true;

		if(size_of_flattened_return > 0 && false == is_void_return)
		{
			flattened_return_ptr = (ffi_type**)calloc(size_of_flattened_return, sizeof(int8_t));
		}
		if(size_of_custom_type_return > 0 && false == is_void_return)
		{
			custom_type_return_ptr = (ffi_type*)calloc(size_of_custom_type_return, sizeof(int8_t));
		}

	}
	
	// Watch out! ffi_type_for_args may return a different pointer which is bad if you malloc'd memory.
	FFISupport_ParseSupportFunctionArgumentsToFFIType(parse_support, custom_type_args_ptr, &real_args_ptr, flattened_args_ptr);


	// Based on the bug found by Fjolnir, I think this is wrong.
	// I think the pointer should be NULL to be set by FFISupport_ParseSupportFunctionReturnValueToFFIType.
	FFISupport_ParseSupportFunctionReturnValueToFFIType(parse_support, custom_type_return_ptr, &real_return_ptr, flattened_return_ptr);

	// Prepare the ffi_cif structure.
	ffi_status error_status;
	error_status = ffi_prep_cif(cif_ptr, FFI_DEFAULT_ABI, parse_support.numberOfRealArguments, real_return_ptr, real_args_ptr);
	if(FFI_OK != error_status)
	{
		// Handle the ffi_status error.
		if(FFI_BAD_TYPEDEF == error_status)
		{
			NSLog(@"ffi_prep_cif failed with FFI_BAD_TYPEDEF for function: %@", parse_support.keyName);			
		}
		else if(FFI_BAD_ABI == error_status)
		{
			NSLog(@"ffi_prep_cif failed with FFI_BAD_ABI for function: %@", parse_support.keyName);			
		}
		else
		{
			NSLog(@"ffi_prep_cif failed with unknown error for function: %@", parse_support.keyName);			
			
		}
		free(flattened_return_ptr);
		free(custom_type_return_ptr);
		free(custom_type_args_ptr);
		free(flattened_args_ptr);
		free(real_args_ptr);
		free(cif_ptr);

		return false;
	}
	

	ffi_closure* imp_closure = NULL;
	// Allocate a page to hold the closure with read and write permissions.
	if((imp_closure = mmap(NULL, sizeof(ffi_closure), PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0)) == (void*)-1)
	{
		// Check errno and handle the error.
		
		NSLog(@"mmap failed for ffi_closure");
		free(flattened_return_ptr);
		free(custom_type_return_ptr);
		free(custom_type_args_ptr);
		free(flattened_args_ptr);
		free(real_args_ptr);
		free(cif_ptr);
		
		return false;
	}
	
	
	
	
	// Save the ffi_closure in the environment table (so it can be released later)
	// An additional benefit is that if we had an existing closure from a previous set,
	// then the old closure should be released from the table and lua __gc should properly release it.
	
	lua_getfenv(lua_state, stack_index_of_userdata); // get the environment table from the userdata object, [env_table new_function function_name class_userdata] 
	lua_getfield(lua_state, -1, "__fficlosures"); // [__fficlosures_table env_table new_function function_name class_userdata] 
	
	lua_pushstring(lua_state, method_name_in_objc); // function name, [function_name __fficlosures_table env_table new_function function_name class_userdata] 
	// creates a new userdata and leaves it on the stack
	LuaFFIClosureUserDataContainer* lua_ffi_closure_user_data;
	
	// Make sure the return pointers only get added to the struct if it is dynamic memory.
	// Otherwise, the destructor will attempt to call free() on memory that I don't own which is bad.
	if(true == used_dynamic_memory_for_return_type)
	{
		// Based on the bug found by Fjolnir, real_return_ptr needs to be NULL because it is always assigned from something else.
		// I think the pointer should be NULL to be set by FFISupport_ParseSupportFunctionReturnValueToFFIType.
		lua_ffi_closure_user_data = LuaFFIClosure_CreateNewLuaFFIClosure(lua_state, cif_ptr, real_args_ptr, flattened_args_ptr, custom_type_args_ptr, NULL, flattened_return_ptr, custom_type_return_ptr, imp_closure, parse_support, the_class);
	}
	else
	{
		lua_ffi_closure_user_data = LuaFFIClosure_CreateNewLuaFFIClosure(lua_state, cif_ptr, real_args_ptr, flattened_args_ptr, custom_type_args_ptr, NULL, NULL, NULL, imp_closure, parse_support, the_class);
	}

	// [imp_function function_name __fficlosures_table env_table new_function function_name class_userdata]
	
	lua_settable(lua_state, -3); // __methods[function_name] = function, [__fficlosures_table env_table new_function function_name class_userdata] 
	lua_pop(lua_state, 2); // pop __fficlosures and environment_table

	
	
	
	// Prepare the ffi_closure structure.
	error_status = ffi_prep_closure(imp_closure, cif_ptr, LuaSubclassBridge_GenericClosureCallback, lua_ffi_closure_user_data);
	// Handle the ffi_status error.
	if(FFI_OK != error_status)
	{
		// Handle the ffi_status error.
		if(FFI_BAD_TYPEDEF == error_status)
		{
			NSLog(@"ffi_prep_closure failed with FFI_BAD_TYPEDEF for function: %@", parse_support.keyName);			
		}
		else if(FFI_BAD_ABI == error_status)
		{
			NSLog(@"ffi_prep_closure failed with FFI_BAD_ABI for function: %@", parse_support.keyName);			
		}
		else
		{
			NSLog(@"ffi_prep_closure failed with unknown error for function: %@", parse_support.keyName);			
			
		}
		munmap(imp_closure, sizeof(imp_closure));

		free(flattened_return_ptr);
		free(custom_type_return_ptr);
		free(custom_type_args_ptr);
		free(flattened_args_ptr);
		free(real_args_ptr);
		free(cif_ptr);

		return NULL;
	}
	
	// Ensure that the closure will execute on all architectures.
	if(mprotect(imp_closure, sizeof(imp_closure), PROT_READ | PROT_EXEC) == -1)
	{
		// Check errno and handle the error.
		NSLog(@"mprotect for ffi_closure failed");
		munmap(imp_closure, sizeof(imp_closure));

		free(flattened_return_ptr);
		free(custom_type_return_ptr);
		free(custom_type_args_ptr);
		free(flattened_args_ptr);
		free(real_args_ptr);
		free(cif_ptr);

		return NULL;
	}
/*	
	NSLog(@"the_class:%s", class_getName(the_class));
	NSLog(@"the_selector:%s", sel_getName(the_selector));
*/
	// Will call addMethod or method_setImplementation depending on the situation
	
	class_replaceMethod(the_class, the_selector, (IMP)imp_closure, method_signature);

	// Track/record which lua_State(s) this is defined in.
	// Multple Lua states are allowed for convenience but all definitions must be the same since there is only one true Obj-C definition.
	[[LuaClassDefinitionMap sharedDefinitionMap] addLuaState:lua_state forClass:the_class forSelector:the_selector];

	return (IMP)imp_closure;
	
}

// -3 for userdata object
// -2 for index or key (function_name)
// -1 for new value (function)
bool LuaSubclassBridge_SetNewMethod(lua_State* lua_state)
{
#warning "Need to remove because is replaced by SetNewMethodAndSignature"
	// Because I will be pushing stuff on the stack, 
	// I will record the absolute positions of the items that were passed in
	// for easy reference.
	int top_of_stack = lua_gettop(lua_state);
	int stack_index_of_function = top_of_stack - 1 + 1;
	int stack_index_of_function_name = top_of_stack - 2 + 1;
	int stack_index_of_userdata = top_of_stack - 3 + 1;
	
	// Assumption: This is a Lua-only method.
	// I might be able to guess, but there is an ambiguity between class and instance methods
	// if both exist which I don't really want to deal with.
	
	if(lua_isfunction(lua_state, stack_index_of_function))
	{
		
//		NSLog(@"Found function, key is %s", lua_tostring(lua_state, stack_index_of_function_name));
		int top0 = lua_gettop(lua_state);
		
//		lua_checkstack(lua_state, 4);



		// stack: [new_function function_name class_userdata] 

		
		

			// Save the Lua function in the __methods env table so we can retrieve it when we need to actually invoke it.
			
			lua_getfenv(lua_state, stack_index_of_userdata); // get the environment table from the userdata object, [env_table new_function function_name class_userdata] 
			lua_getfield(lua_state, -1, "__methods"); // [__methods env_table new_function function_name class_userdata] 
			
			lua_pushvalue(lua_state, stack_index_of_function_name); // [function_name __methods env_table new_function function_name class_userdata]
			lua_pushvalue(lua_state, stack_index_of_function); // [lua_function function_name __methods env_table new_function function_name class_userdata]

			lua_settable(lua_state, -3); // __methods[function_name] = function, [__methods env_table new_function function_name class_userdata] 
			lua_pop(lua_state, 2); // pop __methods and environment_table

		
		
/*

		// If the object is a class, then we need to put the class in the global strong table so it won't be collected
		// if the user isn't currently referencing the object. The definition must persist since Obj-C categories and classes
		// will persist until the end of the program.
		// If the object is an instance, we don't need to put it into the strong table because if all references are removed,
		// we want it to be cleaned up.
		if(LuaObjectBridge_IsClass(lua_class_container))
		{
			LuaCocoaStrongTable_InsertObjectInGlobalStrongTable(lua_state, stack_index_of_userdata, LuaObjectBridge_GetClass(lua_class_container));
		}
*/
		int top1 = lua_gettop(lua_state);
		assert(top0 == top1);
		return true;
	}

	else if(lua_isnil(lua_state, stack_index_of_function))
	{
		NSLog(@"Removing a function is not implemented");
		// TODO: Remove the function. 
		// Also remove the signature entry,
		// If the entire method table is removed (and the ivar table), then it may be appropriate to remove the
		// class from the strong table if it is a non-Lua subclass (i.e. we just removed a category from a Obj-C class).
	}
	else
	{
		luaL_error(lua_state, "Type: %s not supported in LuaSubclassBridge_SetNewMethod", lua_typename(lua_state, stack_index_of_function));
	}

	
	return false;
}

#if 0
// -3 for userdata object
// -2 for index or key (function_name)
// -1 for new value (function)
bool LuaSubclassBridge_SetNewMethodSignature(lua_State* lua_state)
{
#warning "Need to remove because is replaced by SetNewMethodAndSignature"
	// Because I will be pushing stuff on the stack, 
	// I will record the absolute positions of the items that were passed in
	// for easy reference.
	int top_of_stack = lua_gettop(lua_state);
	int stack_index_of_signature = top_of_stack - 1 + 1;
	int stack_index_of_function_name = top_of_stack - 2 + 1;
	int stack_index_of_userdata = top_of_stack - 3 + 1;
	

	if(LuaObjectBridge_isnsstring(lua_state, stack_index_of_signature))
	{
		NSLog(@"Found function, key is %s", lua_tostring(lua_state, stack_index_of_function_name));
		int top0 = lua_gettop(lua_state);
		
		lua_checkstack(lua_state, 4);

		// stack: [new_function function_name class_userdata] 

		lua_getfenv(lua_state, stack_index_of_userdata); // get the environment table from the userdata object, [env_table new_function function_name class_userdata] 
		lua_getfield(lua_state, -1, "__signatures"); // [__signatures env_table new_function function_name class_userdata] 

		lua_pushvalue(lua_state, stack_index_of_function_name); // function name, [function_name __signatures env_table new_function function_name class_userdata] 
		lua_pushstring(lua_state, [LuaObjectBridge_tonsstring(lua_state, stack_index_of_signature) UTF8String]); // [signature function_name __signatures env_table new_function function_name class_userdata] 

		lua_settable(lua_state, -3); // __signatures[function_name] = function, [__signatures env_table new_function function_name class_userdata] 
//		lua_pop(lua_state, 3); // pop __methods, environment_table, and lua_class_proxy
		lua_pop(lua_state, 2); // pop __methods and environment_table
//		lua_pop(lua_state, 2); // pop environment_table, and lua_class_proxy
//		lua_pop(lua_state, 1); // pop environment_table

/*
		// I'm assuming the userdata is valid, not checking.
		LuaUserDataContainerForObject* lua_class_container = (LuaUserDataContainerForObject*)lua_touserdata(lua_state, stack_index_of_userdata);
		// If the object is a class, then we need to put the class in the global strong table so it won't be collected
		// if the user isn't currently referencing the object. The definition must persist since Obj-C categories and classes
		// will persist until the end of the program.
		// If the object is an instance, we don't need to put it into the strong table because if all references are removed,
		// we want it to be cleaned up.
		if(LuaObjectBridge_IsClass(lua_class_container))
		{
			LuaCocoaStrongTable_InsertObjectInGlobalStrongTable(lua_state, stack_index_of_userdata, LuaObjectBridge_GetClass(lua_class_container));
		}
*/
		int top1 = lua_gettop(lua_state);
		assert(top0 == top1);
		return true;
	}

	else if(lua_isnil(lua_state, stack_index_of_signature))
	{
		NSLog(@"Removing a function is not implemented");
		// TODO: Remove the function. 
		// Also remove the signature entry,
		// If the entire method table is removed (and the ivar table), then it may be appropriate to remove the
		// class from the strong table if it is a non-Lua subclass (i.e. we just removed a category from a Obj-C class).
	}
	else
	{
		luaL_error(lua_state, "Type: %s not supported in LuaSubclassBridge_SetNewMethodSignature", lua_typename(lua_state, stack_index_of_signature));
	}

	
	return false;
}
#endif

// TODO: Without prep_closure, we would have to pre-implement all the variations for the signatures we want to handle
#if 0
id LuaSubclassBridge_InvokeLuaMethod(id self, SEL _cmd)
{
	void* existing_lua_state = NULL;
	lua_State* lua_state = NULL;
	object_getInstanceVariable(self, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, &existing_lua_state);
	if(NULL == existing_lua_state)
	{
		// fallback, get from database
		lua_state = [[LuaClassDefinitionMap sharedDefinitionMap] anyLuaStateForSelector:_cmd inClass:[self class]];
	}
	else
	{
		lua_state = (lua_State*)existing_lua_state;
	}
	if(NULL == lua_state)
	{
		NSLog(@"Can't find lua state for %@, %@", self, NSStringFromSelector(_cmd));
		return nil;
	}
	// TODO: Go to global weak table and retrive based on the key: self
	// Find a Lua method for that object and selector (remember it could be a special case per-instance method)
	// Once we have the function, arrange all the parameters so we can call it
	// Handle the return value. Should only be 0 or 1 return value, though we also need to worry about non-id return types.
	
	void* return_value = LuaCocoaWeakTable_GetObjectInGlobalWeakTable(lua_state, self);
	if(NULL == return_value)
	{
		NSLog(@"Error: Expected to find key object in GlobalWeakTable but didn't: %@ in _cmd:%@", self, NSStringFromSelector(_cmd));
		NSLog(@"real class is %@:", NSStringFromClass(object_getClass(self)));

//		return nil;
//		return objc_msgSend(self, _cmd);
		// How do I know if I need to call super or not? (self puts me in infinite loop)
		struct objc_super super_data = { self, [self superclass] };
		return objc_msgSendSuper(&super_data, _cmd);
	}
	LuaUserDataContainerForObject* lua_object_container = LuaObjectBridge_LuaCheckClass(lua_state, -1);
	bool did_find_lua_method = LuaSubclassBridge_FindLuaMethod(lua_state, lua_object_container, sel_getName(_cmd));
	if(did_find_lua_method)
	{
		// Move the function below the userdata
		lua_insert(lua_state, -2);
		
		lua_call(lua_state, 1, 1);
		
		// hmmmm, if I pop, it won't be in lua any more. Hope this isn't a problem
		id return_value = LuaObjectBridge_checkid(lua_state, -1);
		lua_pop(lua_state, 1); // pop return value
		return return_value;
	}
	else
	{
		NSLog(@"Couldn't find lua method");
		lua_pop(lua_state, 1); // pop LuaCocoaWeakTable_GetObjectInGlobalWeakTable
		return nil;
	}

	
}
#endif


// -3 for userdata object
// -2 for index or key (function_name)
// -1 for new value (array containing function and method signature)
bool LuaSubclassBridge_SetNewMethodAndSignature(lua_State* lua_state)
{
	// Because I will be pushing stuff on the stack, 
	// I will record the absolute positions of the items that were passed in
	// for easy reference.
	int top_of_stack = lua_gettop(lua_state);
	int stack_index_of_array = top_of_stack - 1 + 1;
	int stack_index_of_function_name = top_of_stack - 2 + 1;
	int stack_index_of_userdata = top_of_stack - 3 + 1;
	

	if(lua_istable(lua_state, stack_index_of_array))
	{
		// We are going to call SetNewMethod, but it requires the stack to be ordered in a certain way.
		// So we will push some copies of parameters before we extract the function in the array.
//		lua_checkstack(lua_state, 3);
		lua_checkstack(lua_state, 2);
//		lua_pushvalue(lua_state, stack_index_of_userdata); // [class_userdata array function_name class_userdata]
//		lua_pushvalue(lua_state, stack_index_of_function_name); // [function_name class_userdata array function_name class_userdata]
		lua_rawgeti(lua_state, stack_index_of_array, 1); // array[1]
		// stack: [function function_name class_userdata array function_name class_userdata]
		
		
		
		lua_rawgeti(lua_state, stack_index_of_array, 2); // array[2]

		// Note: signature is expected to include the + or - symbol at the beginning to denote class or instance method.
		// stack: [signature function function_name class_userdata array function_name class_userdata]
		// or
		// stack: [function signature function_name class_userdata array function_name class_userdata]

		int stack_index_of_lua_function = 0;
		int stack_index_of_lua_signature = 0;
		
		// Compute the absolute indices for the function and signature
		if(lua_isfunction(lua_state, -2) && lua_isstring(lua_state, -1))
		{
			stack_index_of_lua_function = lua_gettop(lua_state) -2 + 1;
			stack_index_of_lua_signature = lua_gettop(lua_state) -1 + 1;
		}
		else if(lua_isfunction(lua_state, -1) && lua_isstring(lua_state, -2))
		{
			stack_index_of_lua_function = lua_gettop(lua_state) -1 + 1;
			stack_index_of_lua_signature = lua_gettop(lua_state) -2 + 1;			
		}
		else
		{
			return luaL_error(lua_state, "Setting a new method expects an array containing a lua function and a string containing the method signature.");
		}

		
		/* New technique:
		 I want to use ffi_prep_closure and class_addMethod.
		 If the method name already exists in Objective-C, then we want to use the existing method signature
		 and use the Obj-C runtime to register the new method. 
		 The method may exist because it is defined in the superclass, it is a category, or maybe we want to redefine it.
		 
		 If the method does not already exist, we need a method signature to register it in Obj-C.
		 The advantage of this is that once registered, invoking from Obj-C should just work as normal.
		 
		 If we do not have a method signature, then things get tricky and imperfect. 
		 The advantage is that when calling directly from Lua, we can use variable number of arguments 
		 and multiple return values. The disadvantage is that these methods probably cannot be directly invoked
		 from Objective-C. (I think we may be able to invoke via a lua_call.)
		 
		 Since this function doesn't have a signature provided, we can try to look it up.
		 We can use BridgeSupport or we can query the runtime directly.
		 
		 Let's simplify this though. Let's check the runtime to see if we can find this method.
		 If this method exists in the runtime, then there is a method signature.
		 We don't need bridge support because we are not yet converting actual values through the bridge.
		 
		 If the method doesn't exist in the runtime, then we add it to a list of lua-only methods.
		 I thought about adding a stub implementation that always takes 1 object as a parameter so the Obj-C
		 can know about and invoke this method, but I'm worried it might mess up attempts to invoke the method
		 with variable and non-object types of parameters when calling from the Lua side.
		 Also, if I don't add a stub implementation to Obj-C, this might make it possible to add a method on a per-instance
		 basis instead of a per-class basis. Not sure if this is useful, but it is interesting.
		 */
		
					
		const char* function_name_in_lua = lua_tostring(lua_state, stack_index_of_function_name);
		size_t max_str_length = strlen(function_name_in_lua)+2;
		
		char method_name_in_objc[max_str_length];
		const char* method_signature = NULL;
		SEL the_selector = NULL;
		Method the_method;
		IMP imp_closure = NULL;
		
		bool is_class_method;
		// e.g. "-@@:"
		// instance method, returns id, parameters id(self), cmd
		const char* lua_signature_string = lua_tostring(lua_state, stack_index_of_lua_signature);
		size_t length_of_lua_signature_string = strlen(lua_signature_string);
		if(length_of_lua_signature_string < 1)
		{
			return luaL_error(lua_state, "Signature string (in setting a new method) requires at least 1 character specifying if the method is a class or instance.");
		}
		// This buffer will contain the signature string minus the +/- character.
		// We don't need to add 1 for the '\0' since we can use the +/- character space for that.
//		char temporary_method_signature_buffer[length_of_lua_signature_string];



		if('-' == lua_signature_string[0])
		{
			is_class_method = false;
		}
		else if('+' == lua_signature_string[0])
		{
			is_class_method = true;
		}
		else
		{
			return luaL_error(lua_state, "First character in signature string (in setting a new method) must be + or -");
		}

		
		// First we are going to look to see if the method already exists in the Obj-C runtime (probably from a super-class).
		// Note that if it exists, we ignore the user provided method signature.
		// It is not possible to change the method signature.
		
		bool found_method_in_objc = false;
		// I'm assuming the userdata is valid, not checking.
		LuaUserDataContainerForObject* lua_class_container = (LuaUserDataContainerForObject*)lua_touserdata(lua_state, stack_index_of_userdata);
		if(LuaObjectBridge_IsClass(lua_class_container))
		{
			the_method = ObjectSupport_ConvertUnderscoredSelectorToObjCAndGetMethod(method_name_in_objc, function_name_in_lua, max_str_length, lua_class_container->theObject, false, &the_selector, is_class_method);
			if(NULL != the_method)
			{
				found_method_in_objc = true;										
			}
		}
		else
		{
			the_method = ObjectSupport_ConvertUnderscoredSelectorToObjCAndGetMethod(method_name_in_objc, function_name_in_lua, max_str_length, lua_class_container->theObject, true, &the_selector, is_class_method);
			if(NULL != the_method)
			{
				// I don't think it is a good idea to allow setting a method on a per-instance basis,
				// at least for methods defined in the Obj-C runtime.
				// (Maybe Lua-only methods are more reasonable?)
				return luaL_error(lua_state, "Setting a method on an instance (not a class) that is registered in Objective-C is not supported.");
			}
		}
		
#if 0
		// I read that I should ignore these numbers anyway because they are unreliable.
		// This is too complicated, so I am going to trust the user provided signature completely.

		if(true == found_method_in_objc)
		{
			// method_getTypeEncoding returns stange numbers in the signature which mess up my other code.
			method_signature = method_getTypeEncoding(the_method);

		}
		else
		{
			// This is a brand new method we are going to register into Obj-C.
			// Since we don't have an existing method signature, we need to use the user provided one.
			
			// We need to 'remove' the +/- character.
			// We can use a new pointer to start pointing at the second character of the string.
			method_signature = &lua_signature_string[1];
		}
#else	
		// We need to 'remove' the +/- character.
		// We can use a new pointer to start pointing at the second character of the string.
		method_signature = &lua_signature_string[1];
#endif
					
		ParseSupport* parse_support = nil;
		imp_closure = LuaSubclassBridge_CreateAndSetFFIClosureForSetMethod(lua_state, lua_class_container->theObject, method_name_in_objc, the_selector, method_signature, &parse_support, stack_index_of_userdata);
		
		if(NULL == imp_closure)
		{
			return luaL_error(lua_state, "Creating new IMP failed.");
		}
		
		
		
		// Save the Lua function in the __methods env table so we can retrieve it when we need to actually invoke it.

		lua_getfenv(lua_state, stack_index_of_userdata); // get the environment table from the userdata object, [env_table new_function function_name class_userdata] 
		lua_getfield(lua_state, -1, "__methods"); // [__methods env_table new_function function_name class_userdata] 
		
		lua_pushvalue(lua_state, stack_index_of_function_name); // [function_name __methods env_table new_function function_name class_userdata]
		lua_pushvalue(lua_state, stack_index_of_lua_function); // [lua_function function_name __methods env_table new_function function_name class_userdata]
		
		lua_settable(lua_state, -3); // __methods[function_name] = function, [__fficlosures_table env_table new_function function_name class_userdata] 
		lua_pop(lua_state, 2); // pop __methods and environment_table
		
	
		
	
	
		
		
		// reset the stack
		// pop array[1], array[2]
		lua_pop(lua_state, 2);
		
		
			
		/*	
		// If the object is a class, then we need to put the class in the global strong table so it won't be collected
		// if the user isn't currently referencing the object. The definition must persist since Obj-C categories and classes
		// will persist until the end of the program.
		// If the object is an instance, we don't need to put it into the strong table because if all references are removed,
		// we want it to be cleaned up.
		if(LuaObjectBridge_IsClass(lua_class_container))
		{
			LuaCocoaStrongTable_InsertObjectInGlobalStrongTable(lua_state, stack_index_of_userdata, LuaObjectBridge_GetClass(lua_class_container));
		}
		*/
		int top1 = lua_gettop(lua_state);
		assert(top_of_stack == top1);
		return true;
			
		
	}
	else
	{
		luaL_error(lua_state, "Type: %s not supported in LuaSubclassBridge_SetNewMethodAndSignature", lua_typename(lua_state, stack_index_of_array));
	}
	return false;
}


// Will return function on top of stack (need to pop) or nothing on top of stack if not found (don't pop)
// is_instance_defined currently unused/unimplemented

bool LuaSubclassBridge_FindLuaMethodInClass(lua_State* lua_state, Class starting_class, const char* method_name, Class* which_class_found, bool* is_instance_defined)
{
	bool found_lua_method = false;
	is_instance_defined = false;
	*which_class_found = NULL;
	size_t method_string_length = strlen(method_name);
	// Add 2: 1 for null character, 1 for possible last underscore that was omitted by scripter
	//	char objc_method_name[method_string_length+2];
	
	char method_name_with_underscores[method_string_length+1];
	
	strlcpy(method_name_with_underscores, method_name, method_string_length+1);
	
	// Replace all underscores with colons
	for(size_t char_index=0; char_index<method_string_length; char_index++)
	{
		if(':' == method_name[char_index])
		{
			method_name_with_underscores[char_index] = '_';
		}
	}
	//	NSLog(@"method_name_with_underscores:%s", method_name_with_underscores);
	
	int top0 = lua_gettop(lua_state);
	
	Class the_class = starting_class;
	do
	{
		
		
		
		//			NSLog(@"class: %@", NSStringFromClass(the_class));
		
		//		LuaSubClassBridge_LuaClassProxy* lua_class_proxy = (LuaSubClassBridge_LuaClassProxy*)LuaCocoaStrongTable_GetObjectInGlobalStrongTable(lua_state, the_class);
		void* ret_object = LuaCocoaStrongTable_GetObjectInGlobalStrongTable(lua_state, the_class); // [class_userdata]
		if(NULL == ret_object)
		{
			// Assumption: Only classes in the global strong table have custom methods.
			// These could be Lua subclasses or categories added in Lua.
			// Pop the nil and try next loop.
			lua_pop(lua_state, 1);
			continue;
		}
		lua_getfenv(lua_state, -1); // [env_table, class_userdata]
		
		lua_getfield(lua_state, -1, "__methods"); // [__methods_table env_table class_userdata] 
		
		
		lua_getfield(lua_state, -1, method_name_with_underscores); // pushes __methods[function_name] which should be a function, 
		if(lua_isfunction(lua_state, -1))
		{
			// [function __methods_table env_table class_userdata]
			//				NSLog(@"Got function!");
			
			found_lua_method = true;
			lua_replace(lua_state, -4); // takes the top item and replaces the item at index -3 with it and pops, [__methods_table env_table function]
			lua_pop(lua_state, 2); // make sure the stack only has [function] on top when we're done
			*which_class_found = the_class;
			break;
		}
		else
		{
			// [something __methods_table env_table class_userdata] 
			lua_pop(lua_state, 4);
			
			int top1 = lua_gettop(lua_state);
			assert(top0 == top1);
		}
	} while(NULL != (the_class = ObjectSupport_GetSuperClassFromClass(the_class)));
	
	
	return found_lua_method;
}



// Will return function on top of stack (need to pop) or nothing on top of stack if not found (don't pop)
bool LuaSubclassBridge_FindLuaMethod(lua_State* lua_state, LuaUserDataContainerForObject* lua_class_container, const char* method_name, Class* which_class_found, bool* is_instance_defined)
{
	return LuaSubclassBridge_FindLuaMethodInClass(lua_state, LuaObjectBridge_GetClass(lua_class_container), method_name, which_class_found, is_instance_defined);
}


// Will return function on top of stack (need to pop) or nothing on top of stack if not found (don't pop)
const char* LuaSubclassBridge_FindLuaSignature(lua_State* lua_state, LuaUserDataContainerForObject* lua_class_container, const char* method_name)
{
	bool found_lua_signature = false;
	
	int top0 = lua_gettop(lua_state);
	
	
	size_t method_string_length = strlen(method_name);
	// Add 2: 1 for null character, 1 for possible last underscore that was omitted by scripter
	//	char objc_method_name[method_string_length+2];
	
	char method_name_with_underscores[method_string_length+1];
	
	strlcpy(method_name_with_underscores, method_name, method_string_length+1);
	
	// Replace all underscores with colons
	for(size_t char_index=0; char_index<method_string_length; char_index++)
	{
		if(':' == method_name[char_index])
		{
			method_name_with_underscores[char_index] = '_';
		}
	}
	
	
	Class the_class = LuaObjectBridge_GetClass(lua_class_container);
	do
	{
		
		
		
//		NSLog(@"class: %@", NSStringFromClass(the_class));
		
		//		LuaSubClassBridge_LuaClassProxy* lua_class_proxy = (LuaSubClassBridge_LuaClassProxy*)LuaCocoaStrongTable_GetObjectInGlobalStrongTable(lua_state, the_class);
		void* ret_object = LuaCocoaStrongTable_GetObjectInGlobalStrongTable(lua_state, the_class); // [class_userdata]
		if(NULL == ret_object)
		{
			// Assumption: Only classes in the global strong table have custom methods.
			// These could be Lua subclasses or categories added in Lua.
			// Pop the nil and try next loop.
			lua_pop(lua_state, 1);
			continue;
		}
		lua_getfenv(lua_state, -1); // [env_table, class_userdata]
		
		lua_getfield(lua_state, -1, "__signatures"); // [__signatures env_table class_userdata] 
		
		
		lua_getfield(lua_state, -1, method_name_with_underscores); // pushes __signatures[function_name] which should be a string, 
		if(lua_isstring(lua_state, -1))
		{
			// [function __methods_table env_table class_userdata]
//			NSLog(@"Got string!");
			found_lua_signature = true;
			lua_replace(lua_state, -4); // takes the top item and replaces the item at index -3 with it and pops, [__signatures env_table function]
			lua_pop(lua_state, 2); // make sure the stack only has [string] on top when we're done
			break;
		}
		else
		{
			// [something __methods_table env_table class_userdata] 
			lua_pop(lua_state, 4);
			//			lua_pop(lua_state, 3);
			/*
			 if(lua_class_container->isSuper)
			 {
			 lua_pop(lua_state, 1);
			 
			 }
			 */
			int top1 = lua_gettop(lua_state);
			assert(top0 == top1);
		}
	} while(NULL != (the_class = ObjectSupport_GetSuperClassFromClass(the_class)));
	
	
	if(true == found_lua_signature)
	{
		return lua_tostring(lua_state, -1);
	}
	else
	{
		return NULL;
	}

}


Class LuaSubclassBridge_InternalCreateClass(lua_State* lua_state, const char* new_class_name, Class parent_class)
{
	// First, make sure the class doesn't already exist.
	// FIXME: Since Obj-C is global/shared, in the case of multiple Lua states that wish to define the same class,
	// we need to allow this test to pass through if the class already exists and make sure the LuaProxy stuff is created.
	Class new_class = objc_getClass(new_class_name);
	if(nil != new_class)
	{	
		// verify the same parent class exists
		if(class_getSuperclass(new_class) != parent_class)
		{
			luaL_error(lua_state, "Error: Class: %s is redefined and with different parent classes: %s, %s", new_class_name, class_getName(class_getSuperclass(new_class)), class_getName(parent_class));
			return NULL;
		}
		
		// I used to return an error for classes being redefined in the same Lua state, but not if redefined from different Lua states to help multiple Lua states and relaunching scenarios.
		// But after changing to track on a per-selector basis instead of classes, it is easier to not check at all.
		// Remember, all implementations must be identical.
		/*
		if([[LuaClassDefinitionMap sharedDefinitionMap] isClassDefined:new_class inLuaState:lua_state])
		{
			luaL_error(lua_state, "Error: Class: %s is redefined in the same lua_State", new_class_name);
			return NULL;
		}
		*/
		
		// return the existing class since it already exists
		return new_class;
	}
	
	// Make sure the parent class exists
	if(nil == parent_class)
	{
		return nil;
	}
	
	// Create the new class.
	new_class = objc_allocateClassPair(parent_class, new_class_name, 0);
	
	
	// TODO: Add extra size bytes for ivars and lua_State
	// Only add on classes that don't have the Lua special data
	// (i.e. subclasses of Lua subclasses will already have this data, so don't add again)
	bool has_lua_state = class_getInstanceVariable(parent_class, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER);
	if(false == has_lua_state)	
	{
		// What is this? Are we going to use luaL_ref to hold a table?
		class_addIvar(new_class, LUA_SUBCLASS_BRIDGE_IVAR_FOR_STATE_AND_UNIQUE_IDENTIFIER, sizeof(lua_State*), log2(sizeof(lua_State*)), "^");
		
		// For finalizers, I am concerned about non-origin-thread clean up. I need an ivar to track which thread the Lua state belongs to.
		class_addIvar(new_class, LUA_SUBCLASS_BRIDGE_IVAR_FOR_ORIGIN_THREAD, sizeof(lua_State*), log2(sizeof(lua_State*)), "^");
		
		// What is this? Are we going to use luaL_ref to hold a table?
		//		class_addIvar(new_class, "__ivars", sizeof(int), log2(sizeof(int)), "i");
	}
	
	
	// Finish creating class
	objc_registerClassPair(new_class);
	
	
	
	// If this class is a new Lua class (not a subclass of another Lua class
	// then we need to override some of the methods for special handling.
	// Don't do this if it is a subclass of a Lua class or we may mess up a user's custom implementation
	if(false == has_lua_state)	
	{
		//		BOOL ret_flag;
		/*		
		 ret_flag = class_addMethod(object_getClass(new_class), @selector(alloc), (IMP)LuaSubclassBridge_alloc, "@#:");
		 if(NO == ret_flag)
		 {
		 NSLog(@"class_addMethod failed for alloc"); 
		 }
		 */
		// Do I need this?
		/*
		 ret_flag = class_addMethod(object_getClass(new_class), @selector(allocWithZone:), (IMP)LuaSubclassBridge_allocWithZone, "@#:@");
		 if(NO == ret_flag)
		 {
		 NSLog(@"class_addMethod failed for allocWithZone"); 
		 }
		 */
		/*
		 ret_flag = class_addMethod(new_class, @selector(init), (IMP)LuaSubclassBridge_init, "@@:");
		 if(NO == ret_flag)
		 {
		 NSLog(@"class_addMethod failed for init"); 
		 }
		 */
		/*
		 ret_flag = class_addMethod(new_class, @selector(initWithLuaCocoaState:), (IMP)LuaSubclassBridge_initWithLuaCocoaState, "@@:^");
		 if(NO == ret_flag)
		 {
		 NSLog(@"class_addMethod failed for initWithLuaCocoaState:"); 
		 }
		 */
		/*
		 // Add dealloc
		 ret_flag = class_addMethod(new_class, @selector(dealloc), (IMP)LuaSubclassBridge_dealloc, "v@:");
		 if(NO == ret_flag)
		 {
		 NSLog(@"class_addMethod failed for dealloc"); 
		 }
		 #ifdef __OBJC_GC__
		 // GC finalize
		 NSLog(@"finalize add");
		 ret_flag = class_addMethod(new_class, @selector(finalize), (IMP)LuaSubclassBridge_finalize, "v@:");	
		 if(NO == ret_flag)
		 {
		 NSLog(@"class_addMethod failed for finalize"); 
		 }
		 #endif
		 ret_flag = class_addMethod(new_class, @selector(forwardInvocation:), (IMP)LuaSubclassBridge_forwardInvocation, "v@:@");
		 if(NO == ret_flag)
		 {
		 NSLog(@"class_addMethod failed for forwardInvocation:"); 
		 }
		 
		 ret_flag = class_addMethod(new_class, @selector(methodSignatureForSelector:), (IMP)LuaSubclassBridge_methodSignatureForSelector, "@@::");
		 if(NO == ret_flag)
		 {
		 NSLog(@"class_addMethod failed for methodSignatureForSelector:"); 
		 }
		 //		class_addMethod(new_class, @selector(methodSignatureForSelector:), (IMP)methodSignatureForSelector, "@@::");
		 */
		 // Warning: Adding methods like this cannot be overriden safely because calls to super will result in infinite recursion.
		 // I expect that none of these methods will never be overridden.
		class_addMethod(new_class, @selector(setLuaCocoaState:), (IMP)LuaSubclassBridge_setLuaCocoaState, "v@:^");
		class_addMethod(new_class, @selector(luaCocoaState), (IMP)LuaSubclassBridge_luaCocoaState, "^@:");
		class_addMethod(new_class, @selector(cleanupLuaCocoaInstance), (IMP)LuaSubclassBridge_cleanupLuaCocoaInstance, "v@:");
		
		// Not sure if I really need to add these. I don't think I do because I don't actually subclass these in Lua.
		/*
		[[LuaClassDefinitionMap sharedDefinitionMap] addLuaState:lua_state forClass:new_class forSelector:@selector(setLuaCocoaState:)];
		[[LuaClassDefinitionMap sharedDefinitionMap] addLuaState:lua_state forClass:new_class forSelector:@selector(luaCocoaState:)];
		[[LuaClassDefinitionMap sharedDefinitionMap] addLuaState:lua_state forClass:new_class forSelector:@selector(cleanupLuaCocoaInstance:)];
		*/
		
	}
	return new_class;
}



int LuaSubclassBridge_CreateClass(lua_State* lua_state)
{
	int number_of_arguments = lua_gettop(lua_state);
	
	NSString* new_class_name = LuaObjectBridge_checknsstring(lua_state, 1);
	
	Class parent_class = nil;
	if(LuaObjectBridge_isidclass(lua_state, 2))
	{
		parent_class = (Class)LuaObjectBridge_toid(lua_state, 2);
	}
	else
	{
		NSString* parent_class_name = LuaObjectBridge_checknsstring(lua_state, 2);
		parent_class = objc_getClass([parent_class_name UTF8String]);
	}
	if(nil == parent_class)
	{
		return luaL_error(lua_state, "LuaSubclassBridge_CreateClass did not get valid parent class");
	}
	
	Class new_class = LuaSubclassBridge_InternalCreateClass(lua_state, [new_class_name UTF8String], parent_class);
	if(nil == new_class)
	{
		// Currently, we fail only when the parent class does not exist
		return 0;
	}
	else
	{
		// Two things need to happen.
		// I need to push the class into the global weak table to be returned so the user can use it.
		// I need to store a strong reference in the global strong table so the object will not be collected,
		// even when all active Lua references are gone. This is because once Obj-C classes are registered,
		// there doesn't seem to be a way to unregister them.
		// NOTE: This may look like a leak, but I don't think classes are allowed to be removed once registered.
		// So this is going to sit in memory until the Lua state is closed.
		
		// Puts class in weak table and on top of stack to be returned
		LuaObjectBridge_PushClass(lua_state, new_class);
		
		// Insert into a strong global table because we want to be able to find this object and prevent it from being collected.
		LuaCocoaStrongTable_InsertObjectInGlobalStrongTable(lua_state, -1, new_class);
		
		
		// Get the container for the class that was created by PushClass so we can mark this as a Lua subclass
		// just in case we want to know.
		LuaUserDataContainerForObject* class_container = (LuaUserDataContainerForObject*)lua_touserdata(lua_state, -1);
		class_container->isLuaSubclass = true;
		
		// I used to track class definitions per Lua state. But I realized per-selector made more sense because of categories.
		// However, for object initialization from Obj-C, it is convenient to know whether the Lua state is still alive so I need to register something.
		// So I will register 'alloc' as a placeholder.
		[[LuaClassDefinitionMap sharedDefinitionMap] addLuaState:lua_state forClass:new_class forSelector:@selector(alloc)];
		
		// Special implementions for dealloc and finalize to make sure objects are removed from the GlobalStrongTable
		LuaSubclassBridge_CreateAndSetFFIClosureForDeallocFinalize(lua_state, new_class, "dealloc", @selector(dealloc), -1);
		LuaSubclassBridge_CreateAndSetFFIClosureForDeallocFinalize(lua_state, new_class, "finalize", @selector(finalize), -1);
		
		
		
		// Now add optional protocols
		// FIXME: Support tables as well as valist?
		// Assumption: parameter 3 and beyond go to protocols
		// Remember that LuaSubclassBridge_InternalCreateClass has already pushed a return value on the top of the stack
		// so don't process that one as a protocol
		for(int i = 3; i <= number_of_arguments; i++)
		{
			Protocol* current_protocol = objc_getProtocol(luaL_checkstring(lua_state, i));
			if(NULL == current_protocol)
			{ 
				luaL_error(lua_state, "Could not find protocol named '%s'", current_protocol);				
			}
			class_addProtocol(new_class, current_protocol);
		}
		
		
		return 1;
	}
}

// 1 or -3 for userdata object
// 2 or -2 for index or key
// 3 or -1 for new value
bool LuaCategoryBridge_SetCategoryWithMethodAndSignature(lua_State* lua_state)
{
	LuaUserDataContainerForObject* lua_class_container = LuaObjectBridge_LuaCheckClass(lua_state, 1);
	Class the_class = LuaObjectBridge_GetClass(lua_class_container);
	// This is very similar to subclassing. I need a place to store the mapping of Lua functions for the overridden Obj-C methods.
	// I need to store a strong reference in the global strong table so the object will not be collected,
	// even when all active Lua references are gone. This is because once Obj-C classes are registered,
	// there doesn't seem to be a way to unregister them.
	// NOTE: This may look like a leak, but I don't think classes are allowed to be removed once registered.
	// So this is going to sit in memory until the Lua state is closed.
	// Insert into a strong global table because we want to be able to find this object and prevent it from being collected.
	LuaCocoaStrongTable_InsertObjectInGlobalStrongTable(lua_state, 1, the_class);
	
	// Shoot. I already forgot how this all worked. But it seems that I don't need the subclass environment table for this.
/*	
	LuaSubclassBridge_CreateNewLuaSubclassEnvironmentTable(lua_state);
	LuaCocoaStrongTable_InsertLuaSubclassEnvironmentTableInGlobalStrongTable(lua_state, -1, the_class);
	lua_pop(lua_state, 1);
*/	
	
	
	// The remaining code should be the same as subclass
	return LuaSubclassBridge_SetNewMethodAndSignature(lua_state);
}

bool LuaCategoryBridge_SetNewMethod(lua_State* lua_state)
{
	LuaUserDataContainerForObject* lua_class_container = LuaObjectBridge_LuaCheckClass(lua_state, 1);
	Class the_class = LuaObjectBridge_GetClass(lua_class_container);
	// This is very similar to subclassing. I need a place to store the mapping of Lua functions for the overridden Obj-C methods.
	// I need to store a strong reference in the global strong table so the object will not be collected,
	// even when all active Lua references are gone. This is because once Obj-C classes are registered,
	// there doesn't seem to be a way to unregister them.
	// NOTE: This may look like a leak, but I don't think classes are allowed to be removed once registered.
	// So this is going to sit in memory until the Lua state is closed.
	// Insert into a strong global table because we want to be able to find this object and prevent it from being collected.
	LuaCocoaStrongTable_InsertObjectInGlobalStrongTable(lua_state, -1, the_class);
	
	// The remaining code should be the same as subclass
	return LuaSubclassBridge_SetNewMethod(lua_state);
}

/*
 static const struct luaL_reg LuaSelectorBridge_MethodsForSelectorMetatable[] =
 {
 // Don't think I need much for selectors.
 {"__tostring", LuaSelectorBridge_ToString},
 //	{"__call", LuaSelectorBridge_Call},
 // For __eq, since we use the global weak table to unique things, I think the default comparison will just work.
 // If not, I think I read Obj-C makes SEL's unique so it is just a simple pointer comparison there too.
 //	{"__eq", LuaSelectorBridge_IsEqual},
 // I don't have to worry about memory management with selectors
 //	{"__gc", LuaSelectorBridge_GarbageCollect},
 {NULL,NULL},
 };
 */

static const luaL_reg LuaSubclassBridge_LuaFunctions[] = 
{
	{"CreateClass", LuaSubclassBridge_CreateClass},
	
	{NULL,NULL},
};


int luaopen_LuaSubclassBridge(lua_State* lua_state)
{
	//	luaL_newmetatable(lua_state, LUACOCOA_SUBCLASS_METATABLE_ID);
	//	lua_pushvalue(lua_state, -1);
	//	lua_setfield(lua_state, -2, "__index");
	//	luaL_register(lua_state, NULL, LuaSelectorBridge_MethodsForSelectorMetatable);
	
	luaL_register(lua_state, "LuaCocoa", LuaSubclassBridge_LuaFunctions);
	
	
	return 1;
}

