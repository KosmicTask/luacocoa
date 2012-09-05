//
//  ParseSupportMethod.m
//  LuaCocoa
//
//  Created by Eric Wing on 10/28/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "ParseSupportMethod.h"
#import "BridgeSupportController.h"
#import <objc/objc.h>
#import <objc/runtime.h>
#import "ObjectSupport.h"
#import "ParseSupportCache.h"


@interface ParseSupport ()
@property(copy, readwrite) NSString* keyName;
@property(retain, readwrite) NSXMLDocument* xmlDocument;
@property(retain, readwrite) NSXMLElement* rootElement;
//@property(copy, readwrite) NSString* itemType;

@end


@interface ParseSupportFunction ()
@property(retain, readwrite) NSMutableArray* argumentArray;
//@property(retain, readwrite) NSMutableArray* flattendArgumentRepresentationArray;

//@property(retain, readwrite) ParseSupportArgument* returnValue;
//@property(assign, readwrite, setter=setVariadic:, getter=isVariadic) bool isVariadic;
//@property(assign, readwrite) void* dlsymFunctionPointer;
- (void) handleSpecialEncodingTypes:(ParseSupportArgument*)parse_support_argument;
- (void) fillParseSupportArgument:(ParseSupportArgument*)parse_support_argument withChildNodeElement:(NSXMLElement*)child_node_element;

@end


@interface ParseSupportMethod ()
@property(copy, readwrite) NSString* className;

@end


@implementation ParseSupportMethod

#define PARSE_SUPPORT_MAX_OBJC_DESCRIPTION_LENGTH 128 // hope this is long enough. Only expect Structs and Pointers to be unpredictably long (e.g. longer than 1 character)

#ifdef DEBUG
	#define PARSE_SUPPORT_DO_PARANOID_ARGUMENT_CHECK 1
#endif
/*
@synthesize keyName;
@synthesize xmlDocument;
@synthesize rootElement;
@synthesize itemType;

@synthesize argumentArray;
//@synthesize flattendArgumentRepresentationArray;
@synthesize returnValue;
@synthesize isVariadic;
@synthesize dlsymFunctionPointer;
*/
@synthesize notFound;
@synthesize className;

- (void) handleSpecialEncodingTypes:(ParseSupportArgument*)parse_support_argument
{
	// 
	[super handleSpecialEncodingTypes:parse_support_argument];
}

/* Unlike the Function implemention, the Method needs to be a 2-pass/hybrid implementation.
 Information comes from both Obj-C runtime information and BridgeSupport.
 BridgeSupport may not exist or may only have partial information 
 (e.g. custom subclasses without BridgeSupport or full vs succinct) 
 so we don't want to complelete rely on it.
 But Obj-C runtime information may not be sufficient to accurately describe things (e.g. signed char means bool),
 so we want to use BridgeSupport if it exists.
 So the strategy is to run two passes. 
 First, grab the Obj-C runtime information and fill up the parse support as much as possible.
 Then go back and parse the BridgeSupport and supplement any information we have already created if needed.
*/

- (ParseSupportArgument*) fillParseSupportArgumentFromObjcEncodingType:(const char*)objc_encoding_type
{
	ParseSupportArgument* parse_support_argument = [[[ParseSupportArgument alloc] init] autorelease];
	
	parse_support_argument.objcEncodingType = [NSString stringWithUTF8String:objc_encoding_type];
	// currently super implementation
	[self handleSpecialEncodingTypes:parse_support_argument];
	return parse_support_argument;
}


