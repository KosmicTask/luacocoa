//
//  ParseSupportFunction.m
//  LuaCocoa
//
//  Created by Eric Wing on 10/24/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "ParseSupportFunction.h"
#import "ObjCRuntimeSupport.h"
#import <objc/runtime.h>
#import "ParseSupportCache.h"

@interface ParseSupportFunction ()

@property(retain, readwrite) NSMutableArray* argumentArray;
//@property(copy, readwrite) NSMutableArray* argumentArray;
//@property(retain, readwrite) NSMutableArray* flattendArgumentRepresentationArray;

//@property(retain, readwrite) ParseSupportArgument* returnValue;
//@property(assign, readwrite, setter=setVariadic:, getter=isVariadic) bool isVariadic;
//@property(assign, readwrite) void* dlsymFunctionPointer;


- (ParseSupportArgument*) fillParseSupportArgument:(NSXMLElement*)child_node_element;

- (void) parseChildren;

@end

@implementation ParseSupportFunction

@synthesize argumentArray;
//@synthesize flattendArgumentRepresentationArray;
@synthesize returnValue;
@synthesize isVariadic;
@synthesize dlsymFunctionPointer;


// "<function name='NSSwapShort' inline='true'> <arg type='S'/> <retval type='S'/> </function>"
- (id) initWithXMLString:(NSString*)xml_string
{

	NSError* xml_error = nil;
	
	NSXMLDocument* xml_document = [[[NSXMLDocument alloc] initWithXMLString:xml_string options:0 error:&xml_error] autorelease];
	if(nil != xml_error)
	{
		NSLog(@"Unexpected error: ParseSupport initWithXMLString: failed in xmlDocument creation: %@", [xml_error localizedDescription]);
	}
	
	NSXMLElement* root_element = [xml_document rootElement];
	//		self.itemType = [[xmlDocument rootElement] name];
	NSString* key_name = [[root_element attributeForName:@"name"] stringValue];


	
	ParseSupportCache* parse_support_cache = [ParseSupportCache sharedCache];
	ParseSupportFunction* check_cache = [parse_support_cache parseSupportWithFunctionName:key_name];
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

	// I had to parse all the xml stuff to get the key name. 
	// As an optimization, I will bypass super initWithXMLString
//	self = [super initWithXMLString:xml_string];
	self = [super init];
	if(nil != self)
	{
		xmlDocument = [xml_document retain];
		rootElement = [root_element retain];
		keyName = [key_name copy];

	
		argumentArray = [[NSMutableArray alloc] init];
		returnValue = nil;
		dlsymFunctionPointer = NULL;
		
		isVariadic = ParseSupport_IsVariadic(rootElement);
		[self parseChildren];
		
		if(false == isVariadic)
		{
			[parse_support_cache insertParseSupport:self functionName:key_name];
		}
		else
		{
			id original_self = self;
			id new_self = nil;
			[parse_support_cache insertParseSupport:original_self functionName:key_name];
			new_self = [original_self mutableCopy];
			self = new_self;
			[original_self release];
		}
		
	}
	return self;
}

- (id) initWithKeyName:(NSString *)key_name
{
	ParseSupportCache* parse_support_cache = [ParseSupportCache sharedCache];
	ParseSupportFunction* check_cache = [parse_support_cache parseSupportWithFunctionName:key_name];
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
	
	self = [super initWithKeyName:key_name];
	if(nil != self)
	{
		argumentArray = [[NSMutableArray alloc] init];
		returnValue = nil;
		dlsymFunctionPointer = NULL;
		
		
		isVariadic = ParseSupport_IsVariadic(rootElement);
		[self parseChildren];
		
		if(false == isVariadic)
		{
			[parse_support_cache insertParseSupport:self functionName:key_name];
		}
		else
		{
			id original_self = self;
			id new_self = nil;
			[parse_support_cache insertParseSupport:original_self functionName:key_name];
			new_self = [original_self mutableCopy];
			self = new_self;
			[original_self release];
		}		
	}
	return self;
}


