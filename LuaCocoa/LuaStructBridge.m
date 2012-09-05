//
//  StructBridge.m
//  LuaCocoa
//
//  Created by Eric Wing on 10/13/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "LuaStructBridge.h"


#include "lauxlib.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <objc/runtime.h>

#include "LuaCUtils.h"
#include "StructSupport.h"
#import "LuaObjectBridge.h"
#import "LuaSelectorBridge.h"
#import "ParseSupportStruct.h"



// BridgeSupport struct names are complicated by the fact that they have both a key name and struct name
// which may be different. For example, for keyName="NSRect", in 32-bit structName="_NSRect",
// and in 64-bit structName="CGRect".
// Since my BridgeSupportController map is keyed by keyName, if I try looking up by
// structName, I may not find the correct item. But conversely, if I try comparing by keyName
// instead of structName, I run into certain equality tests that fail when they should pass.
// So I'm keeping hidden fields in the metatable for both.  
static const char* LUASTRUCTBRIDGE_BRIDGESUPPORT_KEYNAME = "__luastructbridgesupportkeyname";
static const char* LUASTRUCTBRIDGE_BRIDGESUPPORT_STRUCTNAME = "__luastructbridgesupportstructname";



bool LuaStructBridge_GetOrCreateStructMetatable(lua_State* lua_state, NSString* key_name, NSString* struct_name);

/* Alas. The implementation used to be much simpler. The original idea was every struct was allocated in full as newuserdata.
 So every Lua instance of a struct was a completely self-contained copy which made things very simple to deal with.
 Unfortunately, it comes to my attention from Fjölnir Ásgeirsson that this fails:
 nsrect.size.width = 100
 The problem is that nsrect.size creates a new copy of a NSSize struct and the width is set on that intermediate NSSize struct.
 Then the value is lost because the original nsrect has no association to the copy of the intermediate struct.

 Interestingly, I originally steered away from this course in my original LuaCore experiments which can be be read about here:
 http://lua-users.org/lists/lua-l/2008-07/msg00604.html
 
 The context was 2D arrays (which was really for CATransform3D). The feeling was that being able to split off a vector from the
 matrix and continue to manipulate the vector separately which would continue to affect the matrix would be weird from a scripter perspective.
 It didn't click until now for me that this 2D array case and this struct case are in fact the same because 
 a dot access is the same as the table look up so in a nested struct access, I am doing multidimensional tables.
 
 So upon reflection, I'm thinking the reference behavior is the better trade-off of the two. I can justify this in part
 in how regular Lua tables work. If I pull off a subtable from a table, I am dealing with a reference, not a copy.
 This suggests though that I may also need to fix assignment constructs to accept references instead of doing a copy.
 However, I'm not yet sold on this idea mostly because of even more complexity.
 
 This function is intended to start addressing the issue that I now need reference structs. 
 Before I always assumed the userdata pointer was my struct and I could memcpy into it or whatever since it had the correct size.
 Now I need two different struct userdata representations. 
 The first is the original implementation; a full memory blob containing the struct.
 The second is a reference struct. While it needs to be a unique userdata for Lua instance purposes, 
 the payload should be a pointer to the struct it is referencing. So I am going to make the userdata the size of a single pointer
 and it will point to the correct offset for the sub-struct in the original userdata's struct.
 In addition, I will use the userdata environment table to hold a strong reference to the original userdata (to avoid dangling
 pointer issues to avoid the possibility that the original struct gets collected while the substruct is still in use).
 
 My existing code seems to simply assume I have the blob of memory I need to walk the struct. So I think I merely need to replace
 the touserdata functions with this helper function to get me back the correct pointer.
 */

struct LuaStructBridge_ReferenceStruct
{
	// This points to the actual struct (userdata).
	// This includes the offset inside the real struct that we want, e.g. this will point to the NSSize part inside NSRect.
	void* pointerToRealStructMemoryOffset;
};

static void* LuaStructBridge_GetStructPointer(lua_State* lua_state, int index_of_struct, _Bool* is_reference_struct)
{
	_Bool found_reference_struct = false;
	void* struct_pointer_to_return = NULL;
	// grab it now before I change the stack positions
	void* struct_userdata = lua_touserdata(lua_state, index_of_struct);
	
	// It looks like we always have an environment table whether I explicitly created one or not.
	// So look inside and if there is a value we stored, then it is a reference struct.
	// Otherwise, it is a full-blown, normal struct.
	lua_getfenv(lua_state, index_of_struct); // pushes a env-table
	lua_pushstring(lua_state, "*"); // look for the key "*" in the env-table
	lua_rawget(lua_state, -2);
	if(lua_type(lua_state, -1) == LUA_TNIL) // see if there is anything in the table (assuming I put an array)
	{
		found_reference_struct = false;
		struct_pointer_to_return = struct_userdata;
	}
	else
	{
		found_reference_struct = true;
		struct_pointer_to_return = ((struct LuaStructBridge_ReferenceStruct*)struct_userdata)->pointerToRealStructMemoryOffset;
	}
	
	// pop the result and environment table
	lua_pop(lua_state, 2);

	if(NULL != is_reference_struct)
	{
		*is_reference_struct = found_reference_struct;
	}
	
	return struct_pointer_to_return;
}

static void* LuaStructBridge_CreateReferenceStruct(lua_State* lua_state, int index_of_original_struct, void* pointer_to_real_data_with_offset, NSString* name_of_return_struct_keyname, NSString* name_of_return_struct_structname)
{
//	int top = lua_gettop(lua_state);
	// convert to absolute index if necesary
	if(index_of_original_struct < 0)
	{
		index_of_original_struct = lua_gettop(lua_state) + index_of_original_struct + 1;
	}
	
	void* return_struct_userdata = lua_newuserdata(lua_state, sizeof(struct LuaStructBridge_ReferenceStruct)); // stack (top is left): [new_struct_reference_userdata ... original_struct_userdata]
	
	// Shove the pointer to the real struct data inside the userdata
	((struct LuaStructBridge_ReferenceStruct*)return_struct_userdata)->pointerToRealStructMemoryOffset = pointer_to_real_data_with_offset;
	
	// We must hold a strong reference to the original struct userdata to prevent the data from being collected from underneath us.
	// Use an environment table to hold the reference.
	// It will look like this:
	// env_table = { ["*"] = original_struct_userdata }
	// Note: The cache optimization adds additional stuff so it looks like this:
	// (To get the reference and cache together, we need a 3-level struct box->rect->origin)
	// env_table = { ["*"]=original_box_struct_userdata, [1]=origin_sub_struct, origin=origin_substruct, ...} }
	lua_newtable(lua_state); // stack (top is left): [env_table new_struct_reference_userdata ... original_struct_userdata]

	
	// Copy the original struct into the environment table
	lua_pushstring(lua_state, "*"); // we're going to use the keyname "*" because the * is an illegal struct field name in C. This will allow us to distinguish between our reference entry and any other cached fields.
	lua_pushvalue(lua_state, index_of_original_struct); // stack (top is left): [original_struct_userdata env_table new_struct_reference_userdata ... original_struct_userdata]	
	lua_rawset(lua_state, -3);    /* env_table[ "*" ] = original_struct_userdata, pops original_struct_userdata */
	
	// stack: [MyMatrix2 index MyVector table]
	lua_setfenv( lua_state, -2 );    // Makes the table on top of the stack the environment table for MyVector (at -2)
	
		
	// Fetch the metatable for this struct type and apply it to the struct so the Lua scripter can access the fields
	LuaStructBridge_SetStructMetatableOnUserdata(lua_state, -1, name_of_return_struct_keyname, name_of_return_struct_structname);

	/*
	int top2 = lua_gettop(lua_state);
	assert(top+1 == top2);
	*/
	
	return return_struct_userdata;
}


/*
What happens?
1) C function returns a struct.
2) We need to create a newuserdata for the struct to get it into Lua
3) We want to create a metatable for this struct based on the information we have from BridgeSupport
(This metatable may have been pre-created at BridgeSupport load-time in which case we just need to retrieve it.)
3b) This metatable will need a unique identifier
3c) It would be nice for this metatable to provide accessors. We will need to walk the struct to make this happen.
4) Set the metatable to this new userdata
*/