// Lower level. NSProxy classes won't forward information which for our purposes doesn't work too well.
- (void) parseObjCRuntimeFromMethod:(Method)the_method
{
	unsigned int number_of_method_args = method_getNumberOfArguments(the_method);
	
	char current_objc_arg_description[PARSE_SUPPORT_MAX_OBJC_DESCRIPTION_LENGTH];
	// Note: Arguments 0 and 1 are expected to be self and _cmd which are an id '@' and a selector ':'
	for(unsigned int i=0; i<number_of_method_args; i++)
	{
		// could use method_copyArgumentType instead,
		// I don't need to worry about the max length, but will have
		// the memory overhead of malloc and free and must remember to call free.
		method_getArgumentType(the_method, i, current_objc_arg_description, PARSE_SUPPORT_MAX_OBJC_DESCRIPTION_LENGTH);
#if PARSE_SUPPORT_DO_PARANOID_ARGUMENT_CHECK
		{
			// There is a (rare) possibility that my string was not long enough to capture the entire argument list.
			// Turn on this check if you think this is happenning. 
			// Then either make the constant bigger or change the implemention.
			// Use either method_copyArgumentType and free or method_getTypeEncoding and parse.
			char* dynamic_arg_description = method_copyArgumentType(the_method, i);
			assert(!strcmp(current_objc_arg_description, dynamic_arg_description));
			free(dynamic_arg_description);
		}
#endif
		ParseSupportArgument* parse_support_argument = [self fillParseSupportArgumentFromObjcEncodingType:current_objc_arg_description];
		// add it to the array
		[argumentArray addObject:parse_support_argument];
//		NSLog(@"method_getArgumentType: %s", current_objc_arg_description);
	}
	method_getReturnType(the_method, current_objc_arg_description, PARSE_SUPPORT_MAX_OBJC_DESCRIPTION_LENGTH);
	
#if PARSE_SUPPORT_DO_PARANOID_ARGUMENT_CHECK
	{
		// There is a (rare) possibility that my string was not long enough to capture the entire argument list.
		// Turn on this check if you think this is happenning. 
		// Then either make the constant bigger or change the implemention.
		// Use either method_copyReturnType and free or method_getTypeEncoding and parse.
		char* dynamic_arg_description = method_copyReturnType(the_method);
		assert(!strcmp(current_objc_arg_description, dynamic_arg_description));
		free(dynamic_arg_description);
	}
#endif
	ParseSupportArgument* parse_support_argument = [self fillParseSupportArgumentFromObjcEncodingType:current_objc_arg_description];
	self.returnValue = parse_support_argument;
}

- (void) parseObjCRuntimeFromMethodSignature:(NSMethodSignature*)method_signature
{
	NSUInteger number_of_method_args = [method_signature numberOfArguments];
	
	
	// Note: Arguments 0 and 1 are expected to be self and _cmd which are an id '@' and a selector ':'
	for(NSUInteger i=0; i<number_of_method_args; i++)
	{
		ParseSupportArgument* parse_support_argument = [self fillParseSupportArgumentFromObjcEncodingType:[method_signature getArgumentTypeAtIndex:i]];
		// add it to the array
		[argumentArray addObject:parse_support_argument];
	}
	ParseSupportArgument* parse_support_argument = [self fillParseSupportArgumentFromObjcEncodingType:[method_signature methodReturnType]];
	self.returnValue = parse_support_argument;
}


- (void) parseObjCRuntime:(NSString *)class_name methodName:(NSString*)method_name isInstance:(bool)is_instance theReceiver:(id)the_receiver isClassMethod:(bool)is_class_method
{
	Class the_class = objc_getClass([class_name UTF8String]);
	SEL the_selector = sel_registerName([method_name UTF8String]);
	// TODO/FIXME: Support NSProxy (i.e. try not to use class_get*Method)
	if(ObjectSupport_IsSubclassOrProtocolOf(the_class, "NSObject"))
	{
		if(is_class_method)
		{
			Method the_method = class_getClassMethod(the_class, the_selector);
			if(NULL != the_method)
			{
				[self parseObjCRuntimeFromMethod:the_method];				
			}
			else
			{
				NSLog(@"Error: Couldn't get a Method in parseObjCRuntime:methodName:isInstance:theReceiver:");
			}
			
		}
		else
		{
			if(is_instance)
			{
				// use 
				// - (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector;
				NSMethodSignature* method_signature = [the_receiver methodSignatureForSelector:the_selector];
				[self parseObjCRuntimeFromMethodSignature:method_signature];
			}
			else
			{
				Method the_method = class_getInstanceMethod(the_receiver, the_selector);
				if(NULL != the_method)
				{
					[self parseObjCRuntimeFromMethod:the_method];				
				}
				else
				{
					NSLog(@"Error: Couldn't get a Method in parseObjCRuntime:methodName:isInstance:theReceiver:");
				}
			}
		}
	}
	else
	{
		// Fallback. This is some weird object.

		Method the_method;
		if(is_class_method)
		{
			 the_method = class_getClassMethod(the_class, the_selector);
		}
		else
		{
			the_method = class_getInstanceMethod(the_class, the_selector);
		}
		
		if(NULL != the_method)
		{
			[self parseObjCRuntimeFromMethod:the_method];				
		}
		else
		{
			NSLog(@"Error: Couldn't get a Method in parseObjCRuntime:methodName:isInstance:theReceiver:");
		}
	}

}

