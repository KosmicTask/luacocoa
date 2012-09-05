//
//  ParseSupport.h
//  LuaCocoa
//
//  Created by Eric Wing on 10/14/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface ParseSupport : NSObject
{
	NSString* keyName; // e.g. NSMakeRect
	NSXMLDocument* xmlDocument;
	NSXMLElement* rootElement;
//	NSString* itemType; // e.g. function
}

@property(copy, readonly) NSString* keyName;
@property(retain, readonly) NSXMLDocument* xmlDocument;
@property(retain, readonly) NSXMLElement* rootElement;
//@property(copy, readonly) NSString* itemType;

- (id) initWithKeyName:(NSString*)key_name;
- (id) initWithXMLString:(NSString*)xml_string;

- (id) copyWithZone:(NSZone*)the_zone;
- (id) mutableCopyWithZone:(NSZone*)the_zone;

// helpers for internal use by subclasses
- (void) copyPropertiesTo:(id)target_copy withZone:(NSZone*)the_zone;
- (void) mutableCopyPropertiesTo:(id)target_copy withZone:(NSZone*)the_zone;



+ (NSArray*) typeEncodingsFromStructureName:(NSString*)structure_name;


// Taken from JSCocoa
// Provide the "type" (or "type64") string, e.g.
// {CGRect={CGPoint=dd}{CGSize=dd}}
// And it will return an array of d,d,d,d
+ (NSArray*) typeEncodingsOfStructureFromFunctionTypeEncoding:(NSString*)structureTypeEncoding;
+ (NSArray*) typeEncodingsOfStructureFromFunctionTypeEncoding:(NSString*)structureTypeEncoding parsedCount:(int*)count;

// Provide the "type" (or "type64") string, e.g.
// {CGRect=&quot;origin&quot;{CGPoint=&quot;x&quot;d&quot;y&quot;d}&quot;size&quot;{CGSize=&quot;width&quot;d&quot;height&quot;d}}
// And it will return an array of d,d,d,d
// Note this is different than the function version which lacks quotes and the field name
// This version is cached. Call this one.
+ (NSArray*) typeEncodingsOfStructureFromStructureTypeEncoding:(NSString*)structureTypeEncoding;
// This one version with the count should not be called externally because it is not cached.
//+ (NSArray*) typeEncodingsOfStructureFromStructureTypeEncoding:(NSString*)structureTypeEncoding parsedCount:(int*)count;
+ (size_t)sizeOfStructureFromStructureName:(NSString*)structure_name;
+ (size_t)sizeOfStructureFromArrayOfPrimitiveObjcTypes:(NSArray*)types;

+ (NSString*) descriptionStringFromStruct:(NSString*)structure_name structPtr:(void*)struct_ptr;

NSString* ParseSupport_StructureReturnNameFromReturnTypeEncoding(NSString* return_type_encoding);

// Expected to be used on a function/method node
bool ParseSupport_IsVariadic(NSXMLElement* root_element);

// Gets the string from "type64" or "type" for the correct arch.
// Expected to be used on a function/method node
NSString* ParseSupport_ObjcType(NSXMLElement* root_element);

// Expected to be used on a function/method node
//NSString* ParseSupport_DeclaredType(NSXMLElement* root_element);

// Expected to be used on a function/method node
NSString* ParseSupport_InOutTypeModifer(NSXMLElement* root_element);

// Expected to be used on a function/method node
bool ParseSupport_NullAccepted(NSXMLElement* root_element);

// Expected to be used on a function/method node
bool ParseSupport_IsPrintfFormat(NSXMLElement* root_element);

// Expected to be used on a function/method node
bool ParseSupport_IsAlreadyRetained(NSXMLElement* root_element);

// Expected to be used on a function/method node
bool ParseSupport_IsMagicCookie(NSXMLElement* root_element);

NSString* ParseSupport_ObjcTypeFromKeyName(NSString* key_name);

bool ParseSupport_IsFunctionPointer(NSXMLElement* root_element);


@end