- (void) copyPropertiesTo:(id)target_copy withZone:(NSZone*)the_zone
{
	ParseSupportFunction* new_copy = (ParseSupportFunction*)target_copy;
	
	[super copyPropertiesTo:target_copy withZone:the_zone];
	
	NSMutableArray* copy_argument_array = [argumentArray copyWithZone:the_zone];
	new_copy.argumentArray = copy_argument_array;
	[copy_argument_array release];
	
	ParseSupportArgument* return_value = [returnValue copyWithZone:the_zone];
	new_copy.returnValue = return_value;
	[return_value release];
		
	new_copy.isVariadic = self.isVariadic;
	new_copy.dlsymFunctionPointer = self.dlsymFunctionPointer;
}

- (void) mutableCopyPropertiesTo:(id)target_copy withZone:(NSZone*)the_zone
{
	ParseSupportFunction* new_copy = (ParseSupportFunction*)target_copy;
	
	[super mutableCopyPropertiesTo:target_copy withZone:the_zone];
	
	NSMutableArray* copy_argument_array = [argumentArray mutableCopyWithZone:the_zone];
	new_copy.argumentArray = copy_argument_array;
	[copy_argument_array release];
		
	ParseSupportArgument* return_value = [returnValue mutableCopyWithZone:the_zone];
	new_copy.returnValue = return_value;
	[return_value release];
	
	new_copy.isVariadic = self.isVariadic;
	new_copy.dlsymFunctionPointer = self.dlsymFunctionPointer;
}

- (id) copyWithZone:(NSZone*)the_zone
{
	ParseSupportFunction* new_copy = [[ParseSupportFunction allocWithZone:the_zone] init];
	[self copyPropertiesTo:new_copy withZone:the_zone];
	return new_copy;
}

- (id) mutableCopyWithZone:(NSZone*)the_zone
{
	ParseSupportFunction* new_copy = [[ParseSupportFunction allocWithZone:the_zone] init];
	[self mutableCopyPropertiesTo:new_copy withZone:the_zone];
	return new_copy;
}

- (void) dealloc
{
	[returnValue release];
//	[flattendArgumentRepresentationArray release];
	[argumentArray release];
	
	[super dealloc];
}

- (NSUInteger) numberOfRealArguments
{
	return [argumentArray count];
}

// Only counts flattened arguments with null terminator.
// Does not include real arguments in the count.
- (NSUInteger) numberOfFlattenedArguments
{
	NSUInteger number_of_args = 0;
	for(ParseSupportArgument* an_argument in argumentArray)
	{
		if(an_argument.isStructType)
		{
			// Need to add 1 for a null character in the structure
			number_of_args += [an_argument.flattenedObjcEncodingTypeArray count] + 1;			
		}
	}
	return number_of_args;
}

// Basically the number of structs in the list
- (NSUInteger) numberOfRealArgumentsThatNeedToBeFlattened
{
	NSUInteger number_of_args = 0;
	for(ParseSupportArgument* an_argument in argumentArray)
	{
		if(an_argument.isStructType)
		{
			number_of_args++;
		}
	}
	return number_of_args;
}

- (NSUInteger) numberOfFlattenedReturnValues
{
	if(nil == returnValue)
	{
		return 0;
	}
	if(returnValue.isStructType)
	{
		return [returnValue.flattenedObjcEncodingTypeArray count] + 1;			
	}
	else
	{
		return 0;
	}
}

- (bool) retrievePrintfFormatIndex:(NSUInteger*)at_index
{
	if(NULL != at_index)
	{
		*at_index = 0;
	}
	for(ParseSupportArgument* an_argument in argumentArray)
	{
		if(an_argument.isPrintfFormat)
		{
			return true;
		}
		if(NULL != at_index)
		{
			*at_index++;
		}
	}
	return false;
}