// don't call super. super's implementation is incompatible.
- (void) parseBridgeSupportMethod
{
	NSUInteger number_of_children = [rootElement childCount];
	
	for(NSUInteger i=0; i<number_of_children; i++)
	{
		NSXMLNode* child_node = [rootElement childAtIndex:i];
		if(NSXMLElementKind != [child_node kind])
		{
			continue;
		}
		NSXMLElement* child_node_element = (NSXMLElement*)child_node;
		
		if([[child_node_element name] isEqualToString:@"arg"])
		{
			NSString* argument_index_string = [[child_node_element attributeForName:@"index"] stringValue];
			if(nil == argument_index_string)
			{
				continue;
			}
			NSUInteger argument_index_number = (NSUInteger)[argument_index_string integerValue];
//			NSLog(@"argument_index_number: %d", argument_index_number);


			// update the existing parse support argument with the better BridgeSupport information
			// Note that BridgeSupport index ignores the object and selector so the index needs to be shifted by 2.
			// I include all the arguments in my array, so add 2 to the BridgeSupport index.
			ParseSupportArgument* current_argument = [argumentArray objectAtIndex:argument_index_number+2];
			[super fillParseSupportArgument:current_argument withChildNodeElement:child_node_element];
		
		}
		else if([[child_node_element name] isEqualToString:@"retval"])
		{
			[super fillParseSupportArgument:returnValue withChildNodeElement:child_node_element];
		}
	}
	
}

- (void) parseBridgeSupportClassWthReceiver:(id)the_receiver isInstance:(bool)is_instance methodName:(NSString*)method_name isClassMethod:(bool)is_class_method
{
	
	NSError* xml_error = nil;
	NSDictionary* xml_hash  = [[BridgeSupportController sharedController] masterXmlHash];
	//		NSString* dict_value = [xml_hash objectForKey:class_name];
	
	//		NSLog(@"dict_value=%@\n", dict_value);
	
	NSString* x_path = nil;
	Class current_class;
	
	if(is_class_method)
	{
		x_path = [NSString stringWithFormat:@"/class/method[@selector=\'%@\' and @class_method=\'true\']", method_name];
	}
	else
	{
		x_path = [NSString stringWithFormat:@"/class/method[@selector=\'%@\' and not(@class_method=\'true\')]", method_name];
	}

	if(is_instance)
	{
		current_class = ObjectSupport_GetClassFromObject(the_receiver);
	}
	else
	{
		current_class = ObjectSupport_GetClassFromClass(the_receiver);
	}
//	NSLog(@"x_path: %@", x_path);

	NSArray* child_nodes = nil;

	// Need to traverse superclasses until we get a hit
	while( (nil != current_class) && ((nil == child_nodes) || ([child_nodes count] < 1)) )
	{
		NSString* current_class_name = NSStringFromClass(current_class);
//		NSLog(@"current_class_name: %@", current_class_name);
#if 1
		NSString* dict_value = [xml_hash objectForKey:current_class_name];
#else
NSString* dict_value = 
@"<class name='NSObject'>\n" \
@"<method selector='URL:resourceDataDidBecomeAvailable:'>\n" \
@"<arg name='sender' declared_type='NSURL*' type='@' index='0'/>\n" \
@"<arg name='newBytes' declared_type='NSData*' type='@' index='1'/>\n" \
@"<retval declared_type='void' type='v'/>\n" \
@"</method>\n" \
@"<method selector='init'>\n" \
@"<retval declared_type='id' type='@'/>\n" \
@"</method>\n" \
@"<method selector='initWithCoder:'>\n" \
@"<arg name='aDecoder' declared_type='NSCoder*' type='@' index='0'/>\n" \
@"<retval declared_type='id' type='@'/>\n" \
@"</method>\n" \
@"<method selector='initialize' class_method='true'>\n" \
@"<retval declared_type='void' type='v'/>\n" \
@"</method>\n" \
@"</class>\n" \
@"<class name='NSObject'>\n" \
@"<method selector='instanceMethodForSelector:' class_method='true'>\n" \
@"<arg name='aSelector' declared_type='SEL' type=':' index='0'/>\n" \
@"<retval declared_type='IMP' type='^?'/>\n" \
@"</method>\n" \
@"</class>\n";
#endif
		if(nil == dict_value)
		{
			// I'm getting into trouble with alloc (before init) for NSString...getting NSPlaceholderString as class name which has no metadata
			current_class = [current_class superclass];
			continue;
		}
//		NSLog(@"dict_value:\n%@", dict_value);

		NSXMLDocument* xml_document = [[NSXMLDocument alloc] initWithXMLString:dict_value options:0 error:&xml_error];
		child_nodes = [[xml_document rootElement] nodesForXPath:x_path error:&xml_error];
		
//		NSLog(@"child_nodes: %@, xml_error=%@", child_nodes, xml_error);

		[xml_document release];
		// get super class for next loop
//		current_class = [current_class superclass];
		current_class = ObjectSupport_GetSuperClassFromClass(current_class);
	}
	
	if((nil == child_nodes) || ([child_nodes count] < 1))
	{
//		NSLog(@"Could not find XML data for %@:%@, falling back to Obj-C runtime info", NSStringFromClass(ObjectSupport_GetClassFromObject(the_receiver)), method_name);
		// rely completely on Obj-C runtime info
		return;
	}
	else
	{
//		NSLog(@"Found it: %@", [child_nodes objectAtIndex:0]);
//		NSLog(@"Found it: %@", [[child_nodes objectAtIndex:0] XMLString]);

	}
//	NSXMLElement* child_node_0 = [child_nodes objectAtIndex:0];
	xml_error = nil;
	xmlDocument = [[NSXMLDocument alloc] initWithXMLString:[[child_nodes objectAtIndex:0] XMLString] options:0 error:&xml_error];
	if(xml_error)
	{
		NSLog(@"xml_error: %@", [xml_error localizedDescription]);
	}
//	NSXMLDocument* new_doc = nil;
	// Weird. Under garbage collection, this triggers an exception on the data:
	// <method selector="init"><retval declared_type="id" type="@"></retval></method>
	// (from CALayer init):
	// *** Assertion failure in -[NSXMLDocument insertChild:atIndex:], /SourceCache/Foundation/Foundation-751/XML.subproj/XMLTypes.subproj/NSXMLDocument.m:737
	// Workaround: convert the node into a string and use initWithXMLString instead.
	
//	xmlDocument = [[NSXMLDocument alloc] initWithRootElement:child_node_0];
//	xmlDocument = [[NSXMLDocument alloc] initWithRootElement:child_node_0];
//new_doc = [[NSXMLDocument alloc] initWithRootElement:child_node_0];
	self.rootElement = [xmlDocument rootElement];
//	self.rootElement = [new_doc rootElement];
	[self parseBridgeSupportMethod];
}

