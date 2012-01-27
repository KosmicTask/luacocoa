//
//  ParseSupportCache.m
//  LuaCocoa
//
//  Created by Eric Wing on 2/22/11.
//  Copyright 2011 PlayControl Software, LLC. All rights reserved.
//

#import "ParseSupportCache.h"
#import "ParseSupport.h"
#import "ParseSupportStruct.h"
#import "ParseSupportFunction.h"
#import "ParseSupportMethod.h"

@implementation ParseSupportCache

static id s_cacheSingleton;

+ (id) sharedCache
{
//	static id s_cacheSingleton;
	@synchronized(self)
	{
		if(nil == s_cacheSingleton)
		{
			s_cacheSingleton = [[ParseSupportCache alloc] init];
		}
		return s_cacheSingleton;
	}
	return s_cacheSingleton;
}

+ (void) destroyCache
{
	@synchronized(self)
	{
		if(nil !=s_cacheSingleton)
		{
			[s_cacheSingleton release];
			s_cacheSingleton = nil;
		}
	}
}

- (id) init
{
	self = [super init];
	if(nil != self)
	{
		cacheOfStructKeyNames = [[NSMutableDictionary alloc] init];
		cacheOfFunctionNames = [[NSMutableDictionary alloc] init];
		cacheOfClassNamesToClassMethods = [[NSMutableDictionary alloc] init];
		cacheOfClassNamesToInstanceMethods = [[NSMutableDictionary alloc] init];
	}
	
	return self;
}

- (void)dealloc
{
	[cacheOfClassNamesToClassMethods release];
	[cacheOfClassNamesToInstanceMethods release];
	[cacheOfFunctionNames release];
	[cacheOfStructKeyNames release];

	[super dealloc];
}


- (void) insertParseSupport:(ParseSupportStruct*)parse_support structKeyName:(NSString*)struct_key_name
{
	[cacheOfStructKeyNames setObject:parse_support forKey:struct_key_name];
}

- (ParseSupportStruct*) parseSupportWithStructKeyName:(NSString*)struct_key_name
{
	return [cacheOfStructKeyNames objectForKey:struct_key_name];
}


- (void) insertParseSupport:(ParseSupportFunction*)parse_support functionName:(NSString*)function_name
{
	[cacheOfFunctionNames setObject:parse_support forKey:function_name];
}

- (ParseSupportFunction*) parseSupportWithFunctionName:(NSString*)function_name
{
	return [cacheOfFunctionNames objectForKey:function_name];
}


- (void) insertParseSupport:(ParseSupportMethod*)parse_support className:(NSString*)class_name methodName:(NSString*)method_name isClassMethod:(bool)is_class_method
{
	NSMutableDictionary* top_level_class_name_cache = nil;
	if(false == is_class_method)
	{
		top_level_class_name_cache = cacheOfClassNamesToInstanceMethods;
	}
	else
	{
		top_level_class_name_cache = cacheOfClassNamesToClassMethods;	
	}

	NSMutableDictionary* second_level_methods_cache = [top_level_class_name_cache objectForKey:class_name];
	// Make sure there is a dictionary for this second level
	if(nil == second_level_methods_cache)
	{
		second_level_methods_cache = [NSMutableDictionary dictionary];
		[top_level_class_name_cache setObject:second_level_methods_cache forKey:class_name];
	}

	// Now add the parse support object to the second level
	[second_level_methods_cache setObject:parse_support forKey:method_name];
}


- (ParseSupportMethod*) parseSupportWithClassName:(NSString*)class_name methodName:(NSString*)method_name isClassMethod:(bool)is_class_method
{
	NSMutableDictionary* top_level_class_name_cache = nil;
	if(false == is_class_method)
	{
		top_level_class_name_cache = cacheOfClassNamesToInstanceMethods;
	}
	else
	{
		top_level_class_name_cache = cacheOfClassNamesToClassMethods;	
	}
	NSMutableDictionary* second_level_methods_cache = [top_level_class_name_cache objectForKey:class_name];
	return [second_level_methods_cache objectForKey:method_name];
}


@end
