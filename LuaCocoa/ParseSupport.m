//
//  ParseSupport.m
//  LuaCocoa
//
//  Created by Eric Wing on 10/14/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "ParseSupport.h"
#import "ParseSupportCache.h"
#import "BridgeSupportController.h"
#import "NSStringHelperFunctions.h"

#include "StructSupport.h"

#include <objc/runtime.h>

@interface ParseSupport ()

@property(copy, readwrite) NSString* keyName;
@property(retain, readwrite) NSXMLDocument* xmlDocument;
@property(retain, readwrite) NSXMLElement* rootElement;
//@property(copy, readwrite) NSString* itemType;



@end


@implementation ParseSupport

@synthesize keyName;
@synthesize xmlDocument;
@synthesize rootElement;
//@synthesize itemType;

- (id) initWithKeyName:(NSString*)key_name
{
	self = [super init];
	if(nil != self)
	{
		self.keyName = key_name;

		NSError* xml_error = nil;
		NSDictionary* xml_hash  = [[BridgeSupportController sharedController] masterXmlHash];
		NSString* dict_value = [xml_hash objectForKey:key_name];

		xmlDocument = [[NSXMLDocument alloc] initWithXMLString:dict_value options:0 error:&xml_error];
		if(nil != xml_error)
		{
			NSLog(@"Unexpected error: ParseSupport initWithKeyName: failed in xmlDocument creation: %@", [xml_error localizedDescription]);
		}
		
		self.rootElement = [xmlDocument rootElement];
//		self.itemType = [[xmlDocument rootElement] name];
				
	}
	return self;
}

// "<function name='NSSwapShort' inline='true'> <arg type='S'/> <retval type='S'/> </function>"
- (id) initWithXMLString:(NSString*)xml_string
{
	self = [super init];
	if(nil != self)
	{
		
		NSError* xml_error = nil;

		xmlDocument = [[NSXMLDocument alloc] initWithXMLString:xml_string options:0 error:&xml_error];
		if(nil != xml_error)
		{
			NSLog(@"Unexpected error: ParseSupport initWithXMLString: failed in xmlDocument creation: %@", [xml_error localizedDescription]);
		}
		
		self.rootElement = [xmlDocument rootElement];
//		self.itemType = [[xmlDocument rootElement] name];
		self.keyName = [[rootElement attributeForName:@"name"] stringValue];

	}
	return self;
}

- (void) copyPropertiesTo:(id)target_copy withZone:(NSZone*)the_zone
{
	ParseSupport* new_copy = (ParseSupport*)target_copy;
	
	NSString* key_name = [keyName copyWithZone:the_zone];
	new_copy.keyName = key_name;
	[key_name release];
	
	new_copy.xmlDocument = self.xmlDocument;
	new_copy.rootElement = self.rootElement;
}

- (void) mutableCopyPropertiesTo:(id)target_copy withZone:(NSZone*)the_zone
{
	ParseSupport* new_copy = (ParseSupport*)target_copy;
	
	NSString* key_name = [keyName mutableCopyWithZone:the_zone];
	new_copy.keyName = key_name;
	[key_name release];

	new_copy.xmlDocument = self.xmlDocument;
	new_copy.rootElement = self.rootElement;
}


- (id) copyWithZone:(NSZone*)the_zone
{
	ParseSupport* new_copy = [[ParseSupport allocWithZone:the_zone] init];
	[self copyPropertiesTo:new_copy withZone:the_zone];
	return new_copy;
}

- (id) mutableCopyWithZone:(NSZone*)the_zone
{
	ParseSupport* new_copy = [[ParseSupport allocWithZone:the_zone] init];
	[self mutableCopyPropertiesTo:new_copy withZone:the_zone];
	return new_copy;
}

- (void) dealloc
{
//	[itemType release];
	[rootElement release];
	[xmlDocument release];
	[keyName release];
	
	[super dealloc];
}