// Need method and/or selector so I can use Obj-C introspection if BridgeSupport is missing
- (id) init
{
	self = [super init];
	if(nil != self)
	{
		notFound = true;
		argumentArray = [[NSMutableArray alloc] init];

		returnValue = [[ParseSupportArgument alloc] init];
//		returnValue.objcEncodingType = @"@";

//		[returnValue.flattenedObjcEncodingTypeArray addObject:@"@"]; 
		returnValue.objcEncodingType = @"v";
		[returnValue.flattenedObjcEncodingTypeArray addObject:@"v"];
		
		xmlDocument = nil;
		rootElement = nil;

	}
	return self;
}		

+ (id) parseSupportMethodFromClassName:(NSString *)class_name methodName:(NSString*)method_name isInstance:(bool)is_instance theReceiver:(id)the_receiver isClassMethod:(bool)is_class_method
{
	ParseSupportCache* parse_support_cache = [ParseSupportCache sharedCache];
	ParseSupportMethod* check_cache = [parse_support_cache parseSupportWithClassName:class_name methodName:method_name isClassMethod:is_class_method];
	if(nil != check_cache)
	{
		return check_cache;
	}
	return [[[ParseSupportMethod alloc] initWithClassName:class_name methodName:method_name isInstance:is_instance theReceiver:the_receiver isClassMethod:is_class_method] autorelease];
}

