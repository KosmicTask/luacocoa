//
//  ParseSupportArgument.m
//  LuaCocoa
//
//  Created by Eric Wing on 10/24/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "ParseSupportArgument.h"
#import "ParseSupportFunction.h"

@implementation ParseSupportArgument

//@synthesize declaredType;
@synthesize objcEncodingType;
@synthesize inOutTypeModifier;
@synthesize nullAccepted;
@synthesize isStructType;
@synthesize sizeOfArgument;
@synthesize flattenedObjcEncodingTypeArray;
@synthesize isPrintfFormat;
@synthesize isVariadic;
@synthesize isConst;
@synthesize isAlreadyRetained;
@synthesize isFunctionPointer;
@synthesize functionPointerEncoding;

- (id) init
{
	self = [super init];
	if(nil != self)
	{
//		declaredType = nil;
		objcEncodingType = nil;
		inOutTypeModifier = nil;
		nullAccepted = false;
		isStructType = false;
		flattenedObjcEncodingTypeArray = [[NSMutableArray alloc] init];
		sizeOfArgument = 0;
		isPrintfFormat = false;
		isVariadic = false;
		isConst = false;
		isAlreadyRetained = false;
		isFunctionPointer = false;
		functionPointerEncoding = nil;
	}
	return self;
}

- (void) dealloc
{
	[functionPointerEncoding release];
	[flattenedObjcEncodingTypeArray release];
	[inOutTypeModifier release];
	[objcEncodingType release];
//	[declaredType release];
	[super dealloc];
}


- (void) copyPropertiesTo:(id)target_copy withZone:(NSZone*)the_zone
{
	ParseSupportArgument* new_copy = (ParseSupportArgument*)target_copy;
	
//	new_copy.declaredType = [self.declaredType copyWithZone:the_zone];
//	[new_copy.declaredType release];
	
	new_copy.objcEncodingType = [self.objcEncodingType copyWithZone:the_zone];
	[new_copy.objcEncodingType release];
	
	new_copy.inOutTypeModifier = [self.inOutTypeModifier copyWithZone:the_zone];
	[new_copy.inOutTypeModifier release];
	
	new_copy.flattenedObjcEncodingTypeArray = [self.flattenedObjcEncodingTypeArray copyWithZone:the_zone];
	[new_copy.flattenedObjcEncodingTypeArray release];
	
	
	new_copy.nullAccepted = self.nullAccepted;
	new_copy.isStructType = self.isStructType;
	
	new_copy.sizeOfArgument = self.sizeOfArgument;
	new_copy.isPrintfFormat = self.isPrintfFormat;
	new_copy.isVariadic = self.isVariadic;
	new_copy.isConst = self.isConst;
	new_copy.isAlreadyRetained = self.isAlreadyRetained;
	new_copy.isFunctionPointer = self.isFunctionPointer;
	new_copy.functionPointerEncoding = self.functionPointerEncoding;
}

- (void) mutableCopyPropertiesTo:(id)target_copy withZone:(NSZone*)the_zone
{
	ParseSupportArgument* new_copy = (ParseSupportArgument*)target_copy;
	
//	new_copy.declaredType = [self.declaredType mutableCopyWithZone:the_zone];
//	[new_copy.declaredType release];
	
	new_copy.objcEncodingType = [self.objcEncodingType mutableCopyWithZone:the_zone];
	[new_copy.objcEncodingType release];
	
	new_copy.inOutTypeModifier = [self.inOutTypeModifier mutableCopyWithZone:the_zone];
	[new_copy.inOutTypeModifier release];
	
	new_copy.flattenedObjcEncodingTypeArray = [self.flattenedObjcEncodingTypeArray mutableCopyWithZone:the_zone];
	[new_copy.flattenedObjcEncodingTypeArray release];
	
	new_copy.nullAccepted = self.nullAccepted;
	new_copy.isStructType = self.isStructType;
	
	new_copy.sizeOfArgument = self.sizeOfArgument;
	new_copy.isPrintfFormat = self.isPrintfFormat;
	new_copy.isVariadic = self.isVariadic;
	new_copy.isConst = self.isConst;
	new_copy.isAlreadyRetained = self.isAlreadyRetained;
	new_copy.isFunctionPointer = self.isFunctionPointer;
	new_copy.functionPointerEncoding = self.functionPointerEncoding;
}

- (id) copyWithZone:(NSZone*)the_zone
{
	ParseSupportArgument* new_copy = [[ParseSupportArgument allocWithZone:the_zone] init];
	[self copyPropertiesTo:new_copy withZone:the_zone];
	return new_copy;
}

- (id) mutableCopyWithZone:(NSZone*)the_zone
{
	ParseSupportArgument* new_copy = [[ParseSupportArgument allocWithZone:the_zone] init];
	[self mutableCopyPropertiesTo:new_copy withZone:the_zone];
	return new_copy;
}

- (bool) isBlock
{
	if(YES == [[self objcEncodingType] isEqualToString:@"@?"])
	{
		return true;
	}
	else
	{
		return false;
	}
}

@end
