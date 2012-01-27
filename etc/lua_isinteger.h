// 
//  lua_isinteger.h
//
//  Created by Eric Wing on 3/22/11.
//  Copyright 2011 PlayControl Software, LLC. All rights reserved.
//


//	You only need this file if you use your own Lua without the LNUM patch.


#include "lua.h"

// Needed because we don't have LNUM
extern int             (lua_isinteger) (lua_State *L, int idx);