// helper method for fillParseSupportArgument
- (void) handleSpecialEncodingTypes:(ParseSupportArgument*)parse_support_argument
{
	char type_encoding_char = 0;
	if(nil == parse_support_argument.objcEncodingType)
	{
		// Lion workaround: bridgesupport (non-full) may not allow us to fill the type encoding.
		// New assumption is that if this field is not defined, then we don't have any special cases we need to worry about and can return.
//		NSLog(@"Error: No type encoding found");
		return;
	}
	else
	{
		type_encoding_char = [parse_support_argument.objcEncodingType UTF8String][0];
	}
	
	while('r' == type_encoding_char
		  || 'n' == type_encoding_char
		  || 'N' == type_encoding_char
		  || 'o' == type_encoding_char
		  || 'O' == type_encoding_char
		  || 'R' == type_encoding_char
		  || 'V' == type_encoding_char
	)
	{
		// _C_CONST
		if('r' == type_encoding_char)
		{
			// lop off const part and continue downward
			parse_support_argument.isConst = true;
			type_encoding_char = [parse_support_argument.objcEncodingType UTF8String][1];
			parse_support_argument.objcEncodingType = [parse_support_argument.objcEncodingType substringFromIndex:1];
		}
		// FIXME: I assume that these are mutually exclusive, but I don't know for sure.
		// If not, this must be fixed not just here, but everywhere that uses this info.
		else if('n' == type_encoding_char
				|| 'N' == type_encoding_char
				|| 'o' == type_encoding_char
				|| 'O' == type_encoding_char
				|| 'R' == type_encoding_char
				|| 'V' == type_encoding_char
		)
		{
			// lop off const part and continue downward
			parse_support_argument.inOutTypeModifier = [NSString stringWithCharacters:(const unichar*)&type_encoding_char length:1];
			type_encoding_char = [parse_support_argument.objcEncodingType UTF8String][1];
			parse_support_argument.objcEncodingType = [parse_support_argument.objcEncodingType substringFromIndex:1];
		}
	}

	
	// Struct case (example function: CGColorSpaceCreateWithName)
	// _C_STRUCT_B
	if('{' == type_encoding_char)
	{
		parse_support_argument.isStructType = true;
		parse_support_argument.flattenedObjcEncodingTypeArray = [[[ParseSupport typeEncodingsOfStructureFromFunctionTypeEncoding:parse_support_argument.objcEncodingType] mutableCopy] autorelease];
		parse_support_argument.sizeOfArgument = [ParseSupport sizeOfStructureFromArrayOfPrimitiveObjcTypes:parse_support_argument.flattenedObjcEncodingTypeArray];
	}
	// _C_PTR
	else if('^' == type_encoding_char)
	{
		// not handled yet
//		NSLog(@"Type '^' not handled yet");
//		internalError = true;

		if([parse_support_argument.objcEncodingType hasPrefix:@"^{__CF"] && !ParseSupport_IsMagicCookie(rootElement))
		{
//			NSLog(@"May have found a CFType: %@", parse_support_argument.objcEncodingType);
			// FIXME: Should cross check with database to verify this is a cftype that can bridge to nsobject
			// Pretend that this is a _C_ID object type.
			parse_support_argument.objcEncodingType = @"@";
			parse_support_argument.sizeOfArgument = ObjCRuntimeSupport_SizeOfTypeEncoding(type_encoding_char);			
		}
		else
		{
			[parse_support_argument.flattenedObjcEncodingTypeArray addObject:parse_support_argument.objcEncodingType];
			parse_support_argument.sizeOfArgument = ObjCRuntimeSupport_SizeOfTypeEncoding(type_encoding_char);			
			
		}

		// special hack to enable out-argument type modifiers for id objects
		// don't change if it has already been set explicitly above or elsewhere 
		// (expected to be filled in fillParseSupportArgument before this method is called)
		if(nil == parse_support_argument.inOutTypeModifier)
		{
			char next_type_encoding_char = [parse_support_argument.objcEncodingType UTF8String][1];

			// Instead of just doing NSError**, I think it is reasonable to extend the out-modifier to all pointers to id's (^@)
			// The remaining question is if we want to automatically extend this any further to other types without requiring BridgeSupport
			if('@' == next_type_encoding_char)
			{
				parse_support_argument.inOutTypeModifier = @"o";
			}
		}

	}
	// _C_ARY_B
	else if('[' == type_encoding_char)
	{
		// not handled yet
		NSLog(@"Type '[' not handled yet");
		internalError = true;

		if([parse_support_argument.objcEncodingType isEqualToString:@"[1{?=II^v^v}]"])
		{
			NSLog(@"Think I found 64-bit va_list. Still don't know what to do.");
			// Pretend it's a _C_CHARPTR like 32-bit???
			
			[parse_support_argument.flattenedObjcEncodingTypeArray addObject:[NSString stringWithFormat:@"%c", _C_CHARPTR]];
			parse_support_argument.sizeOfArgument = sizeof(_C_UINT) * 2 + sizeof(_C_PTR) * 2;
		}
		else
		{
			[parse_support_argument.flattenedObjcEncodingTypeArray addObject:parse_support_argument.objcEncodingType];
			parse_support_argument.sizeOfArgument = ObjCRuntimeSupport_SizeOfTypeEncoding(type_encoding_char);		
		}
	}
	else if(0 == type_encoding_char)
	{
		// not handled yet
		NSLog(@"Type=%d unexpected", type_encoding_char);
		internalError = true;

	}
	else
	{
		// Only one primitive element. Add to the flattened array for convenience.
		[parse_support_argument.flattenedObjcEncodingTypeArray addObject:parse_support_argument.objcEncodingType];
		parse_support_argument.sizeOfArgument = ObjCRuntimeSupport_SizeOfTypeEncoding(type_encoding_char);
	}

	
}