// Think my_table = LuaCocoa.StructToTable(my_nspoint_userdata), user must call explictly
// For nested structs (e.g. NSRect), we need to recursively traverse.
// Might be useful for serialization/dumping to storage
// Priority: nice to have
#if 0
static int lua_CATransform3DToLua(lua_State* lua_state)
{
	CATransform3D* the_struct = LuaCheckCATransform3D(lua_state, -1);
    lua_newtable(lua_state);
	
	lua_pushnumber(lua_state, the_struct->m11);
	lua_setfield(lua_state, -2, "m11");
	
	lua_pushnumber(lua_state, the_struct->m12);
	lua_setfield(lua_state, -2, "m12");
	
	lua_pushnumber(lua_state, the_struct->m13);
	lua_setfield(lua_state, -2, "m13");
	
	lua_pushnumber(lua_state, the_struct->m14);
	lua_setfield(lua_state, -2, "m14");
	
	lua_pushnumber(lua_state, the_struct->m21);
	lua_setfield(lua_state, -2, "m21");
	
	lua_pushnumber(lua_state, the_struct->m22);
	lua_setfield(lua_state, -2, "m22");
	
	lua_pushnumber(lua_state, the_struct->m23);
	lua_setfield(lua_state, -2, "m23");
	
	lua_pushnumber(lua_state, the_struct->m24);
	lua_setfield(lua_state, -2, "m24");
	
	lua_pushnumber(lua_state, the_struct->m31);
	lua_setfield(lua_state, -2, "m31");
	
	lua_pushnumber(lua_state, the_struct->m32);
	lua_setfield(lua_state, -2, "m32");
	
	lua_pushnumber(lua_state, the_struct->m33);
	lua_setfield(lua_state, -2, "m33");
	
	lua_pushnumber(lua_state, the_struct->m34);
	lua_setfield(lua_state, -2, "m34");
	
	lua_pushnumber(lua_state, the_struct->m41);
	lua_setfield(lua_state, -2, "m41");
	
	lua_pushnumber(lua_state, the_struct->m42);
	lua_setfield(lua_state, -2, "m42");
	
	lua_pushnumber(lua_state, the_struct->m43);
	lua_setfield(lua_state, -2, "m43");
	
	lua_pushnumber(lua_state, the_struct->m44);
	lua_setfield(lua_state, -2, "m44");		
	
    return 1;
}
#endif


// Used by __tostring
// Good for debugging: print(my_struct)
static NSString* NSStringFromStruct(NSString* key_name, void* struct_userdata)
{
	return [ParseSupport descriptionStringFromStruct:key_name structPtr:struct_userdata];
}
static int LuaStructBridge_ConvertStructToString(lua_State* lua_state)
{

	NSString* struct_name = LuaStructBridge_GetBridgeStructNameFromMetatable(lua_state, -1);
	if(NULL == struct_name)
	{
		// This is not a LuaStructBridge object so abort with error
		// luaL_typeerror is what luaL_checkudata calls. Seems appropriate.
		luaL_typerror(lua_state, -1, LUASTRUCTBRIDGE_BRIDGESUPPORT_STRUCTNAME);
	}
	NSString* key_name = LuaStructBridge_GetBridgeKeyNameFromMetatable(lua_state, -1);

	void* struct_userdata = LuaStructBridge_GetStructPointer(lua_state, -1, NULL);
	
	NSString* description_string = NSStringFromStruct(key_name, struct_userdata);
	lua_pushstring(lua_state, [description_string UTF8String]);

	return 1;
}

// For __eq.
// Tricky again for the fact that I do not know the name of the struct fields until runtime.
// Following Improved Crazy Thought: Use Lua again to compare each field by iterating through array.
// Also, should I ignore type? This would allow different struct types to return true if all the fields match (e.g. NSRect/CGRect).
#if 0
static int CompareEqualOnCATransform3D(lua_State* lua_state)
{
	CATransform3D* the_struct1 = LuaCheckCATransform3D(lua_state, -2);
	CATransform3D* the_struct2 = LuaCheckCATransform3D(lua_state, -1);
	
	lua_pushboolean(lua_state, CATransform3DEqualToTransform(*the_struct1, *the_struct2));
	return 1;
}
#endif

/*
 static int GetCATransform3DType(lua_State* lua_state)
 {
 CATransform3D* the_struct = LuaCheckCATransform3D(lua_state, -1);
 lua_pushstring(lua_state, "CATransform3D");
 return 1;
 }
 */

