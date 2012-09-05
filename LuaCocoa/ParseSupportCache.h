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

	NSMutableDictionary* cacheOfStructTypeEncodingsToStructNames; // struct_struct_name (_NSRect) intead of struct_key_name (NSRect)
	NSMutableDictionary* cacheOfStructNamesToStructTypeEncodings; // reverse mapping

	NSMutableDictionary* cacheOfStructKeyNamesToSizes;

	NSMutableDictionary* cacheOfStructTypeEncodingStringsToStructTypeEncodingArrays;
}

+ (id) sharedCache;
+ (void) destroyCache;

- (void) insertParseSupport:(ParseSupportStruct*)parse_support structKeyName:(NSString*)struct_key_name;
- (ParseSupportStruct*) parseSupportWithStructKeyName:(NSString*)struct_key_name;

- (void) insertParseSupport:(ParseSupportFunction*)parse_support functionName:(NSString*)function_name;
- (ParseSupportFunction*) parseSupportWithFunctionName:(NSString*)function_name;

- (void) insertParseSupport:(ParseSupportMethod*)parse_support className:(NSString*)class_name methodName:(NSString*)method_name isClassMethod:(bool)is_class_method;
- (ParseSupportMethod*) parseSupportWithClassName:(NSString*)class_name methodName:(NSString*)method_name isClassMethod:(bool)is_class_method;


// maps both ways
- (void) insertStructName:(NSString*)struct_name typeEncoding:(NSString*)type_encoding;
- (NSString*) structNameForTypeEncoding:(NSString*)type_encoding;
- (NSString*) typeEncodingForStructName:(NSString*)struct_name;



// Note: I have two caches for size. This one and the one in ParseSupportStruct. I should see about unifying.
// I am worried that this function may be called before a valid ParseSupportStruct is available though.
- (void) insertStructSize:(size_t)struct_size structKeyName:(NSString*)struct_key_name;
- (NSNumber*) structSizeForStructKeyName:(NSString*)struct_key_name;


- (void) insertStructTypeEncodingArray:(NSArray*)type_encoding_array structTypeEncodingString:(NSString*)type_encoding_string;
- (NSArray*) structTypeEncodingArrayForStructTypeEncodingString:(NSString*)struct_type_encoding;


@end