+ (NSArray*) typeEncodingsFromStructureName:(NSString*)structure_name
{
	ParseSupportCache* parse_support_cache = [ParseSupportCache sharedCache];
	NSString* type_encoding_string = [parse_support_cache typeEncodingForStructName:structure_name];
	if(nil == type_encoding_string)
	{
		NSError* xml_error = nil;
		NSDictionary* xml_hash  = [[BridgeSupportController sharedController] masterXmlHash];
		NSString* dict_value = [xml_hash objectForKey:structure_name];
		if(nil == dict_value)
		{
			// FIXME: Under 32-bit, I am bit by the leading underscore again (_NSPoint). Argh!
			dict_value = [xml_hash objectForKey:NSStringHelperFunctions_StripLeadingUnderscores(structure_name)];
			if(nil == dict_value)
			{
				NSLog(@"Unexpected error in typeEncodingsFromStructureName, can't get value for key=%@", structure_name);
				return nil;
			}
		}
		NSXMLDocument* xml_document = [[[NSXMLDocument alloc] initWithXMLString:dict_value options:0 error:&xml_error] autorelease];
		if(nil != xml_error)
		{
			NSLog(@"Unexpected error: ParseSupport initWithKeyName: failed in xmlDocument creation: %@", [xml_error localizedDescription]);
		}
		
		NSXMLElement* root_element = [xml_document rootElement];
		
		
		
	#if __LP64__	
		type_encoding_string = [[root_element attributeForName:@"type64"] stringValue];
		if(nil == type_encoding_string)
		{
			type_encoding_string = [[root_element attributeForName:@"type"] stringValue];				
		}
	#else
		type_encoding_string = [[root_element attributeForName:@"type"] stringValue];
	#endif
	//	NSLog(@"type_encoding_string=%@", type_encoding_string);
		// add to cache
		[parse_support_cache insertStructName:structure_name typeEncoding:type_encoding_string];
	}
	
	return [[self class] typeEncodingsOfStructureFromStructureTypeEncoding:type_encoding_string];
}


// Provide the "type" (or "type64") string, e.g.
// {CGRect=&quot;origin&quot;{CGPoint=&quot;x&quot;d&quot;y&quot;d}&quot;size&quot;{CGSize=&quot;width&quot;d&quot;height&quot;d}}
// And it will return an array of d,d,d,d
// Taken from JSCocoa
+ (NSArray*) typeEncodingsOfStructureFromFunctionTypeEncoding:(NSString*)structureTypeEncoding
{
	return [self typeEncodingsOfStructureFromFunctionTypeEncoding:structureTypeEncoding parsedCount:nil];
}


+ (NSArray*) typeEncodingsOfStructureFromFunctionTypeEncoding:(NSString*)structureTypeEncoding parsedCount:(int*)count
{
//	NSLog(@"structureTypeEncoding: %@", structureTypeEncoding);
	id types = [[[NSMutableArray alloc] init] autorelease];
	char* c = (char*)[structureTypeEncoding UTF8String];
	char* c0 = c;
	int	openedBracesCount = 0;
	int closedBracesCount = 0;
	for (;*c; c++)
	{
		if (*c == '{')
		{
			openedBracesCount++;
			while (*c && *c != '=') c++;
			if (!*c)	continue;
		}
		if (*c == '}')
		{
			closedBracesCount++;
			
			// If we parsed something (c>c0) and have an equal amount of opened and closed braces, we're done
			if (c0 != c && openedBracesCount == closedBracesCount)	
			{
				c++;
				break;
			}
			continue;
		}
		if (*c == '=')	continue;
		
		
		// Special case for pointers
		if (*c == '^')
		{
			char* c1 = c;

			// Skip pointers to pointers (^^^)
			while (*c && *c == '^')	c++;
			
			// Skip type, special case for structure
			if (*c == '{')
			{
				int	openedBracesCount2 = 1;
				int closedBracesCount2 = 0;
				c++;
				for (; *c && closedBracesCount2 != openedBracesCount2; c++)
				{
					if (*c == '{')	openedBracesCount2++;
					if (*c == '}')	closedBracesCount2++;
				}
				c--;
			}
			else
			{
				NSString* value = [[[NSString alloc] initWithBytes:c1 length:c-c1+1 encoding:NSUTF8StringEncoding] autorelease];
				[types addObject:value];

			}
		}
		else
		{
			[types addObject:[NSString stringWithFormat:@"%c", *c]];
		}



	}
	if (count) *count = c-c0;
	if (closedBracesCount != openedBracesCount)		return NSLog(@"typeEncodingsOfStructureFromFunctionTypeEncoding: Could not parse structure type encodings for %@", structureTypeEncoding), nil;

//	NSLog(@"types: %@", types);
	return	types;
}