- (void) fillParseSupportArgument:(ParseSupportArgument*)parse_support_argument withChildNodeElement:(NSXMLElement*)child_node_element
{
	parse_support_argument.objcEncodingType = ParseSupport_ObjcType(child_node_element);
//	parse_support_argument.declaredType = ParseSupport_DeclaredType(child_node_element);
	parse_support_argument.inOutTypeModifier = ParseSupport_InOutTypeModifer(child_node_element);
	parse_support_argument.nullAccepted = ParseSupport_NullAccepted(child_node_element);
	parse_support_argument.isPrintfFormat = ParseSupport_IsPrintfFormat(child_node_element);
	parse_support_argument.isAlreadyRetained = ParseSupport_IsAlreadyRetained(child_node_element);
	[self handleSpecialEncodingTypes:parse_support_argument];
	
}

// helper for parseChildren
// creates and returns an autoreleased ParseSupportArgument
- (ParseSupportArgument*) fillParseSupportArgument:(NSXMLElement*)child_node_element
{
	ParseSupportArgument* parse_support_argument = [[[ParseSupportArgument alloc] init] autorelease];
	[self fillParseSupportArgument:parse_support_argument withChildNodeElement:child_node_element];
	
	return parse_support_argument;
}

// helper for init
- (void) parseChildren
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
			ParseSupportArgument* parse_support_argument = [self fillParseSupportArgument:child_node_element];

			// add it to the array
			[argumentArray addObject:parse_support_argument];

		}
		else if([[child_node_element name] isEqualToString:@"retval"])
		{
			ParseSupportArgument* parse_support_argument = [self fillParseSupportArgument:child_node_element];
			self.returnValue = parse_support_argument;
		}
	}

}

- (ParseSupportArgument*) appendVaradicArgumentWithObjcEncodingType:(char)objc_encoding_type
{
	ParseSupportArgument* parse_support_argument = [[[ParseSupportArgument alloc] init] autorelease];
//	parse_support_argument.objcEncodingType = [NSString stringWithCharacters:(unichar*)&objc_encoding_type length:1];
	parse_support_argument.objcEncodingType = [NSString stringWithFormat:@"%c", objc_encoding_type];
//	parse_support_argument.declaredType = nil;
	parse_support_argument.inOutTypeModifier = nil;
	parse_support_argument.nullAccepted = false;
	parse_support_argument.isPrintfFormat = false;
	parse_support_argument.isVariadic = true;

	// I don't expect special encoding types to happen here, but call it anyway???
	[self handleSpecialEncodingTypes:parse_support_argument];

	[argumentArray addObject:parse_support_argument];

	return parse_support_argument;
}

