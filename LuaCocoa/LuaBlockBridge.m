//
//  LuaBlockBridge.m
//  LuaCocoa
//
//  Created by Eric Wing on 2/18/12.
//  Copyright (c) 2012 PlayControl Software, LLC. All rights reserved.
//

#import "LuaBlockBridge.h"

#include <ffi/ffi.h>
#include <sys/mman.h>   // for mmap()
#include <dispatch/dispatch.h>

#import <objc/objc.h>
#import <objc/runtime.h>
#import <Foundation/Foundation.h>

#include "lua.h"
#include "lauxlib.h"

#include "LuaFFISupport.h"
#import "LuaObjectBridge.h"
//#import "LuaSelectorBridge.h"
#import "LuaStructBridge.h"
#import "LuaSubclassBridge.h" // reusing ffi/lua argument parsing/pushing
#import "LuaCocoaStrongTable.h"
#import "LuaCocoaWeakTable.h"
#import "LuaCocoaAvailableLuaStates.h"

#import "ParseSupportFunction.h"
#import "ParseSupportStruct.h"


static const char* s_someStaticContstantValueForSetAssociatedBlock = "s_someStaticContstantValueForSetAssociatedBlock";
@class LuaCocoaBlockDataForCleanupForLuaCreatedBlock;
static void LuaBlockBridge_InvokeGenericClosureCallback(ffi_cif* the_cif, void* return_result, void** args_from_ffi, LuaCocoaBlockDataForCleanupForLuaCreatedBlock* closure_user_data);

// Helper to deal with finalize in LuaCocoaBlockDataForCleanupForLuaCreatedBlock
@interface LuaCocoaBlockPointersForFinalizeCleanup : NSObject
{
	lua_State* luaState;
	void* theBlock;
	void* theObject; // intended LuaCocoaBlockDataForCleanupForLuaCreatedBlock instance
}
@property(nonatomic, readonly, assign) lua_State* luaState;
@property(nonatomic, readonly, assign) void* theBlock;
@property(nonatomic, readonly, assign) void* theObject;

- (id) initWithLuaState:(lua_State*)lua_state blockPointer:(void*)the_block objectPointer:(void*)the_object;
@end

@implementation LuaCocoaBlockPointersForFinalizeCleanup

@synthesize luaState;
@synthesize theBlock;
@synthesize theObject;

- (id) initWithLuaState:(lua_State*)lua_state blockPointer:(void*)the_block objectPointer:(void*)the_object
{
	self = [super init];
	if(nil != self)
	{
		luaState = lua_state;
		theBlock = the_block;
		theObject = the_object;
	}
	return self;
}

@end

// This class is the base class for LuaCocoaBlockDataForCleanupForLuaCreatedBlock.
// Originally, this was just one class, but I wanted a way to set associated parse support data for pure-Obj-C created blocks while using the same code paths.
// By simply refactoring and making a simple base class, I can easily distinguish between Lua-created blocks and Obj-C created blocks and use the same code paths.
@interface LuaCocoaBlockDataForCleanup : NSObject
{
	ParseSupportFunction* parseSupport;

}
@property(nonatomic, readonly, retain) ParseSupportFunction* parseSupport;
- (id) initWithParseSupport:(ParseSupportFunction*)parse_support;
- (void) dealloc;
- (void) finalize;

@end

@implementation LuaCocoaBlockDataForCleanup

@synthesize parseSupport;

- (id) initWithParseSupport:(ParseSupportFunction*)parse_support
{
	self = [super init];
	if(nil != self)
	{
		parseSupport = parse_support;
		// Safety check
		if(nil != parseSupport)
		{
			CFRetain(parseSupport);		
		}
	}
	return self;
}

- (void) dealloc
{
	if(NULL != parseSupport)
	{
		CFRelease(parseSupport);
	}
	[super dealloc];
}

- (void) finalize
{
	if(NULL != parseSupport)
	{
		CFRelease(parseSupport);
	}
	[super finalize];
}

@end

@interface LuaCocoaBlockDataForCleanupForLuaCreatedBlock : LuaCocoaBlockDataForCleanup
{
@private
	ffi_cif* luaFFICif;
	ffi_type** luaFFIRealArgs;
	ffi_type** luaFFIFlattenedArgs;
	ffi_type* luaFFICustomTypeArgs;
	
	ffi_type* luaFFIRealReturnArg;
	ffi_type** luaFFIFlattenedReturnArg;
	ffi_type* luaFFICustomTypeReturnArg;
	
	ffi_closure* luaFFIClosure;

	// Because Lua is not compiled with thread locking by default,
	// we must take care to prevent blocks from calling Lua back on a different thread.
	// When the block is created, we will get the current queue and presume this is the queue that is safe to call Lua back on.
	NSThread* originThread;
	struct lua_State* luaState;
	void* theBlock; // Don't use the __weak modifier. I am trying to avoid zeroing weak references because I need the address for a Lua map lookup. But don't retain either or we get a circular reference.
}

@property(nonatomic, readonly, retain) NSThread* originThread;
@property(nonatomic, readonly, assign) lua_State* luaState;
@property(nonatomic, readonly, assign) ffi_closure* luaFFIClosure;

- (id) initWithCif:(ffi_cif*)ffi_cif 
	realArgs:(ffi_type**)real_args_ptr
	flattenedArgs:(ffi_type**)flattened_args_ptr
	customTypeArgs:(ffi_type*)custom_type_args_ptr
	realReturnArg:(ffi_type*)real_return_ptr
	flattenedReturnArg:(ffi_type**)flattened_return_ptr
	customTypeReturnArg:(ffi_type*)custom_type_return_ptr
	ffiClosure:(ffi_closure*)the_closure
	parseSupport:(ParseSupportFunction*)parse_support
	originThread:(NSThread*)origin_thread
	luaState:(lua_State*)lua_state
	theBlock:(void*)the_block
;
- (void) dealloc;
- (void) finalize;

@end

@implementation LuaCocoaBlockDataForCleanupForLuaCreatedBlock

@synthesize originThread;
@synthesize luaState;
@synthesize luaFFIClosure;

- (id) initWithCif:(ffi_cif*)ffi_cif 
	realArgs:(ffi_type**)real_args_ptr
	flattenedArgs:(ffi_type**)flattened_args_ptr
	customTypeArgs:(ffi_type*)custom_type_args_ptr
	realReturnArg:(ffi_type*)real_return_ptr
	flattenedReturnArg:(ffi_type**)flattened_return_ptr
	customTypeReturnArg:(ffi_type*)custom_type_return_ptr
	ffiClosure:(ffi_closure*)the_closure
	parseSupport:(ParseSupportFunction*)parse_support
	originThread:(NSThread*)origin_thread
	luaState:(lua_State*)lua_state
	theBlock:(void*)the_block
{
	self = [super initWithParseSupport:parse_support];
	if(nil != self)
	{
		luaFFICif = ffi_cif;
		luaFFIRealArgs = real_args_ptr;
		luaFFIFlattenedArgs = flattened_args_ptr;
		luaFFICustomTypeArgs = custom_type_args_ptr;
		luaFFIRealReturnArg = real_return_ptr;
		luaFFIFlattenedReturnArg = flattened_return_ptr;
		luaFFICustomTypeReturnArg = custom_type_return_ptr;
		
		luaFFIClosure = the_closure;
		
		originThread = origin_thread;
		if(nil != originThread)
		{
			CFRetain(originThread);		
		}
		
		luaState = lua_state;
		theBlock = the_block; // this is a weak reference. It must not retain or we create a circular reference.
	}
	return self;	
}


+ (void) cleanupGloblalLuaStates:(lua_State*)lua_state blockPointer:(void*)the_block objectPointer:(void*)the_object
{
	// Because blocks may be asynchronous, the Lua state may have been killed off in the interim.
	// We must guard against calling into a dead Lua state.
	if(true == [[LuaCocoaAvailableLuaStates sharedAvailableLuaStates] containsLuaState:lua_state])
	{
		// Remove block <=> lua function mappings. Note that the Lua function may still exist, but the block is going away.
		// (I couldn't figure out a good way of keeping the block around with the Lua function life-cycle without inadvertently keeping the Lua function referenced unnecessarily.
		LuaCocoaWeakTable_RemoveBidirectionalLuaFunctionBlockInGlobalWeakTable(lua_state, the_block);
		
		
		// Remove the reference to the Lua function.
		LuaCocoaStrongTable_RemoveLuaFunctionValueForBlockCleanupKeyInGlobalStrongTable(lua_state, the_object);
	}
}

- (void) dealloc
{
	
	if(nil != originThread)
	{
		CFRelease(originThread);
	}
	
	if(NULL != luaFFIClosure)
	{
		if(munmap(luaFFIClosure, sizeof(luaFFIClosure)) == -1)
		{
			// Check errno and handle the error.
			NSLog(@"munmap failed in LuaFFIClosure");
			// Check errno and handle the error.
			perror( "munmap failed in LuaFFIClosure" );
			fprintf( stderr, "munmap failed in LuaFFIClosure: %s\n", strerror( errno ) );
		}
	}
	
	free(luaFFICustomTypeReturnArg);
	free(luaFFIFlattenedReturnArg);
	free(luaFFIRealReturnArg);
	free(luaFFICustomTypeArgs);
	free(luaFFIFlattenedArgs);
	free(luaFFIRealArgs);
	free(luaFFICif);

	// Because blocks may be asynchronous, the Lua state may have been killed off in the interim.
	// We must guard against calling into a dead Lua state.
	[LuaCocoaBlockDataForCleanupForLuaCreatedBlock cleanupGloblalLuaStates:luaState blockPointer:theBlock objectPointer:self];

	
	[super dealloc];
}

+ (void) cleanupGloblalLuaStates:(LuaCocoaBlockPointersForFinalizeCleanup*)pointer_data
{
	lua_State* lua_state = [pointer_data luaState];
	void* the_block = [pointer_data theBlock];
	void* the_object = [pointer_data theObject];
	[LuaCocoaBlockDataForCleanupForLuaCreatedBlock cleanupGloblalLuaStates:lua_state blockPointer:the_block objectPointer:the_object];
}

- (void) finalize
{
	if(NULL != luaFFIClosure)
	{
		if(munmap(luaFFIClosure, sizeof(luaFFIClosure)) == -1)
		{
			// Check errno and handle the error.
			NSLog(@"munmap failed in LuaFFIClosure");
			// Check errno and handle the error.
			perror( "munmap failed in LuaFFIClosure" );
			fprintf( stderr, "munmap failed in LuaFFIClosure: %s\n", strerror( errno ) );
		}
	}
	
	free(luaFFICustomTypeReturnArg);
	free(luaFFIFlattenedReturnArg);
	free(luaFFIRealReturnArg);
	free(luaFFICustomTypeArgs);
	free(luaFFIFlattenedArgs);
	free(luaFFIRealArgs);
	free(luaFFICif);

	if([originThread isEqualTo:[NSThread currentThread]])
	{
		// Because blocks may be asynchronous, the Lua state may have been killed off in the interim.
		// We must guard against calling into a dead Lua state.
		[LuaCocoaBlockDataForCleanupForLuaCreatedBlock cleanupGloblalLuaStates:luaState blockPointer:theBlock objectPointer:self];
	}
	else
	{
		// Finalize is on a background thread, but not all the Lua/LuaCocoa stuff is thread safe.
		// I know the origin Lua thread, so I'll take advantage of it.
		LuaCocoaBlockPointersForFinalizeCleanup* pointer_data = [[LuaCocoaBlockPointersForFinalizeCleanup alloc] initWithLuaState:luaState blockPointer:theBlock objectPointer:self];
		// This says you can use an NSObject class
		// http://www.cocoabuilder.com/archive/cocoa/217687-forcing-finalization-on-the-main-thread.html
		[LuaCocoaBlockDataForCleanupForLuaCreatedBlock performSelector:@selector(cleanupGloblalLuaStates:) onThread:originThread withObject:pointer_data waitUntilDone:NO]; 
		[pointer_data release];		
	}
	
	if(nil != originThread)
	{
		CFRelease(originThread);
	}
		
	[super finalize];
}

@end

// I made a class for this callback instead of making a category because categories are giving me headaches with static linking when building static libraries.
@interface LuaCocoaBlockDataForCallback : NSObject
{
@private
	ffi_cif* luaFFICif;
	void* returnResult;
	void** argsFromFfi;
	LuaCocoaBlockDataForCleanupForLuaCreatedBlock* closureUserData;	
}
/*
@property(nonatomic, readonly, assign) ffi_cif* luaFFICif;
@property(nonatomic, readonly, assign) void* returnResult;
@property(nonatomic, readonly, assign) void* argsFromFfi;
@property(nonatomic, readonly, retain) LuaCocoaBlockDataForCleanupForLuaCreatedBlock* closureUserData;
*/
- (id) initWithCif:(ffi_cif*)ffi_cif 
	returnResult:(void*)return_result
	argsFromFfi:(void*)args_from_ffi
	closureUserData:(LuaCocoaBlockDataForCleanupForLuaCreatedBlock*)closure_user_data
;
- (void) dealloc;

@end

@implementation LuaCocoaBlockDataForCallback
/*
@synthesize luaFFICif;
@synthesize returnResult;
@synthesize argsFromFfi;
@synthesize closureUserData;
*/

- (id) initWithCif:(ffi_cif*)ffi_cif 
	returnResult:(void*)return_result
	argsFromFfi:(void*)args_from_ffi
	closureUserData:(LuaCocoaBlockDataForCleanupForLuaCreatedBlock*)closure_user_data
{
	self = [super init];
	if(nil != self)
	{
		luaFFICif = ffi_cif;
		returnResult = return_result;
		argsFromFfi = args_from_ffi;
		closureUserData = [closure_user_data retain];
	}
	return self;
}

- (void) dealloc
{
	[closureUserData release];
	[super dealloc];
}

// Callback for performSelector:onThread:
- (void) invokeLuaCallback:(id)the_object
{
	LuaBlockBridge_InvokeGenericClosureCallback(luaFFICif, returnResult, argsFromFfi, closureUserData);
}

@end