// Need method and/or selector so I can use Obj-C introspection if BridgeSupport is missing
- (id) initWithClassName:(NSString *)class_name methodName:(NSString*)method_name isInstance:(bool)is_instance theReceiver:(id)the_receiver isClassMethod:(bool)is_class_method
{
	ParseSupportCache* parse_support_cache = [ParseSupportCache sharedCache];
	ParseSupportMethod* check_cache = [parse_support_cache parseSupportWithClassName:class_name methodName:method_name isClassMethod:is_class_method];
	if(nil != check_cache)
	{
		// It appears self is valid even though I don't assign to it.
		// I need to release the memory created by the call to alloc since I am returning a different object.
		// Leaks will discover this leak if I don't.
		[self release];

		if(false == check_cache.isVariadic)
		{
			self = [check_cache retain];			
		}
		else
		{
			self = [check_cache mutableCopy];			
		}
		return self;
	}

	self = [super init];
	if(nil != self)
	{
		argumentArray = [[NSMutableArray alloc] init];
		returnValue = nil;

//		self.keyName = class_name;
		self.className = class_name;

//		NSLog(@"method_name=%@", method_name);

//		const char* objc_type_encoding = method_getTypeEncoding(the_method);
//		NSLog(@"objc_type_encoding=%s", objc_type_encoding);
//		NSLog(@"method_getReturnType: %s", current_objc_arg_description);

		// TODO: OPTIMIZATION: Check for XML data and skip the Obj-C runtime check if found.
		// But remember that the runtime must still must be parsed in some cases like variadic parameters.
		[self parseObjCRuntime:class_name methodName:method_name isInstance:is_instance theReceiver:the_receiver isClassMethod:is_class_method];

		[self parseBridgeSupportClassWthReceiver:the_receiver isInstance:is_instance methodName:method_name isClassMethod:is_class_method];

		
		/*

		self.rootElement = [xmlDocument rootElement];
		self.itemType = [[xmlDocument rootElement] name]; // looking for "method"
	
	
		argumentArray = [[NSMutableArray alloc] init];
		//		flattendArgumentRepresentationArray = [[NSMutableArray alloc] init];
		//		numberOfArguments = 0;
		//		numberOfFlattenedArguments = 0;
		
		returnValue = nil;
		dlsymFunctionPointer = NULL;
		
		
		isVariadic = ParseSupport_IsVariadic(rootElement);
		[self parseChildren];
		*/
		isVariadic = ParseSupport_IsVariadic(rootElement);
		
		if(false == isVariadic)
		{
			[parse_support_cache insertParseSupport:self className:class_name methodName:method_name isClassMethod:is_class_method];
		}
		else
		{
			id original_self = self;
			id new_self = nil;
			[parse_support_cache insertParseSupport:original_self className:class_name methodName:method_name isClassMethod:is_class_method];
//			[parse_support_cache insertParseSupport:[[self mutableCopy] autorelease] className:class_name methodName:method_name isClassMethod:is_class_method];
			new_self = [original_self mutableCopy];
			self = new_self;
			[original_self release];
		}


	}
	return self;
}

+ (id) parseSupportMethodFromClassName:(NSString *)class_name methodName:(NSString*)method_name isInstance:(bool)is_instance theReceiver:(id)the_receiver isClassMethod:(bool)is_class_method stringMethodSignature:(const char*)method_signature
{
	ParseSupportCache* parse_support_cache = [ParseSupportCache sharedCache];
	ParseSupportMethod* check_cache = [parse_support_cache parseSupportWithClassName:class_name methodName:method_name isClassMethod:is_class_method];
	if(nil != check_cache)
	{
		return check_cache;
	}
	return [[[ParseSupportMethod alloc] initWithClassName:class_name methodName:method_name isInstance:is_instance theReceiver:the_receiver isClassMethod:is_class_method stringMethodSignature:method_signature] autorelease];
}

- (id) initWithClassName:(NSString *)class_name methodName:(NSString*)method_name isInstance:(bool)is_instance theReceiver:(id)the_receiver isClassMethod:(bool)is_class_method stringMethodSignature:(const char*)method_signature
{
	ParseSupportCache* parse_support_cache = [ParseSupportCache sharedCache];
	ParseSupportMethod* check_cache = [parse_support_cache parseSupportWithClassName:class_name methodName:method_name isClassMethod:is_class_method];
	if(nil != check_cache)
	{
		// It appears self is valid even though I don't assign to it.
		// I need to release the memory created by the call to alloc since I am returning a different object.
		// Leaks will discover this leak if I don't.
		[self release];
	
		if(false == check_cache.isVariadic)
		{
			self = [check_cache retain];			
		}
		else
		{
			self = [check_cache mutableCopy];			
		}
		return self;
	}
	
	self = [super init];
	if(nil != self)
	{
		argumentArray = [[NSMutableArray alloc] init];
		returnValue = nil;
		
		//		self.keyName = class_name;
		self.className = class_name;
		
//		NSLog(@"method_name=%@", method_name);
		
		
		[self parseObjCRuntimeFromMethodSignature:[NSMethodSignature signatureWithObjCTypes:method_signature]];

				
		[self parseBridgeSupportClassWthReceiver:the_receiver isInstance:is_instance methodName:method_name isClassMethod:is_class_method];
		
		
		isVariadic = ParseSupport_IsVariadic(rootElement);
		
		if(false == isVariadic)
		{
			[parse_support_cache insertParseSupport:self className:class_name methodName:method_name isClassMethod:is_class_method];
		}
		else
		{
			id original_self = self;
			id new_self = nil;
			[parse_support_cache insertParseSupport:original_self className:class_name methodName:method_name isClassMethod:is_class_method];
			new_self = [original_self mutableCopy];
			self = new_self;
			[original_self release];
		}
	}
	return self;
}