// obj_index = -1 is key
// obj_index = -2 is userdata object
static int LuaStructBridge_GetIndexOnStruct(lua_State* lua_state)
{
	NSString* struct_name = LuaStructBridge_GetBridgeStructNameFromMetatable(lua_state, -2);
	if(NULL == struct_name)
	{
		// This is not a LuaStructBridge object so abort with error
		// luaL_typeerror is what luaL_checkudata calls. Seems appropriate.
		luaL_typerror(lua_state, -2, LUASTRUCTBRIDGE_BRIDGESUPPORT_STRUCTNAME);
	}
	
	// Deferring variables until after cache check.
	NSString* key_name = nil;
	// convert to absolute index if necesary
	int absolute_index_of_original_struct = lua_gettop(lua_state) + -2 + 1;
	
	// Parse support
	ParseSupportStruct* parse_support_struct_object = nil;

//	NSLog(@"structName:%@", parse_support_struct_object.structName);

/*
	for(NSString* field_name in parse_support_struct_object.fieldNameArray)
	{
		NSLog(@"FieldName:%@", field_name);
	}
*/
	NSUInteger number_of_fields = [parse_support_struct_object.fieldNameArray count];
	
	int array_index = 0;
	const char* index_string = NULL;
	
	if(lua_isnumber(lua_state, -1))
	{
		array_index = lua_tointeger(lua_state, -1);
		
		// Check the cache in the environment table to see if we already created this value
		// If so, we can return quickly.
		lua_getfenv(lua_state, absolute_index_of_original_struct); // pushes the env-table onto the stack
		lua_rawgeti(lua_state, -1, array_index);
		if(lua_type(lua_state, -1) != LUA_TNIL)
		{
			return 1;
		}
		lua_pop(lua_state, 2); // pop nil and env_table
		
		// Fill out these variables. We'll need them later
		key_name = LuaStructBridge_GetBridgeKeyNameFromMetatable(lua_state, -2);
		// Parse support
		parse_support_struct_object = [ParseSupportStruct parseSupportStructFromKeyName:key_name];;
		
		
	}
	else if(lua_isstring(lua_state, -1))
	{
		// Check the cache in the environment table to see if we already created this value
		// If so, we can return quickly.
		lua_getfenv(lua_state, absolute_index_of_original_struct); // pushes the env-table onto the stack
		lua_pushvalue(lua_state, -2); // push the key string on top so we can do a raw set
		lua_rawget(lua_state, -2);
		if(lua_type(lua_state, -1) != LUA_TNIL)
		{
			return 1;
		}
		lua_pop(lua_state, 2); // pop nil and env_table

		
		key_name = LuaStructBridge_GetBridgeKeyNameFromMetatable(lua_state, -2);
		// Parse support
		parse_support_struct_object = [ParseSupportStruct parseSupportStructFromKeyName:key_name];;
	
		
		
		
		index_string = lua_tostring(lua_state, -1);
		
		// Use parse support to find and enumerate where the element resides in the struct.
		// Save this as an array_index for convenience later.
		bool not_found = true;
		for(NSString* field_name in parse_support_struct_object.fieldNameArray)
		{
			// increment first since Lua indexing starts at 1
			array_index++;
//			NSLog(@"FieldName:%@", field_name);
			if(!strcmp(index_string, [field_name UTF8String]))
			{
				not_found = false;
				break; // found it
				
			}
		}
		if(not_found)
		{
			luaL_error(lua_state, "Invalid member access of struct:%s __index with unknown key:%s ", [key_name UTF8String], index_string);
		}
	}
	else
	{
		luaL_error(lua_state, "Invalid member access of struct:%s __index", [key_name UTF8String]);
	}
	
	number_of_fields = [parse_support_struct_object.fieldNameArray count];

	// FIXME: If struct fields are considered opaque/hidden, I need to remove them
	// and adjust the index ranges accordingly.
	luaL_argcheck(lua_state, 1 <= array_index && array_index <= number_of_fields, -1, "Index out of range");



	// Now I have to walk the struct to find the value I want.
	// I also have to figure out the type so I can push the correct type to Lua.
	void* struct_userdata = LuaStructBridge_GetStructPointer(lua_state, -2, NULL);
	void* struct_field_ptr = [parse_support_struct_object pointerAtFieldIndex:array_index-1 forStructPtr:struct_userdata];
	ParseSupportStructFieldElement* field_element = [parse_support_struct_object.fieldElementArray objectAtIndex:array_index-1];
	

	bool did_push = true;
	if(false == field_element.isCompositeType)
	{
		// My assertion is that if this is not a compositeType, there is only one value in the array
		NSNumber* boxed_objc_encoding = [field_element.objcEncodingTypeArray objectAtIndex:0];
		char objc_type_encoding = [boxed_objc_encoding charValue];
		
		switch(objc_type_encoding)
		{
			case _C_ID:
			{
				id value_ptr = (id)struct_field_ptr;
				LuaObjectBridge_Pushid(lua_state, value_ptr);
				break;
			}
				
			case _C_CLASS:
			{
				Class value_ptr = (id)struct_field_ptr;
				LuaObjectBridge_PushClass(lua_state, value_ptr);
				break;
			}

			case _C_SEL:
			{
				LuaSelectorBridge_pushselector(lua_state, (SEL)struct_field_ptr);
				break;
			}

			case _C_CHR:
			{
				char* value_ptr = (char*)struct_field_ptr;
				lua_pushinteger(lua_state, (lua_Integer)(*value_ptr));
				break;
			}
			case _C_UCHR:
			{
				unsigned char* value_ptr = (unsigned char*)struct_field_ptr;
				lua_pushinteger(lua_state, (lua_Integer)(*value_ptr));
				break;
			}
			case _C_SHT:
			{
				short* value_ptr = (short*)struct_field_ptr;
				lua_pushinteger(lua_state, (lua_Integer)(*value_ptr));
				break;
			}
			case _C_USHT:
			{
				unsigned short* value_ptr = (unsigned short*)struct_field_ptr;
				lua_pushinteger(lua_state, (lua_Integer)(*value_ptr));
				break;
			}
			case _C_INT:
			{
				int* value_ptr = (int*)struct_field_ptr;
				lua_pushinteger(lua_state, (lua_Integer)(*value_ptr));
				break;
			}
			case _C_UINT:
			{
				unsigned int* value_ptr = (unsigned int*)struct_field_ptr;
				lua_pushinteger(lua_state, (lua_Integer)(*value_ptr));
				break;
			}
			case _C_LNG:
			{
				long* value_ptr = (long*)struct_field_ptr;
				lua_pushinteger(lua_state, (lua_Integer)(*value_ptr));
				break;
			}
			case _C_ULNG:
			{
				unsigned long* value_ptr = (unsigned long*)struct_field_ptr;
				lua_pushnumber(lua_state, (lua_Integer)(*value_ptr));
				break;
			}
			case _C_LNG_LNG:
			{
				long long* value_ptr = (long long*)struct_field_ptr;
				lua_pushinteger(lua_state, (lua_Integer)(*value_ptr));
				break;
			}
			case _C_ULNG_LNG:
			{
				unsigned long long* value_ptr = (unsigned long long*)struct_field_ptr;
				lua_pushinteger(lua_state, (lua_Integer)(*value_ptr));
				break;
			}
			case _C_FLT:
			{
				float* value_ptr = (float*)struct_field_ptr;
				lua_pushnumber(lua_state, (lua_Number)(*value_ptr));
				break;
			}
			case _C_DBL:
			{
				double* value_ptr = (double*)struct_field_ptr;
				lua_pushnumber(lua_state, (lua_Number)(*value_ptr));
				break;
			}

			case _C_BOOL:
			{
				_Bool* value_ptr = (_Bool*)struct_field_ptr;
				lua_pushboolean(lua_state, (int)(*value_ptr));
				break;
			}
			
			case _C_VOID:
			{
				// no return value (probably an error if I get here)
				did_push = false;
				break;
			}
			
			case _C_PTR:
			{
				lua_pushlightuserdata(lua_state, struct_field_ptr);
				break;
			}
			
			case _C_CHARPTR:
			{
				lua_pushstring(lua_state, (const char*)struct_field_ptr);
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
				did_push = false;
				luaL_error(lua_state, "Unexpected return type %c for struct:%s __index", objc_type_encoding, [key_name UTF8String]);
			}
		}
	}
	else
	{
		NSString* name_of_return_struct_structname = field_element.compositeName;
		NSString* name_of_return_struct_keyname = field_element.lookupName;
//		NSLog(@"returning struct compositeName:%@", name_of_return_struct);
		
		
		// Change to use reference struct instead of full copy to handle cases like: nsrect.size.width = 10
		void* return_struct_userdata = LuaStructBridge_CreateReferenceStruct(lua_state, absolute_index_of_original_struct, struct_field_ptr, name_of_return_struct_keyname, name_of_return_struct_structname);
		
		// Additional optimization. It is often that accessing a field in a struct is repeated multiple times.
		// nsrect.origin.x = 100; nsrect.origin.y = 200 -- origin is accessed twice.
		// nsrect.origin.x = nsrect.origin.x + 1
		// This optimization will set the real field in Lua with this new reference struct so that the next access won't have to fallback to this metamethod.
		// This is a win for two reasons:
		// 1) We don't have to walk the entire struct again in this metamethod (strcmp shows up as a hotspot in the profiler)
		// 2) We can avoid allocating a new/duplicate userdata.
		// Since we support string keys and numbered indices, we should set both.
		// Note that this will create a circular reference (cycle) between the original struct and its sub-struct.
		// (The rawset creates a strong reference from the original struct to the sub-struct and
		// the sub-struct already has a strong reference to the originating struct.)
		// But since Lua can handle circular references, I think this will be okay.
		// And I don't think anything else will be able to directly intefere with this relationship to cause a leak.

		// CreateReferenceStruct created a environment table that looked like this:
		// env_table = { ["*"] = original_struct_userdata }
		// Note: The cache optimization adds additional stuff so it looks like this:
		// (To get the reference and cache together, we need a 3-level struct box->rect->origin)
		// env_table = { ["*"]=original_box_struct_userdata, [1]=origin_sub_struct, origin=origin_substruct, ...} }

		int absolute_index_of_reference_struct = lua_gettop(lua_state) + -1 + 1;

		lua_getfenv(lua_state, absolute_index_of_original_struct); // pushes the env-table onto the stack (top is left): [env_table return_sub_struct]		
		
		lua_pushvalue(lua_state, absolute_index_of_reference_struct);
		lua_rawseti(lua_state, -2, array_index); // env_table[array_index]=sub_struct

		// Get the key if we need it. (Maybe the user is using array index access instead.)
		if(NULL == index_string)
		{
			index_string =  [[parse_support_struct_object.fieldNameArray objectAtIndex:array_index-1] UTF8String];
		}
		lua_pushstring(lua_state, index_string);
		lua_pushvalue(lua_state, absolute_index_of_reference_struct);
		lua_rawset(lua_state, -3);

		lua_pop(lua_state, 1); // pop the env_table

	}

	if(did_push)
	{
		return 1;
	}
	else
	{
		return 0;
	}
}

