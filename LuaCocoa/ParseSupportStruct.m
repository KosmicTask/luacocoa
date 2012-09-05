//
//  ParseSupportStruct.m
//  LuaCocoa
//
//  Created by Eric Wing on 10/14/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "ParseSupportStruct.h"
#import "BridgeSupportController.h"
#import "NSStringHelperFunctions.h"
#import "StructSupport.h"

#import "ParseSupportCache.h"

/*
@interface ParseSupport ()

@property(copy, readwrite) NSString* keyName;
@property(retain, readwrite) NSXMLDocument* xmlDocument;
@property(retain, readwrite) NSXMLElement* rootElement;

@end
*/

@interface ParseSupportStruct ()

@property(retain, readwrite) NSString* structName;
@property(retain, readwrite) NSMutableArray* fieldNameArray;
@property(retain, readwrite) NSMutableArray* fieldElementArray;
- (void) parseAndFillData;

@end

@implementation ParseSupportStruct

@synthesize structName;
@synthesize fieldNameArray;
@synthesize fieldElementArray;
@synthesize sizeOfStruct;

+ (id) parseSupportStructFromKeyName:(NSString*)key_name
{
	ParseSupportCache* parse_support_cache = [ParseSupportCache sharedCache];
	ParseSupportStruct* check_cache = [parse_support_cache parseSupportWithStructKeyName:key_name];
	if(nil != check_cache)
	{
		return check_cache;
	}
	return [[[ParseSupportStruct alloc] initWithKeyName:key_name] autorelease];	
}

// TODO: Now that I have a new designated initializer, I can change this to not always check parse support 
// first since it will be redundant. However, I am unclear if I should skip adding to the cache too.
- (id) initWithKeyName:(NSString*)key_name
{
	ParseSupportCache* parse_support_cache = [ParseSupportCache sharedCache];
	ParseSupportStruct* check_cache = [parse_support_cache parseSupportWithStructKeyName:key_name];
	if(nil != check_cache)
	{
		// It appears self is valid even though I don't assign to it.
		// I need to release the memory created by the call to alloc since I am returning a different object.
		// Leaks will discover this leak if I don't.
		[self release];
		
		self = [check_cache retain];			
		return self;
	}
	
	self = [super initWithKeyName:key_name];
	if(nil != self)
	{
		structName = nil;
		fieldNameArray = [[NSMutableArray alloc] init];
		fieldElementArray = [[NSMutableArray alloc] init];
		[self parseAndFillData];
		
		[parse_support_cache insertParseSupport:self structKeyName:key_name];
	}
	return self;
}


- (void) copyPropertiesTo:(id)target_copy withZone:(NSZone*)the_zone
{
	ParseSupportStruct* new_copy = (ParseSupportStruct*)target_copy;

	[super copyPropertiesTo:target_copy withZone:the_zone];

	NSString* struct_name = [structName copyWithZone:the_zone];
	new_copy.structName = struct_name;
	[struct_name release];
	
	NSMutableArray* copy_field_name_array = [fieldNameArray copyWithZone:the_zone];
	new_copy.fieldNameArray = copy_field_name_array;
	[copy_field_name_array release];
	
	NSMutableArray* copy_field_element_array = [fieldElementArray copyWithZone:the_zone];
	new_copy.fieldElementArray = copy_field_element_array;
	[copy_field_element_array release];

}

- (void) mutableCopyPropertiesTo:(id)target_copy withZone:(NSZone*)the_zone
{
	ParseSupportStruct* new_copy = (ParseSupportStruct*)target_copy;

	[super mutableCopyPropertiesTo:target_copy withZone:the_zone];

	NSString* struct_name = [structName mutableCopyWithZone:the_zone];
	new_copy.structName = struct_name;
	[struct_name release];
	
	NSMutableArray* copy_field_name_array = [fieldNameArray mutableCopyWithZone:the_zone];
	new_copy.fieldNameArray = copy_field_name_array;
	[copy_field_name_array release];
	
	NSMutableArray* copy_field_element_array = [fieldElementArray mutableCopyWithZone:the_zone];
	new_copy.fieldElementArray = copy_field_element_array;
	[copy_field_element_array release];
}

- (id) copyWithZone:(NSZone*)the_zone
{
	ParseSupportStruct* new_copy = [[ParseSupportStruct allocWithZone:the_zone] init];
	[self copyPropertiesTo:new_copy withZone:the_zone];
	return new_copy;
}

- (id) mutableCopyWithZone:(NSZone*)the_zone
{
	ParseSupportStruct* new_copy = [[ParseSupportStruct allocWithZone:the_zone] init];
	[self mutableCopyPropertiesTo:new_copy withZone:the_zone];
	return new_copy;
}

- (void) dealloc
{
	[fieldElementArray release];
	[fieldNameArray release];
	[structName release];
	
	[super dealloc];
}