// This version is not cached with ParseSupportCache. Use the version without parseCount:
+ (NSArray*) typeEncodingsOfStructureFromStructureTypeEncoding:(NSString*)structureTypeEncoding parsedCount:(int*)count
{
	id types = [[[NSMutableArray alloc] init] autorelease];
	char* c = (char*)[structureTypeEncoding UTF8String];
	char* c0 = c;
	int	openedBracesCount = 0;
	int closedBracesCount = 0;
	for (;*c; c++)
	{
		if (*c == '{')
		{
			openedBracesCount++;
			while (*c && *c != '=') c++;
			if (!*c)	continue;
		}
		if (*c == '}')
		{
			closedBracesCount++;
			
			// If we parsed something (c>c0) and have an equal amount of opened and closed braces, we're done
			if (c0 != c && openedBracesCount == closedBracesCount)	
			{
				c++;
				break;
			}
			continue;
		}
		if (*c == '=')	continue;
		
		if (*c == '"')
		{
			c++; // advance past current quote
			while (*c && *c != '"') c++; // skip past field name
			if (!*c)	continue;
			c++; // advance past current quote
			if (*c == '{')
			{
				// nested struct. Loop around for another pass.
				c--;
				continue;
			}
			else
			{
				[types addObject:[NSString stringWithFormat:@"%c", *c]];							
			}
		}
		
		
		// Special case for pointers
		if (*c == '^')
		{
			// Skip pointers to pointers (^^^)
			while (*c && *c == '^')	c++;
			
			// Skip type, special case for structure
			if (*c == '{')
			{
				int	openedBracesCount2 = 1;
				int closedBracesCount2 = 0;
				c++;
				for (; *c && closedBracesCount2 != openedBracesCount2; c++)
				{
					if (*c == '{')	openedBracesCount2++;
					if (*c == '}')	closedBracesCount2++;
				}
				c--;
			}
			else c++;
		}
	}
	if (count) *count = c-c0;
	if (closedBracesCount != openedBracesCount)		return NSLog(@"typeEncodingsOfStructureFromStructureTypeEncoding: Could not parse structure type encodings for %@", structureTypeEncoding), nil;
	
//	NSLog(@"types: %@", types);
	return	types;
}

+ (NSArray*) typeEncodingsOfStructureFromStructureTypeEncoding:(NSString*)structureTypeEncoding
{
	ParseSupportCache* parse_support_cache = [ParseSupportCache sharedCache];
	NSArray* type_encoding_array = [parse_support_cache structTypeEncodingArrayForStructTypeEncodingString:structureTypeEncoding];
	if(nil != type_encoding_array)
	{
		return type_encoding_array;
	}
	
	type_encoding_array = [self typeEncodingsOfStructureFromStructureTypeEncoding:structureTypeEncoding parsedCount:nil];
	[parse_support_cache insertStructTypeEncodingArray:type_encoding_array structTypeEncodingString:structureTypeEncoding];
	
	return type_encoding_array;
}

+ (size_t)sizeOfStructureFromStructureName:(NSString*)structure_name
{
	// Note: I have two caches for size. This one and the one in ParseSupportStruct. I should see about unifying.
	// I am worried that this function may be called before a valid ParseSupportStruct is available though.
	ParseSupportCache* parse_support_cache = [ParseSupportCache sharedCache];

	NSNumber* boxed_size = [parse_support_cache structSizeForStructKeyName:structure_name];
	if(nil != boxed_size)
	{
		return [boxed_size unsignedIntValue];
	}
	
	size_t return_size = [[self class] sizeOfStructureFromArrayOfPrimitiveObjcTypes:[[self class] typeEncodingsFromStructureName:structure_name]];
	[parse_support_cache insertStructSize:return_size structKeyName:structure_name];
	return return_size;
}


+ (size_t)sizeOfStructureFromArrayOfPrimitiveObjcTypes:(NSArray*)types
{
	size_t computedSize = 0;
	void* ptr = (void*)computedSize;
	for (id type in types)
	{
		char encoding = *(char*)[type UTF8String];
		// Align 
		ptr = StructSupport_AlignPointer(ptr, encoding);
		// Advance ptr
		ptr = StructSupport_AdvancePointer(ptr, encoding);
	}
//	NSLog(@"computedSizeOfStruct: %d", (size_t)ptr);
	return	(size_t)ptr;
}



+ (NSString*) descriptionStringFromStruct:(NSString*)structure_name structPtr:(void*)struct_ptr
{
	NSError* xml_error = nil;
	NSDictionary* xml_hash  = [[BridgeSupportController sharedController] masterXmlHash];
	NSString* dict_value = [xml_hash objectForKey:structure_name];
	
	// Lion: 32-bit leading underscore is tripping me up again.
/*
	if(nil == dict_value)
	{
		dict_value = [xml_hash objectForKey:NSStringHelperFunctions_StripLeadingUnderscores(structure_name)];
	}
*/	
	//	NSLog(@"key=%@, value=%@", structure_name, dict_value);
	NSXMLDocument* xml_document = [[[NSXMLDocument alloc] initWithXMLString:dict_value options:0 error:&xml_error] autorelease];
	if(nil != xml_error)
	{
		NSLog(@"Unexpected error: ParseSupport initWithKeyName: failed in xmlDocument creation: %@", [xml_error localizedDescription]);
	}
	
	NSXMLElement* root_element = [xml_document rootElement];
	
	
	
#if __LP64__	
	NSString* structure_type_encoding = [[root_element attributeForName:@"type64"] stringValue];
	if(nil == structure_type_encoding)
	{
		structure_type_encoding = [[root_element attributeForName:@"type"] stringValue];				
	}
#else
	NSString* structure_type_encoding = [[root_element attributeForName:@"type"] stringValue];
#endif
	

	
	// How large should the string be?
	NSMutableString* return_string = [NSMutableString stringWithCapacity:1024];
	
	// I really would prefer to abstract the parsing code, but this is so much easier.
	
	
	void* struct_field_ptr = struct_ptr;
	
	__strong const char* current_ptr = [structure_type_encoding UTF8String];
	__strong const char* last_position_ptr = NULL;	
	
	[return_string appendString:@"\n"];
	[return_string appendString:@"<"];
	[return_string appendString:structure_name];
	[return_string appendString:@" = "];
	[return_string appendFormat:@"0x%x", struct_ptr];
	[return_string appendString:@">\n"];
	
	// Skip first '{'
	current_ptr++;
	last_position_ptr = current_ptr;
	
	while('=' != *current_ptr)
	{
		current_ptr++;
	}
	
//	[return_string appendString:@"\n{"];
	[return_string appendString:@"{"];

	// save struct name
	[return_string appendString:@" <"];
	
	NSString* struct_name = [[[NSString alloc] initWithBytes:last_position_ptr length:current_ptr-last_position_ptr encoding:NSUTF8StringEncoding] autorelease];
	[return_string appendString:struct_name];
//	[return_string appendString:@" = "];
//	[return_string appendFormat:@"0x%x", struct_ptr];

	[return_string appendString:@">\n"];
	
	
	// skip the '='
	current_ptr++;
	last_position_ptr = current_ptr;
		
	int	opened_braces_count = 1;
	int closed_braces_count = 0;
	int nesting_level = 1;
	
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
			
			for(NSUInteger indent_level=0; indent_level<nesting_level; indent_level++)
			{
				[return_string appendString:@"    "];				
			}

			NSString* field_name = [[[NSString alloc] initWithBytes:last_position_ptr length:current_ptr-last_position_ptr encoding:NSUTF8StringEncoding] autorelease];
			[return_string appendString:field_name];

			[return_string appendString:@" = "];
		}
		else if('{' == *current_ptr)
		{
			// The { indicates we have a nested struct
			opened_braces_count++;
			nesting_level++;


			[return_string appendString:@"\n"];
			for(NSUInteger indent_level=0; indent_level<nesting_level; indent_level++)
			{
				[return_string appendString:@"    "];				
			}
			[return_string appendString:@"{"];


			// struct name
			current_ptr++;
			last_position_ptr = current_ptr;
			while('=' != *current_ptr)
			{
				current_ptr++;
			}
			
			NSString* struct_name = [[[NSString alloc] initWithBytes:last_position_ptr length:current_ptr-last_position_ptr encoding:NSUTF8StringEncoding] autorelease];

			[return_string appendString:@" <"];
			[return_string appendString:struct_name];
			[return_string appendString:@">\n"];


			nesting_level++;
			
		}
		else if('}' == *current_ptr)
		{
//			[return_string appendString:@"\n"];
			closed_braces_count++;
			nesting_level--;
			for(NSUInteger indent_level=0; indent_level<nesting_level; indent_level++)
			{
				[return_string appendString:@"    "];				
			}
			[return_string appendString:@"}\n"];
			nesting_level--;

		}
		else if('=' == *current_ptr)
		{
			[return_string appendString:@" = "];			
		}
		// ruled out other cases...this must be an objc type encoding
		else
		{
			char objc_encoding_type = current_ptr[0];

			/*
			for(NSUInteger indent_level=0; indent_level<nesting_level; indent_level++)
			{
				[return_string appendString:@"    "];				
			}
			*/
			
			switch(objc_encoding_type)
			{
				case _C_ID:
				{
					id value_ptr = (id)struct_field_ptr;
					[return_string appendFormat:@"%@\n", value_ptr];
					break;
				}
					
				case _C_CLASS:
				{
					Class value_ptr = (Class)struct_field_ptr;
					[return_string appendFormat:@"%s\n", class_getName(value_ptr)];
					break;
				}
				case _C_SEL:
				{
					SEL value_ptr = (SEL)struct_field_ptr;
					[return_string appendFormat:@"%@\n", NSStringFromSelector(value_ptr)];
					break;
				}
					
				case _C_CHR:
				{
					char* value_ptr = (char*)struct_field_ptr;
					[return_string appendFormat:@"%c\n", *value_ptr];
					break;
				}
				case _C_UCHR:
				{
					unsigned char* value_ptr = (unsigned char*)struct_field_ptr;
					[return_string appendFormat:@"%c\n", *value_ptr];
					break;
				}
				case _C_SHT:
				{
					short* value_ptr = (short*)struct_field_ptr;
					[return_string appendFormat:@"%d\n", *value_ptr];
					break;
				}
				case _C_USHT:
				{
					unsigned short* value_ptr = (unsigned short*)struct_field_ptr;
					[return_string appendFormat:@"%d\n", *value_ptr];
					break;
				}
				case _C_INT:
				{
					int* value_ptr = (int*)struct_field_ptr;
					[return_string appendFormat:@"%d\n", *value_ptr];
					break;
				}
				case _C_UINT:
				{
					unsigned int* value_ptr = (unsigned int*)struct_field_ptr;
					[return_string appendFormat:@"%d\n", *value_ptr];
					break;
				}
				case _C_LNG:
				{
					long* value_ptr = (long*)struct_field_ptr;
					[return_string appendFormat:@"%ld\n", *value_ptr];
					break;
				}
				case _C_ULNG:
				{
					unsigned long* value_ptr = (unsigned long*)struct_field_ptr;
					[return_string appendFormat:@"%ld\n", *value_ptr];
					break;
				}
				case _C_LNG_LNG:
				{
					long long* value_ptr = (long long*)struct_field_ptr;
					[return_string appendFormat:@"%lld\n", *value_ptr];
					break;
				}
				case _C_ULNG_LNG:
				{
					unsigned long long* value_ptr = (unsigned long long*)struct_field_ptr;
					[return_string appendFormat:@"%lld\n", *value_ptr];
					break;
				}
				case _C_FLT:
				{
					float* value_ptr = (float*)struct_field_ptr;
					[return_string appendFormat:@"%f\n", *value_ptr];
					break;
				}
				case _C_DBL:
				{
					double* value_ptr = (double*)struct_field_ptr;
					[return_string appendFormat:@"%lf\n", *value_ptr];
					break;
				}
					
				case _C_BOOL:
				{
					_Bool* value_ptr = (_Bool*)struct_field_ptr;
					[return_string appendFormat:@"%d\n", *value_ptr];
					break;
				}
					
				case _C_VOID:
				{
					// no return value (probably an error if I get here)
					break;
				}
					
				case _C_PTR:
				{
					void* value_ptr = (void*)struct_field_ptr;
					[return_string appendFormat:@"0x%x\n", value_ptr];
					break;
				}
					
				case _C_CHARPTR:
				{
					const char* value_ptr = (const char*)struct_field_ptr;
					[return_string appendFormat:@"%s\n", value_ptr];
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
//					luaL_error(lua_state, "Unexpected type %c for struct:%s __index", objc_type_encoding, [key_name UTF8String]);
					NSLog(@"return type not handled yet");

				}
					
			}
			
			// Increment pointer to next position (since we know the size of the current field element now)
			struct_field_ptr = StructSupport_AlignPointer(struct_field_ptr, objc_encoding_type);
			struct_field_ptr = StructSupport_AdvancePointer(struct_field_ptr, objc_encoding_type);
						
		}
		current_ptr++;
	}
//	[return_string appendString:@"}\n"];

	return return_string;
	
}

NSString* ParseSupport_StructureReturnNameFromReturnTypeEncoding(NSString* return_type_encoding)
{
	NSString* struct_name = nil;
	ParseSupportCache* parse_support_cache = [ParseSupportCache sharedCache];
	struct_name = [parse_support_cache structNameForTypeEncoding:return_type_encoding];
	if(nil != struct_name)
	{
		return struct_name;
	}
	
	// Could rewrite not use NSScanner, but did it to try to get familar with API
	NSCharacterSet* end_marker;
	NSScanner* the_scanner;
	
	NSString* opening_marker_to_skip = @"{";
	
	
	end_marker = [NSCharacterSet characterSetWithCharactersInString:@"="];
	the_scanner = [NSScanner scannerWithString:return_type_encoding];
	
	while ([the_scanner isAtEnd] == NO)
	{
		if ([the_scanner scanString:opening_marker_to_skip intoString:NULL] &&
			[the_scanner scanUpToCharactersFromSet:end_marker
									   intoString:&struct_name]
			)
		{
			
//			NSLog(@"Struct type is: %@", struct_name);
//			return struct_name;
			break;
		}
	}
	
	[parse_support_cache insertStructName:struct_name typeEncoding:return_type_encoding];	
	return struct_name;
}

bool ParseSupport_IsVariadic(NSXMLElement* root_element)
{
	bool is_variadic = false;
	NSError* xml_error = nil;
	NSString* variadic_xpath = @"//*[@variadic=\'true\']";
	NSArray* variadic_nodes = [root_element nodesForXPath:variadic_xpath error:&xml_error];
	if(nil != xml_error)
	{
		NSLog(@"variadic_xpath error: %@", xml_error);
	}
	// It's a variadic method if XPath returned one result
	if([variadic_nodes count] >= 1)
	{
		is_variadic = true;
		
	}	
	return is_variadic;
}

NSString* ParseSupport_ObjcType(NSXMLElement* root_element)
{
#if __LP64__	
	NSString* type_encoding_string = [[root_element attributeForName:@"type64"] stringValue];
	if(nil == type_encoding_string)
	{
		type_encoding_string = [[root_element attributeForName:@"type"] stringValue];				
	}
	// Lion: Non-full bridgesupport files don't list explicit types for selectors
	// Do additional checking for sel_of_type64 and sel_of_type
	/*
	 <method selector='performSelector:'>
	 <arg sel_of_type='@8@0:4' index='0' sel_of_type64='@16@0:8'/>
	 </method>
	 <method selector='performSelector:onThread:withObject:waitUntilDone:'>
	 <arg type='B' index='3'/>
	 </method>
	 */
	if(nil == type_encoding_string)
	{
		if( [root_element attributeForName:@"sel_of_type64"] || [root_element attributeForName:@"sel_of_type"] )
		{
			// We have a selector
			type_encoding_string = @":";
		}
	}
#else
	NSString* type_encoding_string = [[root_element attributeForName:@"type"] stringValue];
	// Lion: Non-full bridgesupport files don't list explicit types for selectors
	// Do additional checking for sel_of_type64 and sel_of_type
	/*
	 <method selector='performSelector:'>
	 <arg sel_of_type='@8@0:4' index='0' sel_of_type64='@16@0:8'/>
	 </method>
	 <method selector='performSelector:onThread:withObject:waitUntilDone:'>
	 <arg type='B' index='3'/>
	 </method>
	 */
	if(nil == type_encoding_string)
	{
		if( [root_element attributeForName:@"sel_of_type"] )
		{
			// We have a selector
			type_encoding_string = @":";
		}
	}

#endif
	return type_encoding_string;
}

/*
NSString* ParseSupport_DeclaredType(NSXMLElement* root_element)
{
	return [[root_element attributeForName:@"declared_type"] stringValue];
}
*/
NSString* ParseSupport_InOutTypeModifer(NSXMLElement* root_element)
{
	// BridgeSupport seems to be lacking and inconsistent on these.
	// Sometimes declared type has the "out " parameter
	// And NSError** seems to almost always omit the modifiers entirely even though it always seems to be out
	/* In NSNumberFormatter
	 <method selector='getObjectValue:forString:range:error:'>
	 <arg name='obj' declared_type='out id*' type='^@' index='0'/>
	 <arg name='string' declared_type='NSString*' type='@' index='1'/>
	 <arg name='rangep' declared_type='inout NSRange*' type64='^{_NSRange=QQ}' type='^{_NSRange=II}' index='2'/>
	 <arg name='error' declared_type='out NSError**' type='^@' index='3'/>
	 <retval declared_type='BOOL' type='B'/>
	 </method>
	 */
	NSString* type_modifer = [[root_element attributeForName:@"type_modifier"] stringValue];
	if(type_modifer != nil)
	{
		return type_modifer;		
	}

/*
	NSString* declared_type = [[root_element attributeForName:@"declared_type"] stringValue];
	if([declared_type hasPrefix:@"out "] || [declared_type isEqualToString:@"NSError**"])
	{
		return @"o";
	}
*/
	// Instead of just doing NSError**, I think it is reasonable to extend the out-modifier to all pointers to id's (^@)
	NSString* the_type = [[root_element attributeForName:@"type"] stringValue];
	if([the_type isEqualToString:@"^@"])
	{
		return @"o";
	}
	
	
	return nil;
}

bool ParseSupport_NullAccepted(NSXMLElement* root_element)
{
	NSString* null_accepted = [[root_element attributeForName:@"null_accepted"] stringValue];
	if(nil == null_accepted)
	{
		return true;
	}
	else
	{
		if([null_accepted isEqualToString:@"true"])
		{
			return true;
		}
		else
		{
			return false;
		}
	}
}

bool ParseSupport_IsPrintfFormat(NSXMLElement* root_element)
{
	NSString* printf_format = [[root_element attributeForName:@"printf_format"] stringValue];
	if(nil == printf_format)
	{
		return false;
	}
	else
	{
		if([printf_format isEqualToString:@"true"])
		{
			return true;
		}
		else
		{
			return false;
		}
	}
}

bool ParseSupport_IsAlreadyRetained(NSXMLElement* root_element)
{
	NSString* already_retained = [[root_element attributeForName:@"already_retained"] stringValue];
	if(nil == already_retained)
	{
		return false;
	}
	else
	{
		if([already_retained isEqualToString:@"true"])
		{
			return true;
		}
		else
		{
			return false;
		}
	}
}

bool ParseSupport_IsMagicCookie(NSXMLElement* root_element)
{
	bool is_magic_cookie = false;
	NSError* xml_error = nil;
	NSString* magic_cookie_xpath = @"//*[@magic_cookie=\'true\']";
	NSArray* magic_cookie_nodes = [root_element nodesForXPath:magic_cookie_xpath error:&xml_error];
	if(nil != xml_error)
	{
		NSLog(@"magic_cookie_xpath error: %@", xml_error);
	}
	// It's a variadic method if XPath returned one result
	if([magic_cookie_nodes count] >= 1)
	{
		is_magic_cookie = true;
		
	}	
	return is_magic_cookie;
}

NSString* ParseSupport_ObjcTypeFromKeyName(NSString* key_name)
{
	NSString* xml_string = [[[BridgeSupportController sharedController] masterXmlHash] objectForKey:key_name];
	NSError* xml_error = nil;
	NSXMLDocument* xml_document = [[[NSXMLDocument alloc] initWithXMLString:xml_string options:0 error:&xml_error] autorelease];
	if(nil != xml_error)
	{
		NSLog(@"Unexpected error: ParseSupport ParseSupport_ObjcTypeFromKeyName: failed in xmlDocument creation: %@", [xml_error localizedDescription]);
	}
	NSString* encoding_string = ParseSupport_ObjcType([xml_document rootElement]);
	return encoding_string;
}


bool ParseSupport_IsFunctionPointer(NSXMLElement* root_element)
{
	NSString* is_function_pointer = [[root_element attributeForName:@"function_pointer"] stringValue];
	if(nil == is_function_pointer)
	{
		return false;
	}
	else
	{
		if([is_function_pointer isEqualToString:@"true"])
		{
			return true;
		}
		else
		{
			return false;
		}
	}
}

@end
