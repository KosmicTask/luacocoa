//
//  ParseSupportCache.h
//  LuaCocoa
//
//  Created by Eric Wing on 2/22/11.
//  Copyright 2011 PlayControl Software, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
@class ParseSupport;
@class ParseSupportStruct;
@class ParseSupportFunction;
@class ParseSupportMethod;

@interface ParseSupportCache : NSObject
{
	NSMutableDictionary* cacheOfStructKeyNames;
	NSMutableDictionary* cacheOfFunctionNames;
	NSMutableDictionary* cacheOfClassNamesToClassMethods;
	NSMutableDictionary* cacheOfClassNamesToInstanceMethods;
}

+ (id) sharedCache;
+ (void) destroyCache;

- (void) insertParseSupport:(ParseSupportStruct*)parse_support structKeyName:(NSString*)struct_key_name;
- (ParseSupportStruct*) parseSupportWithStructKeyName:(NSString*)struct_key_name;

- (void) insertParseSupport:(ParseSupportFunction*)parse_support functionName:(NSString*)function_name;
- (ParseSupportFunction*) parseSupportWithFunctionName:(NSString*)function_name;

- (void) insertParseSupport:(ParseSupportMethod*)parse_support className:(NSString*)class_name methodName:(NSString*)method_name isClassMethod:(bool)is_class_method;
- (ParseSupportMethod*) parseSupportWithClassName:(NSString*)class_name methodName:(NSString*)method_name isClassMethod:(bool)is_class_method;


@end