// start_absolute_stack_position = key
// end_absolute_stack_position = value
static int LuaStructBridge_SetValueInStruct(lua_State* lua_state, void* the_struct, ParseSupportStruct* parse_support_struct, int start_absolute_stack_position, int end_absolute_stack_position)
{
	
	// Parse support
	NSString* key_name = parse_support_struct.keyName;
	NSUInteger number_of_fields = [parse_support_struct.fieldNameArray count];
	int stack_position_for_key = start_absolute_stack_position;
	int stack_position_for_value = end_absolute_stack_position;
	int array_index = 0;
	if(lua_isnumber(lua_state, stack_position_for_key))
	{
		array_index = lua_tointeger(lua_state, stack_position_for_key);
	}
	else if(lua_isstring(lua_state, stack_position_for_key))
	{
		const char* index_string = lua_tostring(lua_state, stack_position_for_key);
		
		// Use parse support to find and enumerate where the element resides in the struct.
		// Save this as an array_index for convenience later.
		bool not_found = true;
		for(NSString* field_name in parse_support_struct.fieldNameArray)
		{
			// increment first since Lua indexing starts at 1
			array_index++;
			//			NSLog(@"FieldName:%@", field_name);
			if(!strcmp(index_string, [field_name UTF8String]))
			{
				not_found = false;
				break; // found it
				
			}
		}
		if(not_found)
		{
			luaL_error(lua_state, "Invalid member access of struct:%s LuaStructBridge_SetValueInStruct with unknown key:%s ", [key_name UTF8String], index_string);
		}
	}
	else
	{
		luaL_error(lua_state, "Invalid member access of struct:%s LuaStructBridge_SetValueInStruct", [key_name UTF8String]);
	}
	// FIXME: If struct fields are considered opaque/hidden, I need to remove them
	// and adjust the index ranges accordingly.
	luaL_argcheck(lua_state, 1 <= array_index && array_index <= number_of_fields, -1, "Index out of range");
	
	
	// Now I have to walk the struct to find the value I want.
	// I also have to figure out the type so I can push the correct type to Lua.
	void* struct_field_ptr = [parse_support_struct pointerAtFieldIndex:array_index-1 forStructPtr:the_struct];
	ParseSupportStructFieldElement* field_element = [parse_support_struct.fieldElementArray objectAtIndex:array_index-1];
	
	if(false == field_element.isCompositeType)
	{
		// My assertion is that if this is not a compositeType, there is only one value in the array
		NSNumber* boxed_objc_encoding = [field_element.objcEncodingTypeArray objectAtIndex:0];
		char objc_type_encoding = [boxed_objc_encoding charValue];
		
		switch(objc_type_encoding)
		{
			case _C_ID:
			{
				// FIXME: Do I need to release the old instance and retain the new instance?
				id value_ptr = (id)struct_field_ptr;
				value_ptr = (id)LuaObjectBridge_checkid(lua_state, stack_position_for_value);
			}
			case _C_CLASS:
			{
				id value_ptr = (id)struct_field_ptr;
				value_ptr = (id)LuaObjectBridge_checkid(lua_state, stack_position_for_value);
				break;
				
			}
			case _C_SEL:
			{
				SEL value_ptr = (SEL)struct_field_ptr;
				value_ptr = LuaSelectorBridge_checkselector(lua_state, stack_position_for_value);
				break;
			}
				
			case _C_CHR:
			{
				char* value_ptr = (char*)struct_field_ptr;
				*value_ptr = (char)luaL_checkinteger(lua_state, stack_position_for_value);
				break;
			}
			case _C_UCHR:
			{
				unsigned char* value_ptr = (unsigned char*)struct_field_ptr;
				*value_ptr = (unsigned char)luaL_checkinteger(lua_state, stack_position_for_value);
				break;
			}
			case _C_SHT:
			{
				short* value_ptr = (short*)struct_field_ptr;
				*value_ptr = (short)luaL_checkinteger(lua_state, stack_position_for_value);
				break;
			}
			case _C_USHT:
			{
				unsigned short* value_ptr = (unsigned short*)struct_field_ptr;
				*value_ptr = (unsigned short)luaL_checkinteger(lua_state, stack_position_for_value);
				break;
			}
			case _C_INT:
			{
				int* value_ptr = (int*)struct_field_ptr;
				*value_ptr = (int)luaL_checkinteger(lua_state, stack_position_for_value);
				break;
			}
			case _C_UINT:
			{
				unsigned int* value_ptr = (unsigned int*)struct_field_ptr;
				*value_ptr = (unsigned int)luaL_checkinteger(lua_state, stack_position_for_value);
				break;
			}
			case _C_LNG:
			{
				long* value_ptr = (long*)struct_field_ptr;
				*value_ptr = (long)luaL_checklong(lua_state, stack_position_for_value);
				break;
			}
			case _C_ULNG:
			{
				unsigned long* value_ptr = (unsigned long*)struct_field_ptr;
				*value_ptr = (unsigned long)luaL_checklong(lua_state, stack_position_for_value);
				break;
			}
			case _C_LNG_LNG:
			{
				long long* value_ptr = (long long*)struct_field_ptr;
				*value_ptr = (long long)luaL_checklong(lua_state, stack_position_for_value);
				break;
			}
			case _C_ULNG_LNG:
			{
				unsigned long long* value_ptr = (unsigned long long*)struct_field_ptr;
				*value_ptr = (unsigned long long)luaL_checklong(lua_state, stack_position_for_value);
				break;
			}
			case _C_FLT:
			{
				float* value_ptr = (float*)struct_field_ptr;
				*value_ptr = (float)luaL_checknumber(lua_state, stack_position_for_value);
				break;
			}
			case _C_DBL:
			{
				double* value_ptr = (double*)struct_field_ptr;
				*value_ptr = (double)luaL_checknumber(lua_state, stack_position_for_value);
				break;
			}
				
			case _C_BOOL:
			{
				_Bool* value_ptr = (_Bool*)struct_field_ptr;
				*value_ptr = (_Bool)LuaCUtils_checkboolean(lua_state, stack_position_for_value);
				break;
			}
				
			case _C_VOID:
			{
				// no value (probably an error if I get here)
				break;
			}
				
			case _C_PTR:
			{
				const void* new_userdata = LuaCUtils_checklightuserdata(lua_state, stack_position_for_value);
				NSString* name_of_return_struct = field_element.compositeName;
				size_t size_of_return_struct = [ParseSupport sizeOfStructureFromStructureName:name_of_return_struct];				

				memcpy(struct_field_ptr, new_userdata, size_of_return_struct);
				break;
			}
				
			case _C_CHARPTR:
			{
				NSLog(@"Warning: assigning Lua string to _C_CHARPTR. Not sure how to handle this...strcpy or pointer assign.");
				// strcpy seems really dangerous for overflow reasons.
				// Do pointer assign instead?
				const void* new_userdata = LuaCUtils_checklightuserdata(lua_state, stack_position_for_value);
				NSString* name_of_return_struct = field_element.compositeName;
				size_t size_of_return_struct = [ParseSupport sizeOfStructureFromStructureName:name_of_return_struct];				
				
				memcpy(struct_field_ptr, new_userdata, size_of_return_struct);
				
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
				luaL_error(lua_state, "Unexpected return type %c for struct:%s LuaStructBridge_SetValueInStruct", objc_type_encoding, [key_name UTF8String]);
			}
		}
	}
	else
	{
		NSString* name_of_return_struct_structname = field_element.compositeName;
		NSString* name_of_return_struct_keyname = field_element.lookupName;
		if(nil == name_of_return_struct_keyname)
		{
			return luaL_error(lua_state, "Could not find struct:%s in loaded BridgeSupport", [name_of_return_struct_structname UTF8String]);
		}
		
//		NSLog(@"returning struct compositeName:%@, %@, %@", name_of_return_struct, field_element, field_element.compositeName);
		size_t size_of_return_struct = [ParseSupport sizeOfStructureFromStructureName:name_of_return_struct_keyname];				
//		NSLog(@"size_of_return_struct:%d", size_of_return_struct);

		// TODO: Should try coercing tables as convenience
		if(lua_istable(lua_state, stack_position_for_value))
		{
			
			ParseSupportStruct* parse_support_sub_struct = [ParseSupportStruct parseSupportStructFromKeyName:name_of_return_struct_keyname];
			// Need a struct to fill but can only use a blob of memory at runtime.
			// Use VLA to keep memory on the stack
			int8_t sub_struct_ptr[size_of_return_struct];


			// Going to do recursion. Make sure the stack is large enough.
			lua_checkstack(lua_state, 2); // lua_next will pop the key and push a key-value, thus we need 2 more slots
			/* table is in the stack at index 't' */
			lua_pushnil(lua_state);  /* first key */
			while(lua_next(lua_state, stack_position_for_value) != 0)
			{
				/* uses 'key' (at index -2) and 'value' (at index -1) */
				int new_end_absolute_stack_position = lua_gettop(lua_state);
				int new_start_absolute_stack_position = new_end_absolute_stack_position - 1;
				// Recursively do this again to parse through the sub-struct
				LuaStructBridge_SetValueInStruct(lua_state, sub_struct_ptr, parse_support_sub_struct, new_start_absolute_stack_position, new_end_absolute_stack_position);

				/* removes 'value'; keeps 'key' for next iteration */
				lua_pop(lua_state, 1);
			}

			// Fall through. Checks okay.
			memcpy(struct_field_ptr, sub_struct_ptr, size_of_return_struct);
			
		}
		else if(lua_isuserdata(lua_state, stack_position_for_value))
		{
			// Verify the userdata is the same type.
			// TODO: Might want to inspect primitive types of struct for comparison if userdata type check fails.
			// This will allow bridging of types like NSPoint and CGPoint. 
			// However, this will also allow abuse of bridging NSPoint and NSSize.
			
			NSString* new_userdata_struct_name = LuaStructBridge_GetBridgeStructNameFromMetatable(lua_state, stack_position_for_value);
			NSString* new_userdata_struct_keyname = LuaStructBridge_GetBridgeKeyNameFromMetatable(lua_state, stack_position_for_value);
//			NSLog(@"new_userdata_struct_name=%@, new_userdata_struct_keyname=%@", new_userdata_struct_name, new_userdata_struct_keyname);
			if(NULL == new_userdata_struct_name)
			{
				// This is not a LuaStructBridge object so abort with error
				// luaL_typeerror is what luaL_checkudata calls. Seems appropriate.
				return luaL_typerror(lua_state, -3, LUASTRUCTBRIDGE_BRIDGESUPPORT_STRUCTNAME);
			}
			else if(![new_userdata_struct_name isEqualToString:name_of_return_struct_structname])
			{
				//				luaL_typerror(lua_state, stack_position_for_value, [name_of_return_struct UTF8String]);			
				return luaL_error(lua_state, "Invalid type error assignment of struct:%s LuaStructBridge_SetValueInStruct with. Expecting type of %s, got %s", [key_name UTF8String], [name_of_return_struct_structname UTF8String], [new_userdata_struct_name UTF8String]);
				
			}
			// Fall through. Checks okay.
			void* new_userdata = LuaStructBridge_GetStructPointer(lua_state, stack_position_for_value, NULL);
			memcpy(struct_field_ptr, new_userdata, size_of_return_struct);
			
		}
		else
		{
			return luaL_error(lua_state, "rvalue should be userdata for struct:%s LuaStructBridge_SetValueInStruct", [key_name UTF8String]);

		}
		
	}
	
	
	
	return 0;
}