// Invoking the closure transfers control to this function.
static void LuaBlockBridge_InvokeGenericClosureCallback(ffi_cif* the_cif, void* return_result, void** args_from_ffi, LuaCocoaBlockDataForCleanupForLuaCreatedBlock* closure_user_data)
{
	// FIXME: ParseSupport isn't going to have data for variadic arguments
	
	unsigned int number_of_arguments = the_cif->nargs;
//	LuaCocoaBlockDataForCleanupForLuaCreatedBlock* closure_user_data = (LuaCocoaBlockDataForCleanupForLuaCreatedBlock*)user_data;
	lua_State* lua_state = [closure_user_data luaState];
	
	// Because blocks may be asynchronous, the Lua state may have been killed off in the interim.
	// We must guard against calling into a dead Lua state.
	if(false == [[LuaCocoaAvailableLuaStates sharedAvailableLuaStates] containsLuaState:[closure_user_data luaState]])
	{
		// Not sure what to do about return_result.
		return;
	}
	
	int stack_top = lua_gettop(lua_state);
	// I actually expect a ParseSupportMethod, but I don't think I need any specific APIs from it.
	/*
	assert([closure_user_data->parseSupport isKindOfClass:[ParseSupportFunction class]]);
	ParseSupportFunction* parse_support = (ParseSupportFunction*)closure_user_data->parseSupport;
	*/
	ParseSupportFunction* parse_support = [closure_user_data parseSupport];
	NSUInteger i = 0;

	
	// FIXME: Do variadic arguments here
	
	// Need to handle variadic arguments.
	// Since the ParseSupport is shared, I don't really want to modify the shared instance.
	if(number_of_arguments > [parse_support.argumentArray count])
	{
//		NSLog(@"Warning in LuaSubclassBridge_GenericClosureCallback: Variadic arguments are untested"); 
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
	

	// Make sure there are enough slots for all the arguments, minus 1 for the block, plus 1 for the function.
	lua_checkstack(lua_state, [parse_support.argumentArray count]);

	// Fetch the Lua function from the global table and put it on the stack
	LuaCocoaStrongTable_GetLuaFunctionValueForBlockCleanupKeyInGlobalStrongTable(lua_state, closure_user_data);
	

	// Start at 1 instead of 0 because we want to skip the block argument
	for(i=1 ; i<[parse_support.argumentArray count]; i++)
	{
		LuaSubclassBridge_ParseFFIArgumentAndPushToLua(i, parse_support, lua_state, args_from_ffi);
	}
	

	
	
	
	
	// FIXME: Handle out arguments as multiple return values
#if 1
	int the_error = lua_pcall(lua_state, number_of_arguments-1, LUA_MULTRET, 0);
	if(0 != the_error)
	{
		// returns immediately
//		luaL_error(lua_state, "lua/ffi_prep_closure invocation failed: %s", lua_tostring(lua_state, -1));
		[NSException raise:@"lua/ffi_prep_closure invocation failed in LuaBlockBridge callback:" format:@"lua/ffi_prep_closure invocation failed in LuaBlockBridge callback: %s", lua_tostring(lua_state, -1)];
		//		lua_pop(lua_state, 1); /* pop error message from stack */
		return;
	}
#else
	lua_call(lua_state, number_of_arguments-1, LUA_MULTRET);

#endif
	
	
	// Now that we just called Lua, figure out how many return values were set. 
	// Extra return values in addition to the C/Signature return value denotes out-values.
	// I need to subtract the starting number of stack elements because in the __call situation, I seem to be deeper in the stack.
	int number_of_return_args = lua_gettop(lua_state) - stack_top;
	
	// Set the return FFI value from the first Lua return value
    bool is_void_return = LuaSubclassBridge_SetFFIReturnValueFromLuaReturnValue(the_cif, lua_state, return_result, parse_support);	

	/* The bridge support data is missing out modifiers.
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
		// Start at 1 instead of 0 because we want to skip the block argument
		LuaSubclassBridge_ProcessExtraReturnValuesFromLuaAsPointerOutArguments(lua_state, args_from_ffi, parse_support, 1, j);
	}
	
	
	
	
	lua_settop(lua_state, stack_top); // pop the string and the container
	
}

static void LuaBlockBridge_GenericClosureCallback(ffi_cif* the_cif, void* return_result, void** args_from_ffi, void* user_data)
{
	LuaCocoaBlockDataForCleanupForLuaCreatedBlock* closure_user_data = (LuaCocoaBlockDataForCleanupForLuaCreatedBlock*)user_data;

	// TODO: Add some kind of macro like LUA_LOCK or delegate or block system that users can define to validate if the lua_State is still alive/valid
	// so we can bailout if need be.
	// Example use case: You have a script reloading feature like HybridCoreAnimationScriptability where the lua_State* can get closed and reopened
	// without quiting the app. You do a asynchronous network connection which has a block completion handler like the Game Center APIs.
	// You close/reload your script before the network returns the data and triggers your completion handler.
	// The block is still alive on the Obj-C side, so this gets invoked. We have no general way of knowing that the lua_State is no longer good.
	// VALIDATE_LUA_STATE([closure_user_data luaState)
	
	
	// Because Lua is not compiled with thread locking by default,
	// we must take care to prevent blocks from calling Lua back on a different thread.
	// When the block is created, we will get the current queue and presume this is the queue that is safe to call Lua back on.
	// TODO: Add define to disable this in case somebody does compile Lua with locking enabled and wants to try this.

	// Avoid calling dispatch_sync if I don't need to otherwise I deadlock.
	if([[closure_user_data originThread] isEqualTo:[NSThread currentThread]])
	{
		LuaBlockBridge_InvokeGenericClosureCallback(the_cif, return_result, args_from_ffi, closure_user_data);
	}
	else
	{
//		NSLog(@"Block is not being called back on the same thread it was created.");
		// From the Objective-C mailing list: I was told I should not use dispatch_get_current_queue() and dispatch_sync.
		// Another suggestion was to use [NSThread currentThread] for my comparison and performSelector:onThread:
		// Though less elegant this seems to work well without any compromises.
		LuaCocoaBlockDataForCallback* thread_callback = [[LuaCocoaBlockDataForCallback alloc] initWithCif:the_cif returnResult:return_result argsFromFfi:args_from_ffi closureUserData:closure_user_data];
		[thread_callback performSelector:@selector(invokeLuaCallback:) onThread:[closure_user_data originThread] withObject:nil waitUntilDone:YES]; 
		[thread_callback release];
	}
}



// TODO: Consider supporting userdata or tables that implement the __call metamethod
id LuaBlockBridge_CreateBlockFromLuaFunctionWithParseSupport(lua_State* lua_state, int index_of_lua_function, ParseSupportFunction* parse_support)
{
//	NSLog(@"top: %d", lua_gettop(lua_state));

	// The block will keep a strong reference to the Lua function to prevent it from being garbage collected.
	// In case the function is reused, we should fetch the same block pointer. This means there should be a reverse mapping (function to block mapping); I think a weak reference is sufficent.
	// When the block is destroyed, the reference should be released.
	// Different/multiple Lua states mean different Lua functions which means different unique blocks. Nothing special needs to be done.

	// First check to see if we already have a block for this Lua function.
	// If so, fetch the existing block.
	id the_block = (void*)LuaCocoaWeakTable_GetBlockForLuaFunctionInGlobalWeakTable(lua_state, index_of_lua_function);
	lua_pop(lua_state, 1); // restore the stack
	if(nil != the_block)
	{
		// retain the block again to increase the reference count since this is essentially asking for a new instance.
		return [the_block retain];
	}
	
	
	/*
	 Obj-C doesn't provide a good way to create new blocks dynamically with arbitrary signatures.
	 va_args might be a possibility, but has limitations with types, such as:
	 ffi_prep_closure_blocks.m:249: warning: ‘float’ is promoted to ‘double’ when passed through ‘...’
	 ffi_prep_closure_blocks.m:249: warning: (so you should pass ‘double’ not ‘float’ to ‘va_arg’)
	 ffi_prep_closure_blocks.m:249: note: if this code is reached, the program will abort
	 Instead, we will use ffi_prep_closure to create an imp (like we do with subclasses),
	 and the technique documented here to replace the imp pointer from another block.
	 Philip White:
	 http://blog.rivulus-sw.com/?p=22
	 http://blog.rivulus-sw.com/?p=54
	 
	 Note that the article has a memory leak. (I contacted Philip directly.)
	 
	 I have to worry about the case of anonymous functions. So on the Lua side, 
	 
	 1) I might create a function in Lua for an Obj-C block parameter.
	 2) Crossing over the bridge into the Obj-C, I must tell the Lua interpreter through the Lua API to keep a strong reference to the function so it does not get garbage collected.
	 3) I do what you describe to setup ffi_prep_closure and swap the pointer from the dummy block.
	 4) When my ffi callback gets invoked, invoke my Lua function 
	 5) When the block is dealloc'd, I need to release my strong reference to my Lua function via the Lua API. Presumably, I also need to free the malloc'd memory used to create the ffi_cif.
	 
	 As a solution, I came across objc_setAssociatedObject and started thinking it might do the job. 	 
	 // blog code
	 void(^dummy_block)(void)=[^(void){printf("%i",i);} copy];
	 ...
	 *((void **)(id)cBlock + 3) = (void *)closure;
	 #endif
	 
	 //	<my code>
	 MyClosureData* my_closure_data = [[MyClosureData alloc] init];
	 // todo: add closure data
	 
	 objc_setAssociatedObject(cBlock, "SomeStaticConstantKey,FunctionPtrWouldWork", my_closure_data, OBJC_ASSOCIATION_RETAIN);
	 [my_closure_data release]; // retained by cBlock
	 
	 ...
	 [cBlock release];  // my_clousure_data will be released now

	 Remember to make this work with Obj-C Garbage Collection too.

	 I was also hoping these new API functions would be of help:
	 IMP imp_implementationWithBlock(void *block);
	 void *imp_getBlock(IMP anImp);
	 BOOL imp_removeBlock(IMP anImp);
	 But I think they still fall short for our purposes.
	*/
	
	
		
	
	

	
	
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

	// real_return_ptr will be set by the function.
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
/*	
	NSLog(@"the_class:%s", class_getName(the_class));
	NSLog(@"the_selector:%s", sel_getName(the_selector));
*/

	int i = 0xFFFF;
	// copy the block to get it into the heap. I'm not sure if it is safe to keep on the stack to get to Lua.
	// Don't forget that we need to do the Obj-C garbage collection dance.
	void(^dummy_block)(void)=[^(void){printf("%i",i);} copy];
//	CFRetain(dummy_block);
//	[dummy_block autorelease];
	
#ifdef __x86_64__
	/*  this is what happens when a block is called on x86 64
	 mov    %rax,-0x18(%rbp)		//the pointer to the block object is in rax
	 mov    -0x18(%rbp),%rax
	 mov    0x10(%rax),%rax			//the pointer to the block function is at +0x10 into the block object
	 mov    -0x18(%rbp),%rdi		//the first argument (this examples has no others) is always the pointer to the block object
	 callq  *%rax
	 */
	//2*(sizeof(void*)) = 0x10
	*((void **)(id)dummy_block + 2) = (void *)imp_closure;
#else
	/*  this is what happens when a block is called on x86 32
	 mov    %eax,-0x14(%ebp)		//the pointer to the block object is in eax
	 mov    -0x14(%ebp),%eax		
	 mov    0xc(%eax),%eax			//the pointer to the block function is at +0xc into the block object
	 mov    %eax,%edx
	 mov    -0x14(%ebp),%eax		//the first argument (this examples has no others) is always the pointer to the block object
	 mov    %eax,(%esp)
	 call   *%edx
	 */
	//3*(sizeof(void*)) = 0xc
	*((void **)(id)dummy_block + 3) = (void *)imp_closure;
#endif
	
	
	
	LuaCocoaBlockDataForCleanupForLuaCreatedBlock* block_data_for_cleanup = nil;

	
	// Make sure the real_return_ptr only gets added to the struct if it is dynamic memory.
	// Otherwise, the destructor will attempt to call free() on memory that I don't own which is bad.
	if(true == used_dynamic_memory_for_return_type)
	{
		block_data_for_cleanup = [[LuaCocoaBlockDataForCleanupForLuaCreatedBlock alloc] 
			initWithCif:cif_ptr
			realArgs:real_args_ptr
			flattenedArgs:flattened_args_ptr 
			customTypeArgs:custom_type_args_ptr 
			realReturnArg:NULL // I thought I needed this, but the memory is all in customTypeReturnArg 
			flattenedReturnArg:flattened_return_ptr 
			customTypeReturnArg:custom_type_return_ptr 
			ffiClosure:imp_closure 
			parseSupport:parse_support
			originThread:[NSThread currentThread]
			luaState:lua_state
			theBlock:dummy_block
		];
	}
	else
	{
		block_data_for_cleanup = [[LuaCocoaBlockDataForCleanupForLuaCreatedBlock alloc] 
			initWithCif:cif_ptr
			realArgs:real_args_ptr
			flattenedArgs:flattened_args_ptr 
			customTypeArgs:custom_type_args_ptr 
			realReturnArg:NULL 
			flattenedReturnArg:NULL 
			customTypeReturnArg:NULL 
			ffiClosure:imp_closure 
			parseSupport:parse_support
			originThread:[NSThread currentThread]
			luaState:lua_state
			theBlock:dummy_block
		];
	
	}

	// This is used to make sure that when the block is released, the ffi_closure data also gets cleaned up.
	// The dealloc/finalize methods for LuaCocoaBlockDataForCleanupForLuaCreatedBlock will make sure to clean up all the associated data.
	objc_setAssociatedObject(dummy_block, s_someStaticContstantValueForSetAssociatedBlock, block_data_for_cleanup, OBJC_ASSOCIATION_RETAIN);

	// Can release now that the block is holding a reference to it.
	[block_data_for_cleanup release];

			
	// Prepare the ffi_closure structure.
	// Passing the block_data_for_cleanup as userdata for convenience so we have easy access to ParseSupport on invocations.
	error_status = ffi_prep_closure(imp_closure, cif_ptr, LuaBlockBridge_GenericClosureCallback, block_data_for_cleanup);
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
		free(real_return_ptr);
		free(custom_type_args_ptr);
		free(flattened_args_ptr);
		free(real_args_ptr);
		free(cif_ptr);
		
		[dummy_block release];

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
		free(real_return_ptr);
		free(custom_type_args_ptr);
		free(flattened_args_ptr);
		free(real_args_ptr);
		free(cif_ptr);

		[dummy_block release];

		return NULL;
	}
	
	// We must keep a strong reference to the Lua function to prevent it from getting collected.
	// Note: I am saving the LuaCocoaBlockDataForCleanup instead of the actual block. 
	// This was more useful because the info I need for the callback is in the blockdata.
	// And in the callback, I already get the block back.
	LuaCocoaStrongTable_InsertLuaFunctionValueForBlockCleanupKeyInGlobalStrongTable(lua_state, index_of_lua_function, block_data_for_cleanup);

	// Keep an association between the Lua function and the block so if we encounter the Lua function again, we can reuse the existing pointer
	// which keeps a 1-to-1 mapping.
	LuaCocoaWeakTable_InsertBidirectionalLuaFunctionBlockInGlobalWeakTable(lua_state, index_of_lua_function, dummy_block);
	
	/*
	LuaCocoaWeakTable_GetLuaFunctionForBlockInGlobalWeakTable(lua_state, dummy_block);
	if(lua_type(lua_state, -1) == LUA_TFUNCTION)
	{
		NSLog(@"good");
	}
	else
	{
		NSLog(@"bad %d", lua_type(lua_state, -1));
	}
	LuaCocoaWeakTable_GetBlockForLuaFunctionInGlobalWeakTable(lua_state, -1);
	lua_pop(lua_state, 2);

	LuaCocoaWeakTable_GetLuaFunctionForBlockInGlobalWeakTable(lua_state, dummy_block);
	if(lua_type(lua_state, -1) == LUA_TFUNCTION)
	{
		NSLog(@"good");
	}
	else
	{
		NSLog(@"bad %d", lua_type(lua_state, -1));
	}
	lua_pop(lua_state, 1);
	 

	NSLog(@"top: %d", lua_gettop(lua_state));
	NSLog(@"dummy_block: %@", dummy_block);
	 */
	return dummy_block;

}


/**
 * @param array_for_ffi_arguments For arguments
 * @param array_for_ffi_ref_arguments for out-arguments
 */
static int LuaBlockBridge_InvokeBlock(lua_State* lua_state, id the_block, int lua_argument_start_index, ParseSupportFunction* parse_support)
{
	const int NUMBER_OF_SUPPORT_ARGS = 0; // No internal use only arguments

	
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
	size_t size_of_real_args = sizeof(ffi_type*) * parse_support.numberOfRealArguments;
	size_t size_of_flattened_args = sizeof(ffi_type*) * parse_support.numberOfFlattenedArguments;
	size_t size_of_custom_type_args = sizeof(ffi_type) * parse_support.numberOfRealArgumentsThatNeedToBeFlattened;
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
	
	ffi_cif the_cif;
	
	// FIXME: Check for 0 length sizes and avoid
#define ARBITRARY_NONZERO_SIZE 1
	size_t size_of_real_args_proxy = size_of_real_args ? size_of_real_args : ARBITRARY_NONZERO_SIZE;
	size_t size_of_flattened_args_proxy = size_of_flattened_args ? size_of_flattened_args : ARBITRARY_NONZERO_SIZE;
	size_t size_of_custom_type_args_proxy = size_of_custom_type_args ? size_of_custom_type_args : ARBITRARY_NONZERO_SIZE;
	size_t size_of_flattened_return_proxy = size_of_flattened_return ? size_of_flattened_return : ARBITRARY_NONZERO_SIZE;
	size_t size_of_custom_type_return_proxy = size_of_custom_type_return ? size_of_custom_type_return : ARBITRARY_NONZERO_SIZE;
#undef ARBITRARY_NONZERO_SIZE
	
	
	// use VLAs to use stack memory
	int8_t real_args_array[size_of_real_args_proxy];
	int8_t flattened_args_array[size_of_flattened_args_proxy];
	int8_t custom_type_args_array[size_of_custom_type_args_proxy];
	int8_t flattened_return_array[size_of_flattened_return_proxy];
	int8_t custom_type_return_array[size_of_custom_type_return_proxy];
	
	// Setup pointers to memory areas
	ffi_cif* cif_ptr = &the_cif;
	
	ffi_type** real_args_ptr = (ffi_type**)&real_args_array[0];
	ffi_type* custom_type_args_ptr = (ffi_type*)&custom_type_args_array[0];
	ffi_type** flattened_args_ptr = (ffi_type**)&flattened_args_array[0];
	
	ffi_type* real_return_ptr = NULL; // This will be set appropriately in FFISupport_ParseSupportFunctionReturnValueToFFIType
	ffi_type* custom_type_return_ptr = (ffi_type*)&custom_type_return_array[0];
	ffi_type** flattened_return_ptr = (ffi_type**)&flattened_return_array[0];
	
	char check_void_return;
	if(nil == parse_support.returnValue.objcEncodingType || 0 == [parse_support.returnValue.objcEncodingType length])
	{
		// FIXME:
		NSLog(@"no return type set. This is probably a bug");
		// Not sure if I should assume id or void
		check_void_return = _C_VOID;
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
	
	if(0 == size_of_real_args)
	{
		real_args_ptr = NULL;
	}
	if(0 == size_of_flattened_args)
	{
		flattened_args_ptr = NULL;
	}
	if(0 == size_of_custom_type_args)
	{
		custom_type_args_ptr = NULL;
	}
	if(0 == size_of_flattened_return || true == is_void_return)
	{
		flattened_return_ptr = NULL;
	}
	if(0 == size_of_custom_type_return || true == is_void_return)
	{
		custom_type_return_ptr = NULL;
	}
	
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
		return 0;
	}
	
	
	
	// This part of the implementation uses alloca because it is convenient, likely faster than heap memory, and all the other bridges do the same thing.
	// I would have preferred VLAs because I am unsure about the rules of using alloca (are they reliable as parameters to functions?)
	// but they didn't seem flexible enough as all the sizeof(type)'s are different values.
	// But the big downside is that I can't easily encapsulate the large switch statement into a function because it calls alloca.
	NSUInteger number_of_function_args = parse_support.numberOfRealArguments;
	
	// START COPY AND PASTE HERE	
	void* current_arg;
	int i, j;
	
	//	void** array_for_ffi_arguments = alloca(sizeof(void *) * number_of_function_args);
	void* array_for_ffi_arguments[number_of_function_args];
	
	// for out-arguments
	//	void** array_for_ffi_ref_arguments = array_for_ffi_ref_arguments = alloca(sizeof(void *) * number_of_function_args);
	void* array_for_ffi_ref_arguments[number_of_function_args];
	// END COPY AND PASTE HERE
	
	
	// For blocks, the first argument must be the block

	
	array_for_ffi_arguments[0] = &the_block;

	
	
	// Start at i=1 instead of 0 because we want to skip the block argument in ffi
	// Start at j=2 for the Lua parameters
    for(i = 1, j = 2 + NUMBER_OF_SUPPORT_ARGS; i < number_of_function_args; i++, j++)



	{
		void* current_arg;

		// START COPY AND PASTE HERE
		unsigned short current_ffi_type = cif_ptr->arg_types[i]->type;
		ParseSupportArgument* current_parse_support_argument = [parse_support.argumentArray objectAtIndex:i];
		
	#define putarg(type, val) ((array_for_ffi_arguments[i] = current_arg = alloca(sizeof(type))), *(type *)current_arg = (val))
		switch(current_ffi_type)
		{
			case FFI_TYPE_INT:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(int, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(int, lua_tointeger(lua_state, j));
				}
				break;
			}
			case FFI_TYPE_SINT8:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(int8_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(int8_t, lua_tointeger(lua_state, j));
				}
				break;
			}
			case FFI_TYPE_SINT16:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(int16_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(int16_t, lua_tointeger(lua_state, j));
				}
				break;
			}
			case FFI_TYPE_SINT32:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(int32_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(int32_t, lua_tointeger(lua_state, j));
				}
				break;
			}
			case FFI_TYPE_SINT64:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(int64_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(int64_t, lua_tointeger(lua_state, j));
				}
				break;	
			}
			case FFI_TYPE_UINT8:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(uint8_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(uint8_t, lua_tointeger(lua_state, j));
				}
				break;	
			}
			case FFI_TYPE_UINT16:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(uint16_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(uint16_t, lua_tointeger(lua_state, j));
				}
				break;	
			}
			case FFI_TYPE_UINT32:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(uint32_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(uint32_t, lua_tointeger(lua_state, j));
				}
				break;	
			}
			case FFI_TYPE_UINT64:
			{
				if(lua_isboolean(lua_state, j))
				{
					putarg(uint64_t, lua_toboolean(lua_state, j));				   
				}
				else
				{
					putarg(uint64_t, lua_tointeger(lua_state, j));
				}
				break;	
			}
	#if FFI_TYPE_LONGDOUBLE != FFI_TYPE_DOUBLE
			case FFI_TYPE_LONGDOUBLE:
				putarg(long double, lua_tonumber(lua_state, j));
				break;
	#endif
				
			case FFI_TYPE_DOUBLE:
				putarg(double, lua_tonumber(lua_state, j));
				break;
				
			case FFI_TYPE_FLOAT:
				putarg(float, lua_tonumber(lua_state, j));
				break;
				
			case FFI_TYPE_STRUCT:
				array_for_ffi_arguments[i] = lua_touserdata(lua_state, j);
				break;
				
			case FFI_TYPE_POINTER:
			{
				//			ParseSupportArgument* current_parse_support_argument = [parse_support.argumentArray objectAtIndex:i];
				//						NSLog(@"current_arg.declaredType=%@ objcEncodingType=%@, inOutTypeModifier=%@", current_parse_support_argument.declaredType, current_parse_support_argument.objcEncodingType, current_parse_support_argument.inOutTypeModifier);
				if([current_parse_support_argument.inOutTypeModifier isEqualToString:@"o"] || [current_parse_support_argument.inOutTypeModifier isEqualToString:@"N"] || [current_parse_support_argument.inOutTypeModifier isEqualToString:@"n"])
				{
					
					// Lion workaround for lack of Full bridgesupport file
					char objc_encoding_type;
					NSString* nsstring_encoding_type = current_parse_support_argument.objcEncodingType;
					if([nsstring_encoding_type length] < 2)
					{
						// assuming we are dealing with regular id's
						objc_encoding_type = _C_ID;						
					}
					else
					{
						objc_encoding_type = [nsstring_encoding_type UTF8String][1];						
					}
					
					switch(objc_encoding_type)
					{
						case _C_BOOL:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(int8_t*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(int8_t));
								*((int8_t*)(array_for_ffi_ref_arguments[i])) = lua_toboolean(lua_state, j);
								putarg(int8_t*, (int8_t*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_CHR:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(int8_t*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(int8_t));
								if(lua_isboolean(lua_state, j))
								{
									*((int8_t*)(array_for_ffi_ref_arguments[i])) = lua_toboolean(lua_state, j);
								}
								else
								{
									*((int8_t*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								}
								putarg(int8_t*, (int8_t*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_SHT:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(int8_t*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(int16_t));
								*((int16_t*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(int16_t*, (int16_t*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_INT:
						{    
							if(lua_isnil(lua_state, j))
							{
								putarg(int*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(int));
								if(lua_isboolean(lua_state, j))
								{
									*((int*)(array_for_ffi_ref_arguments[i])) = lua_toboolean(lua_state, j);
								}
								else
								{
									*((int*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								}
								putarg(int*, (int*)&(array_for_ffi_ref_arguments[i]));
							}
							break;			
						}
						case _C_LNG:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(long*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(long));
								if(lua_isboolean(lua_state, j))
								{
									*((long*)(array_for_ffi_ref_arguments[i])) = lua_toboolean(lua_state, j);
								}
								else
								{
									*((long*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								}
								putarg(long*, (long*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_LNG_LNG:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(long long*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(long long));
								*((long long*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(long long*, (long long*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_UCHR:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(uint8_t*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(uint8_t));
								*((uint8_t*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(uint8_t*, (uint8_t*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_USHT:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(uint16_t*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(uint16_t));
								*((uint16_t*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(uint16_t*, (uint16_t*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_UINT:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(unsigned int*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(unsigned int));
								*((unsigned int*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(unsigned int*, (unsigned int*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_ULNG:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(unsigned long*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(unsigned long));
								*((unsigned long*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(unsigned long*, (unsigned long*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_ULNG_LNG:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(unsigned long long*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(unsigned long long));
								*((unsigned long long*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(unsigned long long*, (unsigned long long*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_DBL:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(double*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(double));
								*((double*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(double*, (double*)&(array_for_ffi_ref_arguments[i]));
							}
						}
						case _C_FLT:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(float*, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(float));
								*((float*)(array_for_ffi_ref_arguments[i])) = lua_tointeger(lua_state, j);
								putarg(float*, (float*)&(array_for_ffi_ref_arguments[i]));
							}
						}
							
						case _C_STRUCT_B:
						{
							// Array goes here too
							array_for_ffi_ref_arguments[i] = lua_touserdata(lua_state, j);
							//							array_for_ffi_arguments[i] = lua_touserdata(lua_state, j);
							array_for_ffi_arguments[i] = &array_for_ffi_ref_arguments[i];
							break;
						}
							
						case _C_ID:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(id, nil);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(id));
								if(LuaObjectBridge_isid(lua_state, j))
								{
									// Considering topropertylist, but I don't think the return-by-reference is going to work right
									array_for_ffi_ref_arguments[i] = LuaObjectBridge_toid(lua_state, j);
								}
								else
								{
									array_for_ffi_ref_arguments[i] = nil;
								}
								putarg(id*, (id*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_CLASS:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(Class, nil);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(id));
								if(LuaObjectBridge_isid(lua_state, j))
								{
									// FIXME: Change to explicit toclass
									array_for_ffi_ref_arguments[i] = LuaObjectBridge_toid(lua_state, j);
								}
								else
								{
									array_for_ffi_ref_arguments[i] = nil;
								}
								putarg(id*, (id*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_CHARPTR:
						{
							// I don't expect this to work at all
							if(lua_isnil(lua_state, j))
							{
								putarg(id, nil);
							}
							else
							{
								const char* the_string = lua_tostring(lua_state, j);
								size_t length_of_string = strlen(the_string) + 1; // add one for \0
								
								array_for_ffi_ref_arguments[i] = alloca(sizeof(length_of_string));
								strlcpy(array_for_ffi_ref_arguments[i], the_string, length_of_string);
								putarg(char*, (char*)&(array_for_ffi_ref_arguments[i]));
							}
							break;
						}
						case _C_SEL:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(SEL, NULL);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(SEL));
								if(LuaSelectorBridge_isselector(lua_state, j))
								{
									array_for_ffi_ref_arguments[i] = LuaSelectorBridge_toselector(lua_state, j);
								}
								else
								{
									array_for_ffi_ref_arguments[i] = nil;
								}
								putarg(SEL*, (SEL*)&(array_for_ffi_ref_arguments[i]));						
							}
							break;
						}
							
						case _C_PTR:
						default:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(id, nil);
							}
							else
							{
								array_for_ffi_ref_arguments[i] = alloca(sizeof(void*));
								if(LuaSelectorBridge_isselector(lua_state, j))
								{
									array_for_ffi_ref_arguments[i] = lua_touserdata(lua_state, j);
								}
								else
								{
									array_for_ffi_ref_arguments[i] = nil;
								}
								putarg(void**, (void**)&(array_for_ffi_ref_arguments[i]));						
							}
							break;
						}
					}
					
				}
				else
				{
					// Lion workaround for lack of Full bridgesupport file
					char objc_encoding_type;
					NSString* nsstring_encoding_type = current_parse_support_argument.objcEncodingType;
					if([nsstring_encoding_type length] < 1)
					{
						// assuming we are dealing with regular id's
						objc_encoding_type = _C_ID;						
					}
					else
					{
						objc_encoding_type = [nsstring_encoding_type UTF8String][0];						
					}
					
					switch(objc_encoding_type)
					{
						case _C_ID:
						{
							if(lua_isnil(lua_state, j))
							{
								putarg(id, nil);
							}
							else if(lua_isfunction(lua_state, j) && [current_parse_support_argument isBlock])
							{
								// coerce Lua function into Obj-C block
								id new_block = LuaBlockBridge_CreateBlockFromLuaFunctionWithParseSupport(lua_state, j, [current_parse_support_argument functionPointerEncoding]);
								[new_block autorelease];
								//id block_userdata = LuaObjectBridge_Pushid(lua_state, new_block);
								
								putarg(id, new_block);
							}
							else
							{
								// Will auto-coerce numbers, strings, tables to Cocoa objects
								id property_object = LuaObjectBridge_topropertylist(lua_state, j);			
								putarg(id, property_object);
							}
							break;
						}
						case _C_CLASS:
						{
							Class to_object = LuaObjectBridge_toid(lua_state, j);			
							putarg(Class, to_object);
							break;
						}
						case _C_CHARPTR:
						{
							if(lua_isstring(lua_state, j))
							{
								putarg(const char*, lua_tostring(lua_state, j));
							}
							else if(LuaObjectBridge_isnsstring(lua_state, j))
							{
								putarg(const char*, [LuaObjectBridge_tonsstring(lua_state, j) UTF8String]);								
							}
							else
							{
								putarg(const char*, NULL);
							}
							break;
						}
						case _C_SEL:
						{
							putarg(SEL, LuaSelectorBridge_toselector(lua_state, j));
							break;
						}
							
						case _C_PTR:
						{
							if(lua_isfunction(lua_state, j) && [current_parse_support_argument isFunctionPointer])
							{
								NSLog(@"Non-block function pointers not implemented yet. Should be easy to adapt block code to handle.");
								// coerce Lua function into Obj-C block
								
								//								id new_block = LuaBlockBridge_CreateBlockFromLuaFunctionWithParseSupport(lua_state, j, [current_parse_support_argument.functionPointerEncoding]);
								//								putarg(id, new_block);
								putarg(void*, lua_touserdata(lua_state, j));
								
							}
							else
							{
								putarg(void*, lua_touserdata(lua_state, j));
							}
						}
						default:
						{
							putarg(void*, lua_touserdata(lua_state, j));
						}
					}
				}
				break;
			}
		}
	#       undef putarg
		// END COPY AND PASTE HERE
		
	}

	
	
	
	
	
	
	// if needed
	int stack_index_for_struct_return_value = 0;
	void* return_value = NULL;
	if(false == is_void_return)
	{
		if(FFI_TYPE_STRUCT == cif_ptr->rtype->type)
		{
			return_value = lua_newuserdata(lua_state, cif_ptr->rtype->size);
			stack_index_for_struct_return_value = lua_gettop(lua_state);
			
			// set correct struct metatable on new userdata
			NSString* return_struct_type_name = parse_support.returnValue.objcEncodingType;
			
			// set correct struct metatable on new userdata
			
			NSString* struct_struct_name = ParseSupport_StructureReturnNameFromReturnTypeEncoding(return_struct_type_name);
			
			NSString* struct_keyname = [ParseSupportStruct keyNameFromStructName:struct_struct_name];
			LuaStructBridge_SetStructMetatableOnUserdata(lua_state, stack_index_for_struct_return_value, struct_keyname, struct_struct_name);
		}
		else
		{
			// rvalue must point to storage that is sizeof(long) or larger. For smaller return value sizes, 
			// the ffi_arg or ffi_sarg integral type must be used to hold the return value.
			// But as far as I can tell, cif_ptr->rtype->size already has the correct size for this case.
			return_value = alloca(cif_ptr->rtype->size);
		}
	}
	
	
	IMP block_imp = NULL;
	
	// Problem: It appears that returning structs is getting corrupted if I just use imp_implementationWithBlock to fetch the imp pointer for
	// my Lua created blocks. I suspect that the function does special magic for struct blocks which is incompatible 
	// with the imp pointer injection trick we use to create new blocks.
	// The workaround seems to detect whether we are invoking a Obj-C defined block or Lua defined block.
	// If a Lua block, recover the original imp pointer directly.
	// Otherwise use imp_implementationWithBlock.
	// Through experiments, I can grab the pointer directly from the block just like I set it and it works.
	// But I decided to grab the saved pointer from the block cleanup object.
	// While it is possible to also invoke the Lua function directly, my previous bad experience with this in the subclass bridge,
	// I've decided it is better to go through normal Obj-C mechanisms so the whole system behaves consistently in case there are other
	// useful side-effects I might miss by not traveling through the standard Obj-C dispatch mechanism.
	LuaCocoaBlockDataForCleanup* block_data_for_cleanup = nil;
	block_data_for_cleanup = objc_getAssociatedObject(the_block, s_someStaticContstantValueForSetAssociatedBlock);
	if(nil != block_data_for_cleanup && [block_data_for_cleanup isKindOfClass:[LuaCocoaBlockDataForCleanupForLuaCreatedBlock class]])
	{
		block_imp = (IMP)[(LuaCocoaBlockDataForCleanupForLuaCreatedBlock*)block_data_for_cleanup luaFFIClosure];
	}
	else
	{
		block_imp = imp_implementationWithBlock(the_block);
	}
		
	// Call the function
	ffi_call(cif_ptr, FFI_FN(block_imp), return_value, array_for_ffi_arguments);		
	
	
	int number_of_return_values = 0;
	
	// If the result (now on the top of the stack) is an object instance
	// we need to check if we need to special handle the retain count.
	
	// This is exception is for things like CALayer where alloc leaves the retainCount at 0.
	// NSPlaceholder objects seem to have retainCounts of < 0. I don't think I need to worry about
	// retaining placeholder objects
	// Analysis:
	// For things like CALayer, defer CFRetain and release if the retainCount is 0 until init is called.
	// For things like Placeholder objects, I think retaining is irrelevant either way as I expect
	// a retain and release to be a no-op. However, if it is not a no-op, then I think I can
	// retain here and when init is called, the reference will generally be overwritten in Lua
	// so Lua knows to collect its memory and we will get to call a balancing release.
	// The release however must be deferred until the init.
	// But this block of code will see the final object as a new/different object because
	// the memory addresses are different.

	if(parse_support.returnValue.isAlreadyRetained)
	{
		// We likely called a function like CF*Create().
		// Push, but don't increment the retain count. 
		// We must release the retain count by one
		// I assume the function used a CFRetain() to hold the object.
		// (I only see the already_retained marker in the CoreFoundation XML.)
		// Tell the push function not to retain. We will use this retain towards our bridge count
		number_of_return_values += LuaFFISupport_PushReturnValue(lua_state, return_value, cif_ptr->rtype, parse_support.returnValue, stack_index_for_struct_return_value, false, false);
		LuaUserDataContainerForObject* the_container = lua_touserdata(lua_state, -1);
		the_container->needsRelease = true;
	}
	else
	{
		// general case. Always try to retain and let the natural logic sort out the mess.
		if(false == is_void_return)
		{
			number_of_return_values += LuaFFISupport_PushReturnValue(lua_state, return_value, cif_ptr->rtype, parse_support.returnValue, stack_index_for_struct_return_value, true, false);			
		}
	}
	
	
	// Now traverse out arguments and see which we need to return
	size_t argument_index = 0;
	for(ParseSupportArgument* current_parse_support_argument in parse_support.argumentArray)
	{
		// check for out or inout arguments
		if([current_parse_support_argument.inOutTypeModifier isEqualToString:@"o"] || [current_parse_support_argument.inOutTypeModifier isEqualToString:@"N"])
		{
			int stack_index_for_argument = argument_index + NUMBER_OF_SUPPORT_ARGS + 1; // shift for support arguments, add 1 for lua index starts at 0
			number_of_return_values += LuaFFISupport_PushReturnValue(lua_state, array_for_ffi_arguments[argument_index], cif_ptr->arg_types[argument_index], current_parse_support_argument, stack_index_for_argument, true, true);
		}
		argument_index++;
	}
	//	NSLog(@"number_of_return_values: %d", number_of_return_values); 
	//	NSLog(@"top return type %d", lua_type(lua_state, -1));
	
	return number_of_return_values;
}


int LuaBlockBridge_CallBlock(lua_State* lua_state, id the_block, int lua_argument_start_index)
{
	LuaCocoaBlockDataForCleanup* block_data_for_cleanup = nil;
	block_data_for_cleanup = objc_getAssociatedObject(the_block, s_someStaticContstantValueForSetAssociatedBlock);
	if(nil == block_data_for_cleanup)
	{
		return luaL_error(lua_state, "Cannot call Obj-C block because there is no signature available. (Hint: Use LuaCocoa.setBlockSignature)");
	}
	return LuaBlockBridge_InvokeBlock(lua_state, the_block, lua_argument_start_index, [block_data_for_cleanup parseSupport]);
}



id LuaBlockBridge_CreateBlockFromLuaFunctionWithXMLString(lua_State* lua_state, int index_of_lua_function, NSString* xml_string)
{
	ParseSupportFunction* parse_support = [[[ParseSupportFunction alloc] initFunctionPointerWithXMLString:xml_string objcEncodingType:@"@?"] autorelease];
	return LuaBlockBridge_CreateBlockFromLuaFunctionWithParseSupport(lua_state, index_of_lua_function, parse_support);
}

// index=2 XML
// index=1 Lua function
static int LuaBlockBridge_ToBlock(lua_State* lua_state)
{
	NSString* xml_string = LuaObjectBridge_checknsstring(lua_state, -1);
	id the_block = LuaBlockBridge_CreateBlockFromLuaFunctionWithXMLString(lua_state, -2, xml_string);
	[the_block autorelease];
	LuaObjectBridge_Pushid(lua_state, the_block);
	return 1;
}

// This will take a Obj-C block at index=1 and extract the Lua function if it exists.
static int LuaBlockBridge_ToFunction(lua_State* lua_state)
{
	id the_block = LuaObjectBridge_checkid(lua_state, -1);
	
	if(LuaObjectBridge_isidinstance(lua_state, -1) && [the_block isKindOfClass:NSClassFromString(@"NSBlock")])
	{
		LuaCocoaWeakTable_GetLuaFunctionForBlockInGlobalWeakTable(lua_state, the_block);
		return 1;
	}
	
	// function should return nil if it fails
	return 0;
}

// 1st argument must be the block
// 2nd argument is the XML signature
// This will be a no-op if the signature is already set. Do not use this to change the signature later.
static int LuaBlockBridge_AssociateBlockSignature(lua_State* lua_state)
{
	id the_block = LuaObjectBridge_checkid(lua_state, -2);
	
	if(LuaObjectBridge_isidinstance(lua_state, -2) && [the_block isKindOfClass:NSClassFromString(@"NSBlock")])
	{
		// If there is already an association, we shortcut out.
		// Potentially we could allow the signature to be changed which might help allow for vaargs, but it can get messy and I don't want to think about it right now.
		// All Lua defined blocks will always have an association. Obj-C blocks will have an association if it was already set in a prior call.
		LuaCocoaBlockDataForCleanup* block_data_for_cleanup = nil;
		block_data_for_cleanup = objc_getAssociatedObject(the_block, s_someStaticContstantValueForSetAssociatedBlock);
		if(nil != block_data_for_cleanup)
		{
			return 0; // short cut out
		}
		
		NSString* xml_string = LuaObjectBridge_checknsstring(lua_state, -1);
		ParseSupportFunction* parse_support = [[[ParseSupportFunction alloc] initFunctionPointerWithXMLString:xml_string objcEncodingType:@"@?"] autorelease];
		block_data_for_cleanup = [[[LuaCocoaBlockDataForCleanup alloc] initWithParseSupport:parse_support] autorelease];
		objc_setAssociatedObject(the_block, s_someStaticContstantValueForSetAssociatedBlock, block_data_for_cleanup, OBJC_ASSOCIATION_RETAIN);
	}
	else
	{
		// luaL_error aborts execution.
		return luaL_error(lua_state, "Cannot set the block signature because the object is not a block");
	}
	return 0;
}

static const luaL_reg LuaBlockBridge_LuaFunctions[] = 
{
	{"toblock", LuaBlockBridge_ToBlock},
	{"tofunction", LuaBlockBridge_ToFunction},
	{"setBlockSignature", LuaBlockBridge_AssociateBlockSignature},
	{NULL,NULL},
};


int luaopen_LuaBlockBridge(lua_State* lua_state)
{
//	luaL_newmetatable(lua_state, LUACOCOA_SELECTOR_METATABLE_ID);
	//	lua_pushvalue(lua_state, -1);
	//	lua_setfield(lua_state, -2, "__index");
//	luaL_register(lua_state, NULL, LuaSelectorBridge_MethodsForSelectorMetatable);
	
	luaL_register(lua_state, "LuaCocoa", LuaBlockBridge_LuaFunctions);
	
	
	return 1;
}