- (ParseSupportArgument*) appendVaradicArgumentWithObjcEncodingTypeString:(NSString*)objc_encoding_type_string
{
	ParseSupportArgument* parse_support_argument = [[[ParseSupportArgument alloc] init] autorelease];
	//	parse_support_argument.objcEncodingType = [NSString stringWithCharacters:(unichar*)&objc_encoding_type length:1];
	parse_support_argument.objcEncodingType = objc_encoding_type_string;
	//	parse_support_argument.declaredType = nil;
	parse_support_argument.inOutTypeModifier = nil;
	parse_support_argument.nullAccepted = false;
	parse_support_argument.isPrintfFormat = false;
	parse_support_argument.isVariadic = true;
	
	// I don't expect special encoding types to happen here, but call it anyway???
	[self handleSpecialEncodingTypes:parse_support_argument];
	
	[argumentArray addObject:parse_support_argument];
	
	return parse_support_argument;
}


// Array of NSStrings holding the Obj-C encoding type strings (including structs)
// Not flattened
- (NSArray*) argumentObjcEncodingTypes
{
	NSMutableArray* array_of_encoding_types = [NSMutableArray arrayWithCapacity:[argumentArray count]];
	
	for(ParseSupportArgument* an_argument in argumentArray)
	{
		[array_of_encoding_types addObject:an_argument.objcEncodingType];
	}
	return array_of_encoding_types;
}

- (NSString*) returnValueObjcEncodingType
{
	if(nil == returnValue)
	{
		return nil;
	}
	return [[returnValue.objcEncodingType retain] autorelease];
}

- (bool) internalError
{
	return internalError;
}



/* Support for printf format strings */
// Taken/modified from PyObjC parse_printf_args
/*
static int
parse_printf_args(
				  PyObject* py_format,
				  PyObject* argtuple, Py_ssize_t argoffset,
				  void** byref, struct byref_attr* byref_attr,
				  ffi_type** arglist, void** values,
				  Py_ssize_t curarg)
				  */