static void LuaStructBridge_SetPrimitiveValueForEncoding(lua_State* lua_state, char objc_type_encoding, void* struct_field_ptr,  int stack_position_for_value)
{
	switch(objc_type_encoding)
	{
		case _C_ID:
		{
			// FIXME: Do I need to release the old instance and retain the new instance?
			// FIXME: Should I be using topropertylist? Note the lack of retain will probably make this dangerous.
			id value_ptr = (id)struct_field_ptr;
			value_ptr = (id)LuaObjectBridge_checkid(lua_state, stack_position_for_value);
		}
		case _C_CLASS:
		{
			id value_ptr = (id)struct_field_ptr;
			value_ptr = (id)LuaObjectBridge_checkid(lua_state, stack_position_for_value);
			break;
			
		}
		case _C_SEL:
		{
			SEL value_ptr = (SEL)struct_field_ptr;
			value_ptr = LuaSelectorBridge_checkselector(lua_state, stack_position_for_value);
			break;
		}
			
		case _C_CHR:
		{
			char* value_ptr = (char*)struct_field_ptr;
			*value_ptr = (char)luaL_checkinteger(lua_state, stack_position_for_value);
			break;
		}
		case _C_UCHR:
		{
			unsigned char* value_ptr = (unsigned char*)struct_field_ptr;
			*value_ptr = (unsigned char)luaL_checkinteger(lua_state, stack_position_for_value);
			break;
		}
		case _C_SHT:
		{
			short* value_ptr = (short*)struct_field_ptr;
			*value_ptr = (short)luaL_checkinteger(lua_state, stack_position_for_value);
			break;
		}
		case _C_USHT:
		{
			unsigned short* value_ptr = (unsigned short*)struct_field_ptr;
			*value_ptr = (unsigned short)luaL_checkinteger(lua_state, stack_position_for_value);
			break;
		}
		case _C_INT:
		{
			int* value_ptr = (int*)struct_field_ptr;
			*value_ptr = (int)luaL_checkinteger(lua_state, stack_position_for_value);
			break;
		}
		case _C_UINT:
		{
			unsigned int* value_ptr = (unsigned int*)struct_field_ptr;
			*value_ptr = (unsigned int)luaL_checkinteger(lua_state, stack_position_for_value);
			break;
		}
		case _C_LNG:
		{
			long* value_ptr = (long*)struct_field_ptr;
			*value_ptr = (long)luaL_checklong(lua_state, stack_position_for_value);
			break;
		}
		case _C_ULNG:
		{
			unsigned long* value_ptr = (unsigned long*)struct_field_ptr;
			*value_ptr = (unsigned long)luaL_checklong(lua_state, stack_position_for_value);
			break;
		}
		case _C_LNG_LNG:
		{
			long long* value_ptr = (long long*)struct_field_ptr;
			*value_ptr = (long long)luaL_checklong(lua_state, stack_position_for_value);
			break;
		}
		case _C_ULNG_LNG:
		{
			unsigned long long* value_ptr = (unsigned long long*)struct_field_ptr;
			*value_ptr = (unsigned long long)luaL_checklong(lua_state, stack_position_for_value);
			break;
		}
		case _C_FLT:
		{
			float* value_ptr = (float*)struct_field_ptr;
			*value_ptr = (float)luaL_checknumber(lua_state, stack_position_for_value);
			break;
		}
		case _C_DBL:
		{
			double* value_ptr = (double*)struct_field_ptr;
			*value_ptr = (double)luaL_checknumber(lua_state, stack_position_for_value);
			break;
		}
			
		case _C_BOOL:
		{
			_Bool* value_ptr = (_Bool*)struct_field_ptr;
			*value_ptr = (_Bool)LuaCUtils_checkboolean(lua_state, stack_position_for_value);
			break;
		}
			
		case _C_VOID:
		{
			// no value (probably an error if I get here)
			break;
		}
			
		case _C_PTR:
		{
			//		const void* new_userdata = LuaCUtils_checklightuserdata(lua_state, stack_position_for_value);
			//		NSString* name_of_return_struct = field_element.compositeName;
			//		size_t size_of_return_struct = [ParseSupport sizeOfStructureFromStructureName:name_of_return_struct];				
			
			//		memcpy(struct_field_ptr, new_userdata, size_of_return_struct);
			const void* value_ptr = (const void*)struct_field_ptr;
			value_ptr = LuaCUtils_checklightuserdata(lua_state, stack_position_for_value);
			
			break;
		}
			
		case _C_CHARPTR:
		{
//			NSLog(@"Warning: assigning Lua string to _C_CHARPTR. Not sure how to handle this...strcpy or pointer assign.");
			// strcpy seems really dangerous for overflow reasons.
			// Do pointer assign instead?
			//				const void* new_userdata = LuaCUtils_checklightuserdata(lua_state, stack_position_for_value);
			//				NSString* name_of_return_struct = field_element.compositeName;
			//				size_t size_of_return_struct = [ParseSupport sizeOfStructureFromStructureName:name_of_return_struct];				
			
			//				memcpy(struct_field_ptr, new_userdata, size_of_return_struct);
			
			const char* value_ptr = (const char*)struct_field_ptr;
			value_ptr = luaL_checkstring(lua_state, stack_position_for_value);
			
			
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
			luaL_error(lua_state, "Unexpected return type %c in LuaStructBridge_SetPrimitiveValueForEncoding", objc_type_encoding);
		}
	}
}

static void LuaStructBridge_ParseAndCopyPrimitiveStructValuesFromTableArray(lua_State* lua_state, void* the_struct, ParseSupportStruct* parse_support_struct, NSArray* primitive_objc_type_encodings_array, NSUInteger primitive_element_count, int start_absolute_stack_position)
{
	// Bleh. Too much duplicated code.
	
	void* struct_field_ptr = the_struct;
	
	int top0 = lua_gettop(lua_state);

	lua_pushnil(lua_state);  /* first key */
	int stack_position_for_value = -1; // will always be at the top of the stack
	for(NSString* current_objc_encoding in primitive_objc_type_encodings_array)
	{
		lua_next(lua_state, start_absolute_stack_position);
		char objc_type_encoding = [current_objc_encoding UTF8String][0];

		LuaStructBridge_SetPrimitiveValueForEncoding(lua_state, objc_type_encoding, struct_field_ptr, stack_position_for_value);

		struct_field_ptr = StructSupport_AlignPointer(struct_field_ptr, objc_type_encoding);
		struct_field_ptr = StructSupport_AdvancePointer(struct_field_ptr, objc_type_encoding);

		lua_pop(lua_state, 1);
	}
	// need one more pop to rebalance because lua_next is not called the 
	// last time to completion since I use the NSArray count as the termination condition
	lua_pop(lua_state, 1);

	int top1 = lua_gettop(lua_state);
	assert(top0 == top1);
	
		
}

static void LuaStructBridge_ParseAndCopyPrimitiveStructValuesFromArgumentList(lua_State* lua_state, void* the_struct, ParseSupportStruct* parse_support_struct, NSArray* primitive_objc_type_encodings_array, NSUInteger primitive_element_count, int start_absolute_stack_position)
{
	// Bleh. Too much duplicated code.
	
	void* struct_field_ptr = the_struct;
	int stack_position_for_value = start_absolute_stack_position;
	for(NSString* current_objc_encoding in primitive_objc_type_encodings_array)
	{
		char objc_type_encoding = [current_objc_encoding UTF8String][0];
		
		LuaStructBridge_SetPrimitiveValueForEncoding(lua_state, objc_type_encoding, struct_field_ptr, stack_position_for_value);
		
		struct_field_ptr = StructSupport_AlignPointer(struct_field_ptr, objc_type_encoding);
		struct_field_ptr = StructSupport_AdvancePointer(struct_field_ptr, objc_type_encoding);
		stack_position_for_value++;
	}
	
	
}


