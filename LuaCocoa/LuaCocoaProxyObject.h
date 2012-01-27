/* NOTE: LuaCocoaProxyObject is now obsolete and will be removed. */


//
//  LuaCocoaProxyObject.h
//  LuaCocoa
//
//  Created by Eric Wing on 11/14/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

struct lua_State;

@interface LuaCocoaProxyObject : NSProxy <NSObject>
{
	id luaCocoaObject;
	struct lua_State* luaState;
}
- (id) initWithProxiedObject:(id)the_object;
- (id) luaCocoaObject;
/**
 * Sets a lua_State to the ProxyObject. It will also pass this state down to the underlying luaCocoaObject.
 * @note Under Obj-C garbage collection, setting the state to NULL after you are ready to destroy the object
 * in Objective-C may be a reasonable way to avoid any potential race-condition problems with finalize and 
 * the closing of the lua_State. If you are being bit by that race condition bug, I recommend you try setting
 * the state to NULL. This is a bit experimental, so if you are not being affected by this problem, I recommend
 * you trust on the other precautions I have taken in the code base to avoid this race-condition.
 */
- (void) setLuaStateForLuaCocoaProxyObject:(struct lua_State*)lua_state;
- (struct lua_State*) luaStateForLuaCocoaProxyObject;


@end
