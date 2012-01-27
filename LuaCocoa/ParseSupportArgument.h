//
//  ParseSupportArgument.h
//  LuaCocoa
//
//  Created by Eric Wing on 10/24/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface ParseSupportArgument : NSObject
{
//	NSString* argName;
//	NSString* declaredType;
	NSString* objcEncodingType; // the 'type' parameter
	NSString* inOutTypeModifier;
	bool nullAccepted;
	bool isStructType;
	NSMutableArray* flattenedObjcEncodingTypeArray;
	size_t sizeOfArgument; // total size of argument (i.e. adds up struct size if struct)
	bool isPrintfFormat;
	bool isVariadic;
	bool isConst;
	bool isAlreadyRetained;
}

//@property(retain) NSString* declaredType;
@property(retain) NSString* objcEncodingType;
@property(retain) NSString* inOutTypeModifier;
@property(assign) bool nullAccepted;
@property(assign, getter=isStructType, setter=setStructType:) bool isStructType;
@property(retain) NSMutableArray* flattenedObjcEncodingTypeArray;
@property(assign) size_t sizeOfArgument;
@property(assign, getter=isPrintfFormat, setter=setPrintfFormat:) bool isPrintfFormat;
@property(assign, getter=isVariadic, setter=setVariadic:) bool isVariadic;
@property(assign, getter=isConst, setter=setConst:) bool isConst;
@property(assign, getter=isAlreadyRetained, setter=setAlreadyRetained:) bool isAlreadyRetained;

- (id) copyWithZone:(NSZone*)the_zone;
- (id) mutableCopyWithZone:(NSZone*)the_zone;

// helpers for internal use by subclasses
- (void) copyPropertiesTo:(id)target_copy withZone:(NSZone*)the_zone;
- (void) mutableCopyPropertiesTo:(id)target_copy withZone:(NSZone*)the_zone;

@end