/* Used to parse parameters for new struct values via constructor functions or __call. */
/* Pointer to struct must point to valid struct. Function will fill in values for struct. */	
static void LuaStructBridge_ParseAndCopyStructValues(lua_State* lua_state, void* the_struct, ParseSupportStruct* parse_support_struct, int number_of_args, int start_absolute_stack_position)
{
	//	size_t size_of_return_struct = [ParseSupport sizeOfStructureFromStructureName:name_of_return_struct];					
	size_t size_of_struct = [parse_support_struct sizeOfStruct];
	// Allow empty to represent a zero'ed out struct
	if(0 == number_of_args)
	{
		bzero(the_struct, size_of_struct);
		return;
	}
	// Copy an existing struct to a new one
	// In C, assigning a struct copies the properties into the receiever.
	// Since in Lua, we only get a reference back, a way to copy is useful.
	// So I am overloading this function to do this also if you provide an existing one as a parameter.	
	else if(1 == number_of_args && lua_isuserdata(lua_state, start_absolute_stack_position))
	{
//		NSString* key_name = LuaStructBridge_GetBridgeKeyNameFromMetatable(lua_state, start_absolute_stack_position);
		NSString* struct_name = LuaStructBridge_GetBridgeStructNameFromMetatable(lua_state, start_absolute_stack_position);
		if(NULL == struct_name)
		{
			// This is not a LuaStructBridge object so abort with error
			// luaL_typeerror is what luaL_checkudata calls. Seems appropriate.
			luaL_typerror(lua_state, start_absolute_stack_position, LUASTRUCTBRIDGE_BRIDGESUPPORT_STRUCTNAME);
		}
		else if([struct_name isNotEqualTo:parse_support_struct.structName])
		{
			// FIXME: Do we want to handle automatic conversion for types of the same signature?
			// This would allow NSPoint<->CGPoint, but this would also open the door to NSPoint<->NSSize
			luaL_typerror(lua_state, start_absolute_stack_position, LUASTRUCTBRIDGE_BRIDGESUPPORT_STRUCTNAME);
		}
		void* source_struct = LuaStructBridge_GetStructPointer(lua_state, start_absolute_stack_position, NULL);
		memcpy(the_struct, source_struct, sizeof(size_of_struct));
		return;
	}
	
	else if(1 == number_of_args && lua_istable(lua_state, start_absolute_stack_position))
	{
		// Several different cases:
		// 1) We have an array containing a list of all primitive elements.
		// 2) We have an array containing a list of all field (composite) elements
		// 3) We have a dictionary or hodgepodge of things.

		// To determine which of the cases, we need to iterate through the table and figure out what we have
		NSUInteger item_count = 0;
		bool is_array = true;
		int top0 = lua_gettop(lua_state);
		lua_pushnil(lua_state);  /* first key */
		while (lua_next(lua_state, start_absolute_stack_position) != 0)
		{
			item_count++;
			if(LUA_TNUMBER == lua_type(lua_state, -2) && (lua_tointeger(lua_state, -2) == item_count))
			{
				lua_pop(lua_state, 1);
			}
			else
			{
				is_array = false;
				lua_pop(lua_state, 2); // need to pop 1 extra because I won't be calling lua_next again which pops 1
				break;
			}

		}
		
		int top1 = lua_gettop(lua_state);
		assert(top0 == top1);
		
		if(true == is_array)
		{
			NSUInteger field_element_count = [parse_support_struct.fieldElementArray count];
			NSArray* primitive_objc_type_encodings_array = [ParseSupport typeEncodingsFromStructureName:parse_support_struct.keyName];
			NSUInteger primitive_element_count = [primitive_objc_type_encodings_array count];
			if(item_count == primitive_element_count)
			{
				LuaStructBridge_ParseAndCopyPrimitiveStructValuesFromTableArray(lua_state, the_struct, parse_support_struct, primitive_objc_type_encodings_array, primitive_element_count, start_absolute_stack_position);
				return;
			}
			else if(item_count == field_element_count)
			{
				// The existing general implementation can already handle this case
				// Let this fall through to main case
			}
			else
			{
				// Don't know how to handle this.
				luaL_error(lua_state, "Unexpected number of arguments (%d) in array for LuaStructBridge_ParseAndCopyStructValues", item_count);
			}
		}

		/* table is in the stack at index 'start_absolute_stack_position' */
		lua_pushnil(lua_state);  /* first key */
		while (lua_next(lua_state, start_absolute_stack_position) != 0) {
			/* uses 'key' (at index -2) and 'value' (at index -1) */
			printf("%s - %s\n",
				   lua_typename(lua_state, lua_type(lua_state, -2)),
				   lua_typename(lua_state, lua_type(lua_state, -1)));
			
			if(LUA_TNUMBER == lua_type(lua_state, -2))
			{
				// Consider it an array index, NSSize({1.0, 2.0}) or explicitly NSSize({[1]=1.0, [2]=2.0})
				// This could be optimized if we were willing to assume all
				// keys in the table were a contiguous and properly ordered array.
				// Calling the set element function requires a struct walk each call which may be a little slow.
				// But hopefully struct constructions are usually small and infrequent.
				int current_stack_top = lua_gettop(lua_state);
				int new_stack_end_position = current_stack_top;
				int new_stack_start_position = new_stack_end_position - 1;
				LuaStructBridge_SetValueInStruct(lua_state, the_struct, parse_support_struct, new_stack_start_position, new_stack_end_position);
				
			}
			else if(LUA_TSTRING == lua_type(lua_state, -2))
			{
				// User specified keys like NSSize({width=1.0, height=2.0})
				// Since Lua (non-array) tables are not ordered, we may not be filling the struct in natural order.
				// This implies walking the struct for each field.
				int current_stack_top = lua_gettop(lua_state);
				int new_stack_end_position = current_stack_top;
				int new_stack_start_position = new_stack_end_position - 1;
				LuaStructBridge_SetValueInStruct(lua_state, the_struct, parse_support_struct, new_stack_start_position, new_stack_end_position);		
			}
			else
			{
				luaL_error(lua_state, "Unexpected type: %s in table for LuaStructBridge_ParseAndCopyStructValues", lua_typename(lua_state, lua_type(lua_state, -2)));
			}
			
			//		size_t size_of_return_struct = [ParseSupport sizeOfStructureFromStructureName:name_of_return_struct];				
			//		static int LuaStructBridge_SetValueInStruct(lua_State* lua_state, void* the_struct, ParseSupportStruct* parse_support_struct, int start_absolute_stack_position, int end_absolute_stack_position)
			/*
			 else if(LUA_TUSERDATA == lua_type(lua_state, -1))
			 {
			 // User specified a userdata which is hopefully the correct type
			 // local my_point = NSMakePoint(1.0, 2.0)
			 // local my_size = NSMakeSize(100.0, 200.0)
			 // NSRect({ origin=my_point, [2]=my_size})
			 }
			 else if(LUA_TTABLE == lua_type(lua_state, -1))
			 {
			 // User specified a table
			 // local my_point = NSMakePoint(1.0, 2.0)
			 // local my_size = NSMakeSize(100.0, 200.0)
			 // NSRect({ origin={1.0, 2.0}, [2]={width=100.0, size=200.0} })
			 // Strategy: Using parse support
			 } 
			 */				   
			/* removes 'value'; keeps 'key' for next iteration */
			lua_pop(lua_state, 1);
		}
	}
	// Want to handle a argument list of parameters. 
	else if(number_of_args > 1)
	{
		NSUInteger field_element_count = [parse_support_struct.fieldElementArray count];
		NSArray* primitive_objc_type_encodings_array = [ParseSupport typeEncodingsFromStructureName:parse_support_struct.keyName];
		NSUInteger primitive_element_count = [primitive_objc_type_encodings_array count];
		
		if(number_of_args == primitive_element_count)
		{
			LuaStructBridge_ParseAndCopyPrimitiveStructValuesFromArgumentList(lua_state, the_struct, parse_support_struct, primitive_objc_type_encodings_array, primitive_element_count, start_absolute_stack_position);
			return;
		}
		else if(number_of_args == field_element_count)
		{
			int top0 = lua_gettop(lua_state);

			// The existing general implementation can already handle this case for tables.
			// I rather just nest the elements in a table and recursively handle this.
			lua_checkstack(lua_state, 3); // is it really 3? table+key+value?
			lua_newtable(lua_state);
			int table_index = lua_gettop(lua_state);
			for(int current_arg_index=start_absolute_stack_position, current_arg_count=0; current_arg_count < number_of_args ; current_arg_index++, current_arg_count++)
			{
				lua_pushvalue(lua_state, current_arg_index);
				lua_rawseti(lua_state, table_index, current_arg_count+1); // add 1 because Lua arrays start at 1, not 0
			}
			LuaStructBridge_ParseAndCopyStructValues(lua_state, the_struct, parse_support_struct, 1, table_index);
			lua_pop(lua_state, 1); // pop the table
			
			int top1 = lua_gettop(lua_state);
			assert(top0 == top1);
			
			return;
						
		}
		else
		{
			// Don't know how to handle this.
			luaL_error(lua_state, "Unexpected number of arguments (%d) in array for LuaStructBridge_ParseAndCopyStructValues", number_of_args);
		}
		

	}
	// There is also the possibility of a 1-element struct comprised of a primitive type
	else if(1 == number_of_args)
	{
		NSUInteger field_element_count = [parse_support_struct.fieldElementArray count];
		if(1 == field_element_count)
		{
			NSArray* primitive_objc_type_encodings_array = [ParseSupport typeEncodingsFromStructureName:parse_support_struct.keyName];
			LuaStructBridge_ParseAndCopyPrimitiveStructValuesFromArgumentList(lua_state, the_struct, parse_support_struct, primitive_objc_type_encodings_array, 1, start_absolute_stack_position);
		}
		else
		{
			luaL_error(lua_state, "Invalid parameters to create struct: %s", [parse_support_struct.keyName UTF8String]);
		}

	}
	else
	{
	
		luaL_error(lua_state, "Invalid parameters to create struct: %s", [parse_support_struct.keyName UTF8String]);
	}
}