- (void) copyPropertiesTo:(id)target_copy withZone:(NSZone*)the_zone
{
	ParseSupportMethod* new_copy = (ParseSupportMethod*)target_copy;
	
	[super copyPropertiesTo:target_copy withZone:the_zone];
	
	NSString* class_name = [className copyWithZone:the_zone];
	new_copy.className = class_name;
	[class_name release];
}

- (void) mutableCopyPropertiesTo:(id)target_copy withZone:(NSZone*)the_zone
{
	ParseSupportMethod* new_copy = (ParseSupportMethod*)target_copy;
	
	[super mutableCopyPropertiesTo:target_copy withZone:the_zone];
	
	NSString* class_name = [className mutableCopyWithZone:the_zone];
	new_copy.className = class_name;
	[class_name release];
}

- (id) copyWithZone:(NSZone*)the_zone
{
	ParseSupportMethod* new_copy = [[ParseSupportMethod allocWithZone:the_zone] init];
	[self copyPropertiesTo:new_copy withZone:the_zone];
	return new_copy;
}

- (id) mutableCopyWithZone:(NSZone*)the_zone
{
	ParseSupportMethod* new_copy = [[ParseSupportMethod allocWithZone:the_zone] init];
	[self mutableCopyPropertiesTo:new_copy withZone:the_zone];
	return new_copy;
}

- (void) dealloc
{
	[className release];
	[super dealloc];
}



#if 0
// This is parsed from method_getTypeEncoding
//
//	Later : Use method_copyArgumentType ?
+ (NSMutableArray*)parseObjCMethodEncoding:(const char*)typeEncoding
{
	id argumentEncodings = [NSMutableArray array];
	char* argsParser = (char*)typeEncoding;
	for(; *argsParser; argsParser++)
	{
		// Skip ObjC argument order
		if (*argsParser >= '0' && *argsParser <= '9')	continue;
		else
			// Skip ObjC 'const', 'oneway' markers
			if (*argsParser == 'r' || *argsParser == 'V')	continue;
			else
				if (*argsParser == '{')
				{
					// Parse structure encoding
					int count = 0;
					[ParseSupport typeEncodingsOfStructureFromFunctionTypeEncoding:[NSString stringWithUTF8String:argsParser] parsedCount:&count];
					
					id encoding = [[NSString alloc] initWithBytes:argsParser length:count encoding:NSUTF8StringEncoding];
					id argumentEncoding = [[JSCocoaFFIArgument alloc] init];
					// Set return value
					if ([argumentEncodings count] == 0)	[argumentEncoding setIsReturnValue:YES];
					[argumentEncoding setStructureTypeEncoding:encoding];
					[argumentEncodings addObject:argumentEncoding];
					[argumentEncoding release];
					
					[encoding release];
					argsParser += count-1;
				}
				else
				{
					// Custom handling for pointers as they're not one char long.
					//			char type = *argsParser;
					char* typeStart = argsParser;
					if (*argsParser == '^')
						while (*argsParser && !(*argsParser >= '0' && *argsParser <= '9'))	argsParser++;
					
					id argumentEncoding = [[JSCocoaFFIArgument alloc] init];
					// Set return value
					if ([argumentEncodings count] == 0)	[argumentEncoding setIsReturnValue:YES];
					
					// If pointer, copy pointer type (^i, ^{NSRect}) to the argumentEncoding
					if (*typeStart == '^')
					{
						id encoding = [[NSString alloc] initWithBytes:typeStart length:argsParser-typeStart encoding:NSUTF8StringEncoding];
						[argumentEncoding setPointerTypeEncoding:encoding];
						[encoding release];
					}
					else
					{
						BOOL didSet = [argumentEncoding setTypeEncoding:*typeStart];
						if (!didSet)
						{
							[argumentEncoding release];
							return	nil;
						}
					}
					
					[argumentEncodings addObject:argumentEncoding];
					[argumentEncoding release];
				}
		if (!*argsParser)	break;
	}
	return	argumentEncodings;
}
#endif


@end
