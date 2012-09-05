//
//  ParseSupportFunction.h
//  LuaCocoa
//
//  Created by Eric Wing on 10/24/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ParseSupport.h"
#import "ParseSupportArgument.h"

@interface ParseSupportFunction : ParseSupport
{
	NSMutableArray* argumentArray;
//	NSMutableArray* flattendArgumentRepresentationArray;
//	NSUInteger numberOfArguments;
//	NSUInteger numberOfFlattenedArguments;

	ParseSupportArgument* returnValue;


	bool isVariadic;
	void* dlsymFunctionPointer;


	bool internalError;
}


// Using retain instead of copy because of
// gotcha with properties and mutableCopy. 
// http://vgable.com/blog/2009/03/17/mutable-property-and-copy-gotcha/
@property(retain, readonly) NSMutableArray* argumentArray;
//@property(retain, readonly) NSMutableArray* flattendArgumentRepresentationArray;


// Note: These numberOf* properties have varying degrees of computation/processing under the hood.

// The number of arguments to a function.
@property(assign, readonly) NSUInteger numberOfRealArguments;
// Only counts flattened arguments with null terminator.
// Does not include real arguments in the count.
@property(assign, readonly) NSUInteger numberOfFlattenedArguments;
// Basically the number of structs in the list
@property(assign, readonly) NSUInteger numberOfRealArgumentsThatNeedToBeFlattened;

@property(assign, readonly) NSUInteger numberOfFlattenedReturnValues;


// Warning: setVariadic: and setReturnValue: were originally not designed to be available.
// This is because ParseSupport instances should be considered to be immutable and this assumption is used for caching.
// However, it because it was convenient to create ParseSupport instances dynamically for things like new method definitions
// (e.g. subclasses, categories), these methods got used.
// So try to make mutable copies when using these or make sure to never use these where they are being shared.
@property(retain, readwrite) ParseSupportArgument* returnValue;
@property(assign, readwrite, setter=setVariadic:, getter=isVariadic) bool isVariadic;
//@property(assign, readonly) void* dlsymFunctionPointer;
@property(assign, readwrite) void* dlsymFunctionPointer;


// Used by blocks implementation
- (id) initFunctionPointerWithXMLString:(NSString*)xml_string objcEncodingType:(NSString*)objc_encoding_type;

- (NSArray*) argumentObjcEncodingTypes;
- (NSString*) returnValueObjcEncodingType;

// Returns true if there is a printf format string in the argument list, false otherwise
// at_index is set to the array index (index starts counting at 0) of which argument it resides in.
// Passing in NULL allows you to ignore this value.
- (bool) retrievePrintfFormatIndex:(NSUInteger*)at_index;


// TODO:
- (size_t) appendVaradicArgumentsWithPrintfFormat:(const char*)format_string;
- (ParseSupportArgument*) appendVaradicArgumentWithObjcEncodingType:(char)objc_encoding_type;
- (ParseSupportArgument*) appendVaradicArgumentWithObjcEncodingTypeString:(NSString*)objc_encoding_type_string;

- (void) handleSpecialEncodingTypes:(ParseSupportArgument*)parse_support_argument;
- (void) fillParseSupportArgument:(ParseSupportArgument*)parse_support_argument withChildNodeElement:(NSXMLElement*)child_node_element;

// HACK: Need to remove
- (bool) internalError;

@end