// Tied to __call,
// so given a userdata, can set all values in one shot
// 	ca_transform({1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16})
static int LuaStructBridge_SetValuesFromFunctionCall(lua_State* lua_state)
{
	NSString* struct_name = LuaStructBridge_GetBridgeStructNameFromMetatable(lua_state, 1);
	if(NULL == struct_name)
	{
		// This is not a LuaStructBridge object so abort with error
		// luaL_typeerror is what luaL_checkudata calls. Seems appropriate.
		luaL_typerror(lua_state, 1, LUASTRUCTBRIDGE_BRIDGESUPPORT_STRUCTNAME);
	}
	NSString* key_name = LuaStructBridge_GetBridgeKeyNameFromMetatable(lua_state, 1);
	void* the_struct = LuaStructBridge_GetStructPointer(lua_state, 1, NULL);
	
//	int new_end_absolute_stack_position = lua_gettop(lua_state);
	int number_of_args = lua_gettop(lua_state) - 1; // subtract one to exclude the userdata

#if LUAOBJECTBRIDGE_ENABLE_GETTER_DOT_NOTATION
	#if !LUAOBJECTBRIDGE_GETTER_DOT_NOTATION_SUPPORT_ONLY_ID_TYPES
	// Instead of making my_rect() clear all values to 0,
	// simply return the struct itself. This makes it possible to handle dot notation followed by empty parenthesis
	// my_point = self:bounds().point

	// Weird: I don't understand this. HELP!!! 
	//	NSLog(@"1: %s, 2: %s", lua_typename(lua_state, 1), lua_typename(lua_state, 2));
	// prints  1: boolean, 2: userdata
	// But 
	// NSLog(@"1: %d, 2: %d", lua_type(lua_state, 1), lua_type(lua_state, 2));
	// prints 1: 7, 2: 7
	// And I don't understand why I get more than just the struct on the stack if there are no parameters.
	if(1 == number_of_args)
	{
		if(LUA_TUSERDATA == lua_type(lua_state, 1) && LUA_TUSERDATA == lua_type(lua_state, 2))
		{
			lua_pushvalue(lua_state, 1);
//			lua_replace(lua_state, 1);
		}

		return 1;
	}
	#endif // !LUAOBJECTBRIDGE_GETTER_DOT_NOTATION_SUPPORT_ONLY_ID_TYPES
#endif // LUAOBJECTBRIDGE_ENABLE_GETTER_DOT_NOTATION
	
	int new_start_absolute_stack_position = 2; // start after the user data
	ParseSupportStruct* parse_support_struct = [ParseSupportStruct parseSupportStructFromKeyName:key_name];
	
	LuaStructBridge_ParseAndCopyStructValues(lua_state, the_struct, parse_support_struct, number_of_args, new_start_absolute_stack_position);
	return 0;
}


// obj_index = 3/-1 is the new value
// obj_index = 2/-2 is key or index
// obj_index = 1/-3 is the userdata
static int LuaStructBridge_SetIndexOnStruct(lua_State* lua_state)
{
	//	const char* key_name = LuaStructBridge_GetBridgeKeyNameFromMetatable(lua_state, -2);
	NSString* struct_name = LuaStructBridge_GetBridgeStructNameFromMetatable(lua_state, -3);
	if(NULL == struct_name)
	{
		// This is not a LuaStructBridge object so abort with error
		// luaL_typeerror is what luaL_checkudata calls. Seems appropriate.
		luaL_typerror(lua_state, -3, LUASTRUCTBRIDGE_BRIDGESUPPORT_STRUCTNAME);
	}
	NSString* key_name = LuaStructBridge_GetBridgeKeyNameFromMetatable(lua_state, -3);
	void* struct_userdata = LuaStructBridge_GetStructPointer(lua_state, -3, NULL);
	
	// Parse support
	ParseSupportStruct* parse_support_struct_object = [ParseSupportStruct parseSupportStructFromKeyName:key_name];
	return LuaStructBridge_SetValueInStruct(lua_state, struct_userdata, parse_support_struct_object, 2, 3);
}




/*
 function LuaCocoa.GenerateStructConstructorByName(struct_name)
 local return_function = function(...)
 return LuaCocoa.ConstructStruct(...)
 end
 end
 
 */

// All parameters go to struct construction. Variable number of parameters.
// upvalue index 1: struct name
static int LuaStructBridge_InvokeStructConstructor(lua_State* lua_state)
{
	const char* struct_keyname_cstr = luaL_checkstring(lua_state, lua_upvalueindex(1));
	if(NULL == struct_keyname_cstr)
	{
		return luaL_error(lua_state, "Struct name is NULL in LuaStructBridge_GenerateStructConstructorByName");
	}
	NSString* struct_keyname_nsstring = [NSString stringWithUTF8String:struct_keyname_cstr];
	ParseSupportStruct* parse_support_struct = [ParseSupportStruct parseSupportStructFromKeyName:struct_keyname_nsstring];
	if(nil == parse_support_struct)
	{
		return luaL_error(lua_state, "Struct name: %s is not in BridgeSupport database in LuaStructBridge_GenerateStructConstructorByName", struct_keyname_cstr);
	}
	int number_of_args = lua_gettop(lua_state);
	size_t size_of_struct = [parse_support_struct sizeOfStruct];

	// Allocate memory for the struct
	void* return_struct_userdata = lua_newuserdata(lua_state, size_of_struct);

	// stack: [MyMatrix2 index MyVector table]
	lua_newtable(lua_state); // create a new environment table for the struct. This will simply assumptions for sub-struct caching.
	lua_setfenv(lua_state, -2);  // Makes the table on top of the stack the environment table for the new struct
	
	
	
	// Fetch the metatable for this struct type and apply it to the struct so the Lua scripter can access the fields
	LuaStructBridge_SetStructMetatableOnUserdata(lua_state, -1, struct_keyname_nsstring, parse_support_struct.structName);

	LuaStructBridge_ParseAndCopyStructValues(lua_state, return_struct_userdata, parse_support_struct, number_of_args, 1);

	return 1;
	
}

// stack_position 1: string containing key name
static int LuaStructBridge_GenerateStructConstructorByName(lua_State* lua_state)
{
	// Create a new closure (function) to be returned which will be invoked.
	// It includes an upvalue containing the "key" (struct keyName) so we can retrieve it later
	// The assumption is that this string (key) is on the top of the stack.
	lua_pushcclosure(lua_state, LuaStructBridge_InvokeStructConstructor, 1);
	return 1;
}
// Generates an alias constructor function for easy use in Lua. Essentially,
// NSRect = LuaCocoa.GenerateStructConstructorByName("NSRect")
// Then the user can do:
// local my_rect = NSRect(1.0, 2.0, 3.0, 4.)
void LuaStructBridge_GenerateAliasStructConstructor(lua_State* lua_state, NSString* struct_name)
{
	lua_getfield(lua_state, LUA_GLOBALSINDEX,"LuaCocoa");
	lua_pushliteral(lua_state, "GenerateStructConstructorByName");
	lua_gettable(lua_state, -2);
	lua_remove(lua_state, -2);
	lua_pushstring(lua_state, [struct_name UTF8String]);
	lua_call(lua_state, 1,1);
	lua_setfield(lua_state, LUA_GLOBALSINDEX, [struct_name UTF8String]);	
}

