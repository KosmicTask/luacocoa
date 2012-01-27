//
//  lua_isinteger.c
//
//  Created by Eric Wing on 3/22/11.
//  Copyright 2011 PlayControl Software, LLC. All rights reserved.

//
//	You only need this file if you use your own Lua without the LNUM patch.
// 	You may need to make adjustments for the floating precision you use.

#include "lua_isinteger.h"
#include <math.h>
#include <float.h>

int lua_isinteger (lua_State *L, int idx)
{
	lua_Number the_number = lua_tonumber(L, idx);
	double rounded_number = round(the_number);
//	if( fabs(the_number-rounded_number) <= DBL_EPSILON )
	// Do we want extra fuzziness to handle bad double->float conversion losses?
	if( fabs(the_number-rounded_number) <= FLT_EPSILON )
	{
		return 1;
	}
	else
	{
		return 0;
	}
}