- (size_t) appendVaradicArgumentsWithPrintfFormat:(const char*)format_string;
{
	// Do I want an argument that provides the number of lua arguments I think I have for validation?
	
	/* Walk the format string as a UTF-8 encoded ASCII value. This isn't
	 * perfect but keeps the code simple.
	 */
	
	size_t curarg = 0;
	ParseSupportArgument* current_parse_support_argument = nil;
//	__strong const char* format = [format_string UTF8String];
	const char* format = format_string;

	if (format == NULL)
	{
		return -1;
	}
	
	format = strchr(format, '%');
	while (format && *format != '\0') {
		char typecode;
		
		/* Skip '%' */
		format ++; 
		
		/* Check for '%%' escape */
		if (*format == '%') {
			format++;
			format = strchr(format, '%');
			continue;
		}
		
		/* Skip flags */
		while (1) {
			if (!*format)  break;
			if (
				(*format == '#')
				|| (*format == '0')
				|| (*format == '-')
				|| (*format == ' ')
				|| (*format == '+')
				|| (*format == '\'')) {
				
				format++;
			} else {
				break;
			}
		}
		
		/* Field width */
		if (*format == '*') {
//			if (argoffset >= maxarg) {
//				PyErr_Format(PyExc_ValueError, "Too few arguments for format string [cur:%"PY_FORMAT_SIZE_T"d/len:%"PY_FORMAT_SIZE_T"d]", argoffset, maxarg);
//				return -1;
//			}
			format++;
			
//			current_parse_support_argument = [[[ParseSupportArgument alloc] init] autorelease];
			current_parse_support_argument = [self appendVaradicArgumentWithObjcEncodingType:*@encode(int)];
//			current_parse_support_argument.isPrintfFormat = true;

/*			
			byref[curarg] = PyMem_Malloc(sizeof(int));
			if (byref[curarg] == NULL) {
				Py_DECREF(encoded);
				return -1;
			}
			
			if (depythonify_c_value(@encode(int), PyTuple_GET_ITEM(argtuple, argoffset), byref[curarg]) < 0) {
				Py_DECREF(encoded);
				return -1;
			}	
			values[curarg] = byref[curarg];
			arglist[curarg] = signature_to_ffi_type(@encode(int));
			
			argoffset++;
*/
			curarg++;

		} else {
			while (isdigit(*format)) format++;
		}
		
		/* Precision */
		if (*format == '.') {
			format++;
			if (*format == '*') {
				format++;
				current_parse_support_argument = [self appendVaradicArgumentWithObjcEncodingType:*@encode(int)];
/*
				if (argoffset >= maxarg) {
					PyErr_Format(PyExc_ValueError, "Too few arguments for format string [cur:%"PY_FORMAT_SIZE_T"d/len:%"PY_FORMAT_SIZE_T"d]", argoffset, maxarg);
					Py_DECREF(encoded);
					return -1;
				}
				byref[curarg] = PyMem_Malloc(sizeof(long long));
				if (byref[curarg] == NULL) {
					Py_DECREF(encoded);
					return -1;
				}
				
				
				if (depythonify_c_value(@encode(int), PyTuple_GET_ITEM(argtuple, argoffset), byref[curarg]) < 0) {
					Py_DECREF(encoded);
					return -1;
				}	
				values[curarg] = byref[curarg];
				arglist[curarg] = signature_to_ffi_type(@encode(int));
				argoffset++;
*/
				curarg++;

			} else {
				while (isdigit(*format)) format++;
			}
		}
		
		/* length modifier */
		typecode = 0;
		
		if (*format == 'h') {
			format++;
			
			if (*format == 'h') {
				format++;
			}
			
		} else if (*format == 'l') {
			format++;
			typecode = _C_LNG;
			if (*format == 'l') {
				typecode = _C_LNG_LNG;
				format++;
			}
			
		} else if (*format == 'q') {
			format++;
			typecode = _C_LNG_LNG;
			
		} else if (*format == 'j') {
			typecode = _C_LNG_LNG;
			format++;
			
		} else if (*format == 'z') {
			typecode = *@encode(size_t);
			format++;
			
		} else if (*format == 't') {
			typecode = *@encode(ptrdiff_t);
			format++;
			
		} else if (*format == 'L') {
			/* typecode = _C_LNGDBL, that's odd: no type encoding for long double! */
			format++;
			
		}
/*		
		if (argoffset >= maxarg) {
			PyErr_Format(PyExc_ValueError, "Too few arguments for format string [cur:%"PY_FORMAT_SIZE_T"d/len:%"PY_FORMAT_SIZE_T"d]", argoffset, maxarg);
			Py_DECREF(encoded);
			return -1;
		}
*/		
		/* And finally the info we're after: the actual format character */
		switch (*format) {
			case 'c': case 'C':
			/* I don't know what to do about this
#if SIZEOF_WCHAR_T != 4
#	error "Unexpected wchar_t size"
#endif
*/
				current_parse_support_argument = [self appendVaradicArgumentWithObjcEncodingType:*@encode(int)];
/*				
				byref[curarg] = PyMem_Malloc(sizeof(int));
				arglist[curarg] = signature_to_ffi_type(@encode(int));
				v = PyTuple_GET_ITEM(argtuple, argoffset);
				if (PyString_Check(v)) {
					if (PyString_Size(v) != 1) {
						PyErr_SetString(PyExc_ValueError, "Expecting string of length 1");
						Py_DECREF(encoded);
						return -1;
					}
					*(int*)byref[curarg] = (wchar_t)*PyString_AsString(v);
				} else if (PyUnicode_Check(v)) {
					
					if (PyUnicode_GetSize(v) != 1) {
						PyErr_SetString(PyExc_ValueError, "Expecting string of length 1");
						Py_DECREF(encoded);
						return -1;
					}
					*(int*)byref[curarg] = (wchar_t)*PyUnicode_AsUnicode(v);
				} else if (depythonify_c_value(@encode(int), v, byref[curarg]) < 0) {
					Py_DECREF(encoded);
					return -1;
				}
				
				values[curarg] = byref[curarg];
				
				argoffset++;
*/
				curarg++;

				break;
				
			case 'd': case 'i': case 'D':
				/* INT */
				if (*format == 'D') {
					typecode = _C_LNG;
				}
				else
				{
					typecode = _C_INT;
				}

/*				
				if (typecode == _C_LNG_LNG) {
					byref[curarg] = PyMem_Malloc(sizeof(long long));
					
				} else if (typecode == _C_LNG) {
					byref[curarg] = PyMem_Malloc(sizeof(long));
					
				} else {
					typecode = _C_INT;
					byref[curarg] = PyMem_Malloc(sizeof(int));
				}
				if (byref[curarg] == NULL) {
					PyErr_NoMemory();
					return -1;
				}
				if (depythonify_c_value(&typecode, PyTuple_GET_ITEM(argtuple, argoffset), byref[curarg]) < 0) {
					Py_DECREF(encoded);
					return -1;
				}	
				values[curarg] = byref[curarg];
				arglist[curarg] = signature_to_ffi_type(&typecode);
				
				argoffset++;
*/

				current_parse_support_argument = [self appendVaradicArgumentWithObjcEncodingType:typecode];
				curarg++;

				break;
				
			case 'o': case 'u': case 'x':
			case 'X': case 'U': case 'O':
				/* UNSIGNED */
				if (*format == 'U' || *format == 'X') {
					typecode = _C_LNG;
				}
/*				
				if (typecode == _C_LNG_LNG) {
					byref[curarg] = PyMem_Malloc(sizeof(long long));
					typecode = _C_ULNG_LNG;
					
				} else if (typecode == _C_LNG) {
					byref[curarg] = PyMem_Malloc(sizeof(long));
					typecode = _C_ULNG;
					
				} else {
					byref[curarg] = PyMem_Malloc(sizeof(int));
					typecode = _C_UINT;
				}
				if (byref[curarg] == NULL) {
					PyErr_NoMemory();
					Py_DECREF(encoded);
					return -1;
				}
				if (depythonify_c_value(&typecode, PyTuple_GET_ITEM(argtuple, argoffset), byref[curarg]) < 0) {
					Py_DECREF(encoded);
					return -1;
				}	
				values[curarg] = byref[curarg];
				arglist[curarg] = signature_to_ffi_type(&typecode);
				
				argoffset++;
*/
				curarg++;

				current_parse_support_argument = [self appendVaradicArgumentWithObjcEncodingType:typecode];

				break;
				
			case 'f': case 'F': case 'e': case 'E':
			case 'g': case 'G': case 'a': case 'A':
				/* double */
				typecode = _C_DBL;
/*				
				byref[curarg] = PyMem_Malloc(sizeof(double));
				if (byref[curarg] == NULL) {
					PyErr_NoMemory();
					Py_DECREF(encoded);
					return -1;
				}
				
				if (depythonify_c_value(&typecode, PyTuple_GET_ITEM(argtuple, argoffset), byref[curarg]) < 0) {
					Py_DECREF(encoded);
					return -1;
				}	
				values[curarg] = byref[curarg];
#if defined(__ppc__) 
*/
				/* Passing floats to variadic functions on darwin/ppc
				 * is slightly convoluted. Lying to libffi about the
				 * type of the argument seems to trick it into doing
				 * what the callee expects.
				 * XXX: need to test if this is still needed.
				 */
/*
				arglist[curarg] = &ffi_type_uint64;
#else
				arglist[curarg] = signature_to_ffi_type(&typecode);
#endif
				
				argoffset++;
*/
				curarg++;

				current_parse_support_argument = [self appendVaradicArgumentWithObjcEncodingType:typecode];

				break;
				
				
			case 's': case 'S':
				/* string */
				if (*format == 'S' || typecode == _C_LNG) {
					/* whar_t */
					current_parse_support_argument = [self appendVaradicArgumentWithObjcEncodingType:*@encode(wchar_t*)];
	/*
					v = byref_attr[curarg].buffer = PyUnicode_FromObject( PyTuple_GET_ITEM(argtuple, argoffset));
					if (byref_attr[curarg].buffer == NULL) {
						Py_DECREF(encoded);
						return -1;
					}
					
					Py_ssize_t sz = PyUnicode_GetSize(v);
					byref[curarg] = PyMem_Malloc(sizeof(wchar_t)*(sz+1));
					if (byref[curarg] == NULL) {
						Py_DECREF(encoded);
						return -1;
					}
					
					if (PyUnicode_AsWideChar((PyUnicodeObject*)v, (wchar_t*)byref[curarg], sz)<0) {
						Py_DECREF(encoded);
						return -1;
					}
					((wchar_t*)byref[curarg])[sz] = 0;
					arglist[curarg] = signature_to_ffi_type(@encode(wchar_t*));
					values[curarg] = byref + curarg;
*/
				} else {
					/* char */
					typecode = _C_CHARPTR;
/*					
					byref[curarg] = PyMem_Malloc(sizeof(char*));
					if (byref[curarg] == NULL) {
						PyErr_NoMemory();
						Py_DECREF(encoded);
						return -1;
					}
					if (depythonify_c_value(&typecode, PyTuple_GET_ITEM(argtuple, argoffset), byref[curarg]) < 0) {
						Py_DECREF(encoded);
						return -1;
					}	
					arglist[curarg] = signature_to_ffi_type(&typecode);
					values[curarg] = byref[curarg];
*/
					current_parse_support_argument = [self appendVaradicArgumentWithObjcEncodingType:typecode];
	
				}
				
//				argoffset++;
				curarg++;
				break;
				
			case '@': case 'K':
				/* object (%K is only used by NSPredicate */
				typecode = _C_ID;
				current_parse_support_argument = [self appendVaradicArgumentWithObjcEncodingType:typecode];

				/*
				byref[curarg] = PyMem_Malloc(sizeof(char*));
				if (byref[curarg] == NULL) {
					PyErr_NoMemory();
					Py_DECREF(encoded);
					return -1;
				}
				if (depythonify_c_value(&typecode, PyTuple_GET_ITEM(argtuple, argoffset), byref[curarg]) < 0) {
					Py_DECREF(encoded);
					return -1;
				}	
				values[curarg] = byref[curarg];
				arglist[curarg] = signature_to_ffi_type(&typecode);
				
				argoffset++;
				*/
				curarg++;

				break;
				
			case 'p':
				/* pointer */
				typecode = _C_PTR;
				current_parse_support_argument = [self appendVaradicArgumentWithObjcEncodingType:typecode];

				/*
				byref[curarg] = PyMem_Malloc(sizeof(char*));
				if (byref[curarg] == NULL) {
					PyErr_NoMemory();
					Py_DECREF(encoded);
					return -1;
				}
				*((char**)byref[curarg]) = (char*)PyTuple_GET_ITEM(argtuple, argoffset);
				values[curarg] = byref[curarg];
				arglist[curarg] = signature_to_ffi_type(@encode(void*));
				
				argoffset++;
				*/
				curarg++;

				break;
				
			case 'n':
				/* pointer-to-int */
				/*
				byref[curarg] = PyMem_Malloc(sizeof(long long));
				if (byref[curarg] == NULL) {
					PyErr_NoMemory();
					Py_DECREF(encoded);
					return -1;
				}
				values[curarg] = byref[curarg];
				arglist[curarg] = signature_to_ffi_type(&typecode);
				
				argoffset++;
				*/
				typecode = _C_PTR;
				current_parse_support_argument = [self appendVaradicArgumentWithObjcEncodingType:typecode];
				
				break;
				
			default:
//				PyErr_SetString(PyExc_ValueError, "Invalid format string");
//				Py_DECREF(encoded);
				return -1;
		}
		
		
		format = strchr(format+1, '%');
	}
	/*
	if (argoffset != maxarg) {
		PyErr_Format(PyExc_ValueError, "Too many values for format [%"PY_FORMAT_SIZE_T"d/%"PY_FORMAT_SIZE_T"d]", argoffset, maxarg);
		return -1;
	}
	*/
	return curarg;
}


@end