/* // Just for verifying memory cleanup works 
int LuaStructBridge_GC(lua_State* lua_state)
{
	NSLog(@"In LuaStructBridge_GC");
	return 0;
}
*/
static const struct luaL_reg LuaStructBridge_MethodsForStructMetatable[] =
{
	{"__tostring", LuaStructBridge_ConvertStructToString},
//	{"__eq", CompareEqualOnCATransform3D},
	{"__call", LuaStructBridge_SetValuesFromFunctionCall},
	{"__index", LuaStructBridge_GetIndexOnStruct},
	{"__newindex", LuaStructBridge_SetIndexOnStruct},
//	{"__gc", LuaStructBridge_GC}, // only for debugging memory leaks
	{NULL,NULL},
};

static const struct luaL_reg LuaStructBridge_FunctionsForStruct[] =
{
	{"GenerateStructConstructorByName", LuaStructBridge_GenerateStructConstructorByName},
	{NULL,NULL},
};


int luaopen_LuaStructBridge(lua_State* lua_state)
{
	luaL_register(lua_state, "LuaCocoa", LuaStructBridge_FunctionsForStruct);

	return 1;
}

// My attempt at an isstruct function
bool LuaStructBridge_isstruct(lua_State* lua_state, int obj_index)
{
	// Since I don't have the metatable name, I can't use luaL_getmetatable.
	// So I am going more low-level and using lua_getmetable and then will
	// extract a string from the private field I created on creation which
	// contains the string keyname I seek.
	//	const char* key_name = NULL;
	bool is_struct = false;
	if(lua_getmetatable(lua_state, obj_index))  /* does userdata have a metatable? */
	{
		lua_getfield(lua_state, -1, LUASTRUCTBRIDGE_BRIDGESUPPORT_STRUCTNAME);
		if(lua_isstring(lua_state, -1))
		{
			// got the string
			//			key_name = lua_tostring(lua_state, -1);
			is_struct = true;
		}
		lua_pop(lua_state, 2); // pop the string and the metatable
	}
	return is_struct;
}

// This can kind of be used as a checkstruct function, except that it returns the name of the key.
// I can use the key name to look up the BridgeSupport info by name.
// Assumes userdata is at obj_index (standard Lua semantics)
// Note: This function returns a NSString* instead of const char* directly from Lua.
// This avoids the problem of the value being collected by Lua in your life-cycle, 
// since it copies it. Maybe for performance, I shouldn't worry about this since the usage
// tends to be short term. On the other hand, the main map uses NSString anyway.
//const char* LuaStructBridge_GetBridgeKeyNameFromMetatable(lua_State* lua_state, int obj_index)
NSString* LuaStructBridge_GetBridgeKeyNameFromMetatable(lua_State* lua_state, int obj_index)
{
	// Since I don't have the metatable name, I can't use luaL_getmetatable.
	// So I am going more low-level and using lua_getmetable and then will
	// extract a string from the private field I created on creation which
	// contains the string keyname I seek.
//	const char* key_name = NULL;
	NSString* key_name = nil;
	if(lua_getmetatable(lua_state, obj_index))  /* does userdata have a metatable? */
	{
		lua_getfield(lua_state, -1, LUASTRUCTBRIDGE_BRIDGESUPPORT_KEYNAME);
		if(lua_isstring(lua_state, -1))
		{
			// got the string
//			key_name = lua_tostring(lua_state, -1);
			key_name = [NSString stringWithUTF8String:lua_tostring(lua_state, -1)];
		}
		lua_pop(lua_state, 2); // pop the string and the metatable
	}
	return key_name;
}


const char* LuaStructBridge_GetBridgeKeyNameFromMetatableAsString(lua_State* lua_state, int obj_index)
{
	// Since I don't have the metatable name, I can't use luaL_getmetatable.
	// So I am going more low-level and using lua_getmetable and then will
	// extract a string from the private field I created on creation which
	// contains the string keyname I seek.
	const char* key_name = NULL;
	// NSString* key_name = nil;
	if(lua_getmetatable(lua_state, obj_index))  /* does userdata have a metatable? */
	{
		lua_getfield(lua_state, -1, LUASTRUCTBRIDGE_BRIDGESUPPORT_KEYNAME);
		if(lua_isstring(lua_state, -1))
		{
			// got the string
			key_name = lua_tostring(lua_state, -1);
			//			key_name = [NSString stringWithUTF8String:lua_tostring(lua_state, -1)];
		}
		lua_pop(lua_state, 2); // pop the string and the metatable
	}
	return key_name;
}

// This can kind of be used as a checkstruct function, except that it returns the name of the key.
// I can use the key name to look up the BridgeSupport info by name.
// Assumes userdata is at obj_index (standard Lua semantics)
// Note: This function returns a NSString* instead of const char* directly from Lua.
// This avoids the problem of the value being collected by Lua in your life-cycle, 
// since it copies it. Maybe for performance, I shouldn't worry about this since the usage
// tends to be short term. On the other hand, the main map uses NSString anyway.
//const char* LuaStructBridge_GetBridgeKeyNameFromMetatable(lua_State* lua_state, int obj_index)
NSString* LuaStructBridge_GetBridgeStructNameFromMetatable(lua_State* lua_state, int obj_index)
{
	// Since I don't have the metatable name, I can't use luaL_getmetatable.
	// So I am going more low-level and using lua_getmetable and then will
	// extract a string from the private field I created on creation which
	// contains the string keyname I seek.
	//	const char* key_name = NULL;
	NSString* key_name = nil;
	if(lua_getmetatable(lua_state, obj_index))  /* does userdata have a metatable? */
	{
		lua_getfield(lua_state, -1, LUASTRUCTBRIDGE_BRIDGESUPPORT_STRUCTNAME);
		if(lua_isstring(lua_state, -1))
		{
			// got the string
			//			key_name = lua_tostring(lua_state, -1);
			key_name = [NSString stringWithUTF8String:lua_tostring(lua_state, -1)];
		}
		lua_pop(lua_state, 2); // pop the string and the metatable
	}
	return key_name;
}

// Creates a new metatable and leaves on Lua stack.
// If metatable already exists, it returns 0 with metatable on the stack.
bool LuaStructBridge_GetOrCreateStructMetatable(lua_State* lua_state, NSString* key_name, NSString* struct_name)
{
	__strong const char* key_name_cstr = [key_name UTF8String];
	__strong const char* struct_name_cstr = [struct_name UTF8String];
	int ret_val;
	ret_val = luaL_newmetatable(lua_state, key_name_cstr);
	if(0 == ret_val)
	{
		// Means metatable with keyname already exists in registry.
		// Metatable is still on the top of the stack.
		return true;
	}
	// Because this is all dynamic at runtime, 
	// I will need access to the BridgeSupport metadata for the particular
	// struct in question so I can find elements, etc.
	// I've decided to hide the keyname in the metatable as a string
	// so we can look up the bridge support data when needed.
	lua_pushstring(lua_state, key_name_cstr);
	lua_setfield(lua_state, -2, LUASTRUCTBRIDGE_BRIDGESUPPORT_KEYNAME);
	
	// I also need the struct name because it may differ from the keyname
	lua_pushstring(lua_state, struct_name_cstr);
	lua_setfield(lua_state, -2, LUASTRUCTBRIDGE_BRIDGESUPPORT_STRUCTNAME);
	
	luaL_register(lua_state, NULL, LuaStructBridge_MethodsForStructMetatable);
	
	return false; // metatable is still on top of stack
}


bool LuaStructBridge_SetStructMetatableOnUserdata(lua_State* lua_state, int obj_index, NSString* key_name, NSString* struct_name)
{
	if(!lua_isuserdata(lua_state, obj_index))
	{
		//		luaL_error(lua_state, "SetMetatable must have a userdata as the parameter");
		return false;
	}
	LuaStructBridge_GetOrCreateStructMetatable(lua_state, key_name, struct_name); // metatable at top of stack
	
	if(obj_index > 0) // absolute position didn't change
	{
		lua_setmetatable(lua_state, obj_index); // applies metatable to userdata		
	}
	else // need to shift the index because we pushed the metatable on the stack
	{
		lua_setmetatable(lua_state, obj_index-1); // applies metatable to userdata		
	}

	return true;
}