- (void) parseAndFillData
{
	
#if __LP64__	
	NSString* type_encoding_string = [[rootElement attributeForName:@"type64"] stringValue];
	if(nil == type_encoding_string)
	{
		type_encoding_string = [[rootElement attributeForName:@"type"] stringValue];				
	}
#else
	NSString* type_encoding_string = [[rootElement attributeForName:@"type"] stringValue];
#endif	
//NSLog(@"type_encoding_string: %@", type_encoding_string);
	// Sample strings:
	// {CGSize="width"d"height"d}
	// {CGRect="origin"{CGPoint="x"d"y"d}"size"{CGSize="width"d"height"d}}


	__strong const char* current_ptr = [type_encoding_string UTF8String];
	__strong const char* last_position_ptr = NULL;	
	
	// Skip first '{'
	current_ptr++;
	last_position_ptr = current_ptr;
	
	while('=' != *current_ptr)
	{
		current_ptr++;
	}

	// save struct name
	self.structName = [[[NSString alloc] initWithBytes:last_position_ptr length:current_ptr-last_position_ptr encoding:NSUTF8StringEncoding] autorelease];
	
	// skip the '='
	current_ptr++;
	last_position_ptr = current_ptr;


	int	opened_braces_count = 1;
	int closed_braces_count = 0;
	int nesting_level = 1;
	ParseSupportStructFieldElement* parse_support_struct_field_element = nil;
	
	while('\0' != *current_ptr)
	{
//		NSLog(@" (%@), isQuotedString=%d, delimited=%d stringValue=%@, idValue=%@", pk_token, pk_token.isQuotedString, pk_token.isDelimitedString, pk_token.stringValue, pk_token.value);
		
		// Quoted strings are a field element
		if('"' == *current_ptr)
		{
			current_ptr++;
			last_position_ptr = current_ptr;
			while('"' != *current_ptr)
			{
				current_ptr++;
			}
			
			// For simplicity, I am only saving the top-level field name values.
			// I will throw away the field names from nested structs.
			if(1 == nesting_level)
			{
				// save the field name in the fieldNameArray
				NSString* field_name = [[[NSString alloc] initWithBytes:last_position_ptr length:current_ptr-last_position_ptr encoding:NSUTF8StringEncoding] autorelease];
				[self.fieldNameArray addObject:field_name];
				
				// create a new field element object to go along with this field name
				parse_support_struct_field_element = [[[ParseSupportStructFieldElement alloc] init] autorelease];
				[self.fieldElementArray addObject:parse_support_struct_field_element];
			}
		}
		else if('{' == *current_ptr)
		{
			// The { indicates we have a nested struct
			opened_braces_count++;
			nesting_level++;
			// mark our element as a struct type
			parse_support_struct_field_element.compositeType = true;


			// assertion: nextToken is a struct name
			current_ptr++;
			last_position_ptr = current_ptr;
			while('=' != *current_ptr)
			{
				current_ptr++;
			}

			// I only care about accessing structs at the top-level so anything deeper, I throw away the name
			if(2 == nesting_level) // 2 (and not 1) because to find the name, we had to open a bracket
			{
				parse_support_struct_field_element.compositeName = [[[NSString alloc] initWithBytes:last_position_ptr length:current_ptr-last_position_ptr encoding:NSUTF8StringEncoding] autorelease];
			}

		}
		else if('}' == *current_ptr)
		{
			closed_braces_count++;
			nesting_level--;
		}
		// ruled out other cases...this must be an objc type encoding
		else
		{
			char objc_encoding_type = current_ptr[0];
			[parse_support_struct_field_element.objcEncodingTypeArray addObject:[NSNumber numberWithChar:objc_encoding_type]];
		}
		
		current_ptr++;
	}
	
	// Save size of struct for faster future access
	sizeOfStruct = [ParseSupport sizeOfStructureFromStructureName:structName];
}

// Walk the struct (ugh)
- (void*) pointerAtFieldIndex:(NSUInteger)field_index forStructPtr:(void*)struct_ptr
{
	void* struct_field_ptr = struct_ptr;
	for(NSUInteger i=0; i<field_index; i++)
	{
		ParseSupportStructFieldElement* current_field_element = [fieldElementArray objectAtIndex:i];
		for(NSNumber* current_objc_encoding in current_field_element.objcEncodingTypeArray)
		{
			struct_field_ptr = StructSupport_AlignPointer(struct_field_ptr, [current_objc_encoding charValue]);
			struct_field_ptr = StructSupport_AdvancePointer(struct_field_ptr, [current_objc_encoding charValue]);
		}
	}
	return struct_field_ptr;
}

+ (NSString*) keyNameFromStructName:(NSString*)struct_name
{
	NSString* name_of_return_struct_keyname = nil;
	if(![[BridgeSupportController sharedController] checkForKeyName:struct_name])
	{
		name_of_return_struct_keyname = NSStringHelperFunctions_StripLeadingUnderscores(struct_name);
		// Check one more time
		if(![[BridgeSupportController sharedController] checkForKeyName:name_of_return_struct_keyname])
		{
			// should I return nil or return the compositeName?
			return nil;
		}
		else
		{
			return name_of_return_struct_keyname;
		}
	}
	else
	{
		// found it, just reuse the compositeName
		return [[struct_name copy] autorelease];
	}
	return nil;
}

@end

/*
@interface ParseSupportStructFieldElement ()

@property(retain, readwrite) NSString* lookupName;


@end
*/

@implementation ParseSupportStructFieldElement

@synthesize compositeType;
@synthesize compositeName;

@synthesize objcEncodingTypeArray;

- (id) init
{
	self = [super init];
	if(nil != self)
	{
		compositeType = false;
		compositeName = nil;
		objcEncodingTypeArray = [[NSMutableArray alloc] init];
	}
	return self;
}


- (void) dealloc
{
	[compositeName release];
	[objcEncodingTypeArray release];
	
	[super dealloc];
}

// This annoying piece of code is to deal with the fact that BridgeSupport doesn't give me
// the keyName of structs when listed as a parameter, only the structName which may be different.
// e.g. keyName=NSRect, 64-bit structName=CGRect, 32-bit structName=_NSRect
// If the name doesn't exist as a BridgeSupport key, my last fallback is to try stripping
// the leading underscores to find the keyname.
- (NSString*) lookupName
{
	return [ParseSupportStruct keyNameFromStructName:compositeName];
}

@end