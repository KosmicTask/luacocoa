//
//  BridgeSupportController.m
//  LuaCocoa
//
//  Created by Eric Wing on 10/20/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//
// Some parts taken from JSCocoa.

#import "BridgeSupportController.h"

#import <dlfcn.h>

// This is currently a brute force character level merge.
// It searches for newlines and records character indices.
// This will break if BridgeSupport doesn't consistently use newlines.
// Basically chops off the last line (e.g. </class>) from Node1,
// and chops off the first line (e.g. <class name='NSObject'> from Node 2
// and creates a new string that is the combination of the two.
/*
 
 <class name='NSObject'>
 <method selector='URL:resourceDataDidBecomeAvailable:'>
 <arg name='sender' declared_type='NSURL*' type='@' index='0'/>
 <arg name='newBytes' declared_type='NSData*' type='@' index='1'/>
 <retval declared_type='void' type='v'/>
 </method>
 <method selector='init'>
 <retval declared_type='id' type='@'/>
 </method>
 <method selector='initWithCoder:'>
 <arg name='aDecoder' declared_type='NSCoder*' type='@' index='0'/>
 <retval declared_type='id' type='@'/>
 </method>
 <method selector='initialize' class_method='true'>
 <retval declared_type='void' type='v'/>
 </method>
 </class>
 
 <class name='NSObject'>
 <method selector='instanceMethodForSelector:' class_method='true'>
 <arg name='aSelector' declared_type='SEL' type=':' index='0'/>
 <retval declared_type='IMP' type='^?'/>
 </method>
 </class>
 
*/ 
static NSString* BridgeSupportController_MergeNodes(NSString* xml_data1, NSString* xml_data2)
{
	__strong const char* xml_data1_c_str = [xml_data1 UTF8String];
	__strong const char* xml_data2_c_str = [xml_data2 UTF8String];

	// search for second to last newline to isolate last line in data
	size_t c_string_length = strlen(xml_data1_c_str);
	// start at the end of the string and work backwards. Skip the last newline.
	size_t newline_index_1 = 0;
	
	for(size_t i = c_string_length-1 ; i>0; i--)
	{
//		fprintf(stderr, "%c", xml_data1_c_str[i]);
		if('\n' == xml_data1_c_str[i])
		{
			newline_index_1 = i;
			break;
		}
	}
	
	// search for first newline to isolate first line in data
	c_string_length = strlen(xml_data2_c_str);
	// start at the end of the string and work backwards. Skip the last newline.
	size_t newline_index_2 = 0;
	for(size_t i = 0; i < c_string_length; i++)
	{
//		fprintf(stderr, "%c", xml_data2_c_str[i]);
		if('\n' == xml_data2_c_str[i])
		{
			newline_index_2 = i;
			break;
		}
	}

	NSString* return_string = [[xml_data1 substringToIndex:newline_index_1] 
		stringByAppendingString:[xml_data2 substringFromIndex:newline_index_2]];

/*
	NSLog(@"node1\n%@\n",xml_data1); 
	NSLog(@"node2\n%@\n",xml_data2); 
	NSLog(@"nodemerged\n%@\n",return_string); 
*/
	return return_string;
}

// In LuaCocoa 0.1, we were stuck using "Full" because of the way I did things.
// However, I think the changes I've made in 0.2 for lazy loading via metamethod/LuaCocoa.resolveName,
// may allow us to use the "non-full" or "regular" bridgesupport data.
// The non-full files are somewhat smaller and may possibly give slightly better performance 
// since there is less RAM in use and less data to parse.
// However, I have not yet tested this and I am still in dire need of a more robust unit test system.
// So for now, full bridge support is the default, but for the daring, I would like feedback on whether
// non-full works and if there are noticable performance benefits.
// Update: Lion is forcing my hand and ready or not, I must use non-full.
#define LUACOCOA_USE_FULL_BRIDGESUPPORT 0

#pragma mark BridgeSupportDataObject Start
@implementation BridgeSupportDataObject

@synthesize bridgeSupportLoaded;
@synthesize skipDLopen;
@synthesize frameworkBaseName;
@synthesize fullFilePathAndNameOfBridgeSupport;
@synthesize fullFilePathAndNameOfSupportDylib;
@synthesize fullFilePathAndNameOfFramework;
@synthesize listOfDependsOnFrameworkNames;
@synthesize xmlHashForFramework;
#if LUACOCOA_SAVE_RAW_XML_DATA
@synthesize rawBridgeSupportData;
#endif

- (id) init
{	
	self = [super init];
	if(nil != self)
	{
		listOfDependsOnFrameworkNames = [[NSMutableDictionary alloc] init];
		xmlHashForFramework = [[NSMutableDictionary alloc] init];		
	}
	return self;
}

- (void) dealloc
{
	[xmlHashForFramework release];
	[listOfDependsOnFrameworkNames release];
	[super dealloc];
}

@end

#pragma mark BridgeSupportDataObject End

@interface BridgeSupportController ()

- (bool) parseBridgeSupportDataForFrameworkBaseName:(NSString*)base_name atPath:(NSString*)full_file_path;
- (NSString*) fullPathForFrameworkBaseName:(NSString*)base_name hintPath:(NSString*)hint_path searchHintPathFirst:(bool)search_hint_path_first;


- (NSString*) loadBridgeSupportWithBaseName:(NSString*)base_name atPath:(NSString*)full_path;
- (NSString*) loadSupportDylibWithBaseName:(NSString*)base_name atPath:(NSString*)full_path;
- (NSString*) loadFrameworkDylibWithBaseName:(NSString*)base_name hintPath:(NSString*)hint_path searchHintPathFirst:(bool)search_hint_path_first;
- (NSString*) fullBridgeSupportDirectoryPathForRootPath:(NSString*)root_path baseName:(NSString*)base_name;
- (NSString*) fullFrameworkDirectoryPathForRootPath:(NSString*)root_path baseName:(NSString*)base_name;
- (bool) frameworkDylibExistsAtPath:(NSString*)full_path baseName:(NSString*)base_name;
- (bool) bridgeSupportDylibExistsAtPath:(NSString*)full_path baseName:(NSString*)base_name;
- (bool) bridgeSupportFileExistsAtPath:(NSString*)full_path baseName:(NSString*)base_name;
- (NSString*) fullPathForFrameworkBaseName:(NSString*)base_name hintPath:(NSString*)hint_path searchHintPathFirst:(bool)search_hint_path_first;


@end

#pragma mark BridgeSupportController Implementation

@implementation BridgeSupportController

@synthesize masterXmlHash;

#pragma mark Initialization

+ (id) sharedController
{
	static id singleton;
	@synchronized(self)
	{
		if (!singleton)
			singleton = [[BridgeSupportController alloc] init];
		return singleton;
	}
	return singleton;
}

- (id)init
{
	self = [super init];
	if(nil != self)
	{
		masterXmlHash = [[NSMutableDictionary alloc] init];
			
		bridgeSupportSearchPaths = [[NSArray alloc] initWithObjects:
			[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents/Frameworks"],
			[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents/BridgeSupport"],
			[@"~/Library/Frameworks" stringByExpandingTildeInPath],
			[@"~/Library/BridgeSupport" stringByExpandingTildeInPath],
			@"/Library/Frameworks",
			@"/Library/BridgeSupport",
			@"/Network/Library/Frameworks",
			@"/Network/Library/BridgeSupport",
			@"/System/Library/Frameworks",
			nil
		];
		
		frameworkSearchPaths = [[NSArray alloc] initWithObjects:
			[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents/Frameworks"],
			[@"~/Library/Frameworks" stringByExpandingTildeInPath],
			@"/Library/Frameworks",
			@"/Network/Library/Frameworks",
			@"/System/Library/Frameworks",
			nil
		];
		
		bridgeSupportMap = [[NSMutableDictionary alloc] init];
		failedFrameworkMap = [[NSMutableDictionary alloc] init];
	}
	
	return self;
}

- (void)dealloc
{
	[failedFrameworkMap release];
	[bridgeSupportMap release];
	[bridgeSupportSearchPaths release];
	[frameworkSearchPaths release];
	[masterXmlHash release];

	[super dealloc];
}

#pragma mark Internal Support Methods

// Parsing code taken from JSCocoa
// Load a bridgeSupport file into a hash as { name : xmlTagString } 
// Modified to keep additional information.
// Separate maps allow information to be looked up on a per-framework basis.
// DependsOn information is also tracked.
- (bool) parseBridgeSupportDataForFrameworkBaseName:(NSString*)base_name atPath:(NSString*)full_file_path
{
	NSError* the_error = nil;
//	NSLog(@"parseBridgeSupportDataForFrameworkBaseName: %@ %@", base_name, full_file_path);

	/*
		Adhoc parser
			NSXMLDocument is too slow
			loading xml document as string then querying on-demand is too slow
			can't get CFXMLParserRef to work
			don't wan't to delve into expat
			-> ad hoc : load file, build a hash of { name : xmlTagString }
	*/
	NSString* raw_xml_data = [NSString stringWithContentsOfFile:full_file_path encoding:NSUTF8StringEncoding error:&the_error];
	if(nil != the_error)
	{
		NSLog(@"parseBridgeSupportDataForFrameworkBaseName: %@", [the_error localizedDescription]);
		return false;
	}
	
	BridgeSupportDataObject* bridge_support_data_object = [[[BridgeSupportDataObject alloc] init] autorelease];
	bridge_support_data_object.bridgeSupportLoaded = true;
	bridge_support_data_object.frameworkBaseName = base_name;
	bridge_support_data_object.fullFilePathAndNameOfBridgeSupport = full_file_path;
#if LUACOCOA_SAVE_RAW_XML_DATA
	bridge_support_data_object.rawBridgeSupportData = raw_xml_data; // OPTIMIZATION: Might remove this to save memory.
#endif
	[bridgeSupportMap setObject:bridge_support_data_object forKey:base_name];
	

	__strong const char* c = [raw_xml_data UTF8String];
#ifdef __OBJC_GC__
	__strong const char* original_c = c;
	[[NSGarbageCollector defaultCollector] disableCollectorForPointer:(void*)original_c];
#endif


//	double t0 = CFAbsoluteTimeGetCurrent();
	// Start parsing
	for (; *c; c++)
	{
		if (*c == '<')
		{
			char startTagChar = c[1];
			if (startTagChar == 0)	return	NO;

			// 'co'	constant
			// 'cl'	class
			// 'e'	enum
			// 'fu'	function
			// 'st'	struct
			// 'cf'	cftype
			if ((c[1] == 'c' && (c[2] == 'o' || c[2] == 'l' || c[2] == 'f')) || c[1] == 'e' || (c[1] == 'f' && c[2] == 'u') || (c[1] == 's' && c[2] == 't'))
			{
				// FIXME: function_alias is screwing me up. I assume each key is unique, but in the
				// function_alias case, I can get duplicate keys from function and function_alias.
				// For now, throw away function_alias.
				bool is_function_alias = false;
//				if( c[1] == 'f' && c[2] == 'u' && c[3] == 'n' && c[4] == 'c'  && c[5] == 't'  && c[6] == 'i'  && c[7] == 'o' && c[8] == 'n' && c[9] == '_' && c[10] == 'a' )
				if( c[1] == 'f' && c[2] == 'u' && c[9] == '_' && c[10] == 'a' )
				{				
					is_function_alias = true;
				}
				// Extract name.
				// Oops. This is really bad. 10.8 shuffled the XML tag order around and this code was foolishly assuming the name='Foo' tag would come first which broke this code. This is even more reason to completely replace the XML parser hopefully so I can completely leverage it instead of doing my own performance optimization tricks.
				
				const char* tagStart = c;
				
				// Assuming I will find a name=' tag. Hopefully there won't be value strings with that substring. Yes, this sucks.
				const char* name_tag_start = strstr(tagStart, "name='");
				const char* c0 = NULL;
				id name = nil;
				
				if(NULL != name_tag_start)
				{
					c = name_tag_start;
					c += 6; // advance to the actual value for the name='value' key.
					c0 = c; // save the start position
					for (; *c && *c != '\''; c++); // advance to the end of the value (denoted by closing ')
					
					// save the name
					name = [[NSString alloc] initWithBytes:c0 length:c-c0 encoding:NSUTF8StringEncoding];
				}
				else
				{
					// not sure what to do in this case. Setting a pointer to no.
				}
				
				
				// Move to tag end
				BOOL foundEndTag = NO;
				BOOL foundOpenTag = NO;
				c++;
				for (; *c && !foundEndTag; c++)
				{
					if (*c == '<')					foundOpenTag = YES;
					else	
					if (*c == '/')
					{
						if (!foundOpenTag)
						{
							if(c[1] == '>')	foundEndTag = YES, c++;
						}
						else
						{
							if (startTagChar == c[1])	
							{
								foundEndTag = YES;
								// Skip to end of tag
								for (; *c && *c != '>'; c++);
							}
						}
					}
				}
				
				c0 = tagStart;
				NSString* value = [[NSString alloc] initWithBytes:c0 length:c-c0 encoding:NSUTF8StringEncoding];
				
				// workaround for function_alias
				if(false == is_function_alias)
				{
					// Ugh. It looks like categories will duplicate entries.
					// For example, CAAnimation adds a category on NSObject:
					// @interface NSObject (CAAnimationDelegate)
					// If I'm not careful, I will blow away the core NSObject XML data and replace it 
					// with just the category data. 
					// Instead, I need to merge the data.
					// If I append, then my sections may have multiple <class name='NSObject'>
					// tags. This might be okay, but it wasn't something I was thinking about originally.
					// I think the x_path stuff will still work correctly.
					NSString* existing_local_value = [bridge_support_data_object.xmlHashForFramework objectForKey:name];
					if(nil == existing_local_value)
					{
						[bridge_support_data_object.xmlHashForFramework setObject:value forKey:name];					
					}
					else
					{
						// Append
	//					NSString* merged_value = [existing_local_value stringByAppendingFormat:@"\n%@", value];
						NSString* merged_value = BridgeSupportController_MergeNodes(existing_local_value, value);
						[bridge_support_data_object.xmlHashForFramework setObject:merged_value forKey:name];
					}

					NSString* existing_value = [masterXmlHash objectForKey:name];
					if(nil == existing_value)
					{
						[masterXmlHash setObject:value forKey:name];
						[bridge_support_data_object.xmlHashForFramework setObject:value forKey:name];					
					}
					else
					{
						// Append
	//					NSString* merged_value = [existing_value stringByAppendingFormat:@"\n%@", value];
						NSString* merged_value = BridgeSupportController_MergeNodes(existing_value, value);
						[masterXmlHash setObject:merged_value forKey:name];
			//			NSLog(@"appending masterXmlHash: key:%@, value:%@", name, value);
	//			NSLog(@"appending masterXmlHash: key:%@, value:%@", name, merged_value);
						
					}
				}

				[value release];
				[name release];
			}
			// looking for depends_on
			else if((c[1] == 'd') && (c[2] == 'e'))
			{
				// Extract name
				for (; *c && *c != '\''; c++);
				c++;
				const char* c0 = c;
				for (; *c && *c != '\''; c++);
				
				// Name happens to be the framework name we want,
				// e.g. /System/Library/Frameworks/ApplicationServices.framework
				NSString* name = [[NSString alloc] initWithBytes:c0 length:c-c0 encoding:NSUTF8StringEncoding];
				
				// Do the rest to move the pointer to the end.
				// Move to tag end
				BOOL foundEndTag = NO;
				BOOL foundOpenTag = NO;
				c++;
				for (; *c && !foundEndTag; c++)
				{
					if (*c == '<')					foundOpenTag = YES;
					else	
						if (*c == '/')
						{
							if (!foundOpenTag)
							{
								if(c[1] == '>')	foundEndTag = YES, c++;
							}
							else
							{
								if (startTagChar == c[1])	
								{
									foundEndTag = YES;
									// Skip to end of tag
									for (; *c && *c != '>'; c++);
								}
							}
						}
				}
				
//				NSLog(@"depends_on key:%@, %@", [[name lastPathComponent] stringByDeletingPathExtension], name);
				// Add to list of dependsOn.
				[bridge_support_data_object.listOfDependsOnFrameworkNames setObject:[name stringByDeletingLastPathComponent] forKey:[[name lastPathComponent] stringByDeletingPathExtension]];

				[name release];
			}
		}
	}
//	double t1 = CFAbsoluteTimeGetCurrent();
//	NSLog(@"%f %@", t1-t0, [path lastPathComponent]);
#ifdef __OBJC_GC__
	[[NSGarbageCollector defaultCollector] enableCollectorForPointer:(void*)original_c];
#endif
	
	return	YES;
}


- (NSString*) loadBridgeSupportWithBaseName:(NSString*)base_name atPath:(NSString*)full_path
{
	if([self isBridgeSupportLoaded:base_name])
	{
		BridgeSupportDataObject* bridge_support_data_object = [bridgeSupportMap objectForKey:base_name];
		return bridge_support_data_object.fullFilePathAndNameOfBridgeSupport;
	}
	
	NSString* full_file_path_and_name;
	
#if LUACOCOA_USE_FULL_BRIDGESUPPORT
	full_file_path_and_name = [NSString stringWithFormat:@"%@/%@Full.bridgesupport", full_path, base_name];
#else // succinct
	full_file_path_and_name = [NSString stringWithFormat:@"%@/%@.bridgesupport", full_path, base_name];
#endif


	if(![self parseBridgeSupportDataForFrameworkBaseName:base_name atPath:full_file_path_and_name])
	{	
		NSLog(@"Failed to load %@", full_file_path_and_name);
		return nil;
	}
	return full_file_path_and_name;
}


// This is the extra dylib which contains extra symbols such as inline functions.
- (NSString*) loadSupportDylibWithBaseName:(NSString*)base_name atPath:(NSString*)full_path
{
	if([self isBridgeSupportLoaded:base_name])
	{
		BridgeSupportDataObject* bridge_support_data_object = [bridgeSupportMap objectForKey:base_name];
		return bridge_support_data_object.fullFilePathAndNameOfSupportDylib;
	}
	
	NSString* full_file_path_and_name;
	
	full_file_path_and_name = [NSString stringWithFormat:@"%@/%@.dylib", full_path, base_name];
	
	BOOL is_directory = NO;
	if([[NSFileManager defaultManager] fileExistsAtPath:full_file_path_and_name isDirectory:&is_directory])
	{
		if(YES == is_directory)
		{
			// we have a problem
			return nil;
		}
		else
		{
			// found it
			
			
			void* dl_address = dlopen([full_file_path_and_name UTF8String], RTLD_LAZY);
			if(!dl_address)
			{
				NSLog(@"Could not load support dylib %@", full_file_path_and_name);
				return nil;
			}
			else
			{
				return full_file_path_and_name;
			}
		}
	}
	return nil;
}

// Complication: The framework (with the dynamic library) may actually be in a different location than the BridgeSupport data.
// So we need to go hunting again.
- (NSString*) loadFrameworkDylibWithBaseName:(NSString*)base_name hintPath:(NSString*)hint_path searchHintPathFirst:(bool)search_hint_path_first
{
	if([self isBridgeSupportLoaded:base_name])
	{
		BridgeSupportDataObject* bridge_support_data_object = [bridgeSupportMap objectForKey:base_name];
		return bridge_support_data_object.fullFilePathAndNameOfFramework;
	}
	
	// Make a copy to modify 
	NSMutableArray* framework_search_paths;
	if(nil == hint_path)
	{ 
		// just creating an alias for easy use
		framework_search_paths = [[frameworkSearchPaths copy] autorelease];
	}
	else
	{
		// create a copy I can change that won't persist
		framework_search_paths = [[frameworkSearchPaths mutableCopy] autorelease];
		if(search_hint_path_first)
		{
			[framework_search_paths insertObject:hint_path atIndex:0];
		}
		else
		{
			[framework_search_paths addObject:hint_path];
		}
	}




	NSString* found_search_path = nil;
	for(NSString* current_search_path in framework_search_paths)
	{
		NSString* full_path = [self fullFrameworkDirectoryPathForRootPath:current_search_path  baseName:base_name];
		if([self frameworkDylibExistsAtPath:full_path baseName:base_name])
		{
			found_search_path = full_path;
			break;
		}
	}

	if(nil == found_search_path)
	{
		return nil;
	}

	NSString* path_to_dynamic_library_component_in_framework = [found_search_path stringByAppendingFormat:@"/Versions/Current/%@", base_name];
	void* dl_address = dlopen([path_to_dynamic_library_component_in_framework UTF8String], RTLD_LAZY);
	if(!dl_address)
	{
		// This will always happen with dynamically linked frameworks. Hope its not a problem.
//		NSLog(@"Could not load framework dylib %@", found_search_path);
		return found_search_path;
	}
	return found_search_path;
}

// Assumes root path is something like the strings in self.bridgeSupportSearchPaths
// Returns a full path like /System/Library/Frameworks/OpenGL.framework/Resources/BridgeSupport
- (NSString*) fullBridgeSupportDirectoryPathForRootPath:(NSString*)root_path baseName:(NSString*)base_name
{
	NSString* full_directory_path = nil;
	NSRange substring_range = [root_path rangeOfString:@"/Frameworks"];
	if(NSNotFound != substring_range.location)
	{
		// Is in a Frameworks directory which implies the data is inside an actual framework,
		// so we need to look in foo.framework/Resources/BridgeSupport
		full_directory_path = [NSString stringWithFormat:@"%@/%@.framework/Resources/BridgeSupport", root_path, base_name];
	}
	else
	{
		// Assuming the file is just sitting in the directory as foo.bridgesupport
		full_directory_path = [[root_path copy] autorelease];
	}
	return full_directory_path;
}


// Assumes root path is something like the strings in self.frameworkSearchPaths
// Returns a full path like /System/Library/Frameworks/OpenGL.framework
- (NSString*) fullFrameworkDirectoryPathForRootPath:(NSString*)root_path baseName:(NSString*)base_name
{
	return [NSString stringWithFormat:@"%@/%@.framework", root_path, base_name];
}

// Assumes a full path like /System/Library/Frameworks/OpenGL.framework
- (bool) frameworkDylibExistsAtPath:(NSString*)full_path baseName:(NSString*)base_name
{
	NSString* file_path;
	file_path = [NSString stringWithFormat:@"%@/%@", full_path, base_name];
	
	BOOL is_directory = NO;
	if([[NSFileManager defaultManager] fileExistsAtPath:file_path isDirectory:&is_directory])
	{
		if(YES == is_directory)
		{
			// we have a problem
			return false;
		}
		else
		{
			// found it
			return true;
		}
	}
	return false;
}

- (bool) bridgeSupportDylibExistsAtPath:(NSString*)full_path baseName:(NSString*)base_name
{
	NSString* file_path;
	file_path = [NSString stringWithFormat:@"%@/%@.dylib", full_path, base_name];

	
	BOOL is_directory = NO;
	if([[NSFileManager defaultManager] fileExistsAtPath:file_path isDirectory:&is_directory])
	{
		if(YES == is_directory)
		{
			// we have a problem
			return false;
		}
		else
		{
			// found it
			return true;
		}
	}
	return false;
}

- (bool) bridgeSupportFileExistsAtPath:(NSString*)full_path baseName:(NSString*)base_name
{
	NSString* file_path;
#if LUACOCOA_USE_FULL_BRIDGESUPPORT
	file_path = [NSString stringWithFormat:@"%@/%@Full.bridgesupport", full_path, base_name];
#else // succinct
	file_path = [NSString stringWithFormat:@"%@/%@.bridgesupport", full_path, base_name];
#endif
	
	
	BOOL is_directory = NO;
	if([[NSFileManager defaultManager] fileExistsAtPath:file_path isDirectory:&is_directory])
	{
		if(YES == is_directory)
		{
			// we have a problem
			return false;
		}
		else
		{
			// found it
			return true;
		}
	}
	return false;
}

/**
 * This will find the directory containing the .bridgesupport file for a framework with the given base_name (e.g. OpenGL).
 * Optionally, you may provide an additional search path (hint) and specify if you want it searched first or last.
 * If the .bridgesupport file is found, the path to the directory containing it will be returned, e.g.
 * /System/Library/Frameworks/OpenGL.framework/Resources/BridgeSupport
 * or /Library/BridgeSupport
 * If it is not found, nil is returned.
 */
- (NSString*) fullPathForFrameworkBaseName:(NSString*)base_name hintPath:(NSString*)hint_path searchHintPathFirst:(bool)search_hint_path_first
{
	// Make a copy to modify 
	NSMutableArray* bridge_support_search_paths;
	if(nil == hint_path)
	{ 
		// just creating an alias for easy use
		bridge_support_search_paths = [[bridgeSupportSearchPaths copy] autorelease];
	}
	else
	{
		// create a copy I can change that won't persist
		bridge_support_search_paths = [[bridgeSupportSearchPaths mutableCopy] autorelease];
		if(search_hint_path_first)
		{
			[bridge_support_search_paths insertObject:hint_path atIndex:0];
		}
		else
		{
			[bridge_support_search_paths addObject:hint_path];
		}
	}
	


	NSString* found_search_path = nil;
	for(NSString* current_search_path in bridge_support_search_paths)
	{
		NSString* full_path = [self fullBridgeSupportDirectoryPathForRootPath:current_search_path  baseName:base_name];
		if([self bridgeSupportFileExistsAtPath:full_path baseName:base_name])
		{
			found_search_path = full_path;
			break;
		}
	}

	return found_search_path;
}

#pragma mark Public API


- (bool) isBridgeSupportLoaded:(NSString*)base_name
{
	// Assumption: If the key is not in the map, then it doesn't exist.
	// I currently don't expect the case where the an object exists, but is not loaded.
	if(nil != [bridgeSupportMap objectForKey:base_name])
	{
		return true;
	}
	else
	{
		return false;
	}
}

- (bool) isBridgeSupportFailedToLoad:(NSString*)base_name
{
	// Assumption: If the key is not in the map, then it doesn't exist.
	// I currently don't expect the case where the an object exists, but is not loaded.
	if(nil != [failedFrameworkMap objectForKey:base_name])
	{
		return true;
	}
	else
	{
		return false;
	}
}


/* algorithm
 BridgeSupport: Load XML. Has bridge support already loaded the information?
 - You should provide a framework or dylib name (include suffix .framework/.dylib or not?)
 - You might provide an alternative (hint) path
 - BridgeSupport should automatically look for common places
 
 .framework/Resources/BridgeSupport/%@.bridgeSupport
 
 o   /Library/Frameworks/MyFramework/Resources/BridgeSupport
 
 o   /Library/BridgeSupport
 
 o   ~/Library/BridgeSupport
 
 - Remember to also register all dependencies
 
 BridgeSupport: dlopen if not already loaded AND user doesn't opt-out
 
 LuaState: register all things associated with this library.
 - Remember that the bridge support may have already been loaded from a different lua state so don't make assumptions based on its existance.
 - Remember to also register all dependencies
 - BridgeSupport should have a way to isolate information contained in a particular library
 */
- (BridgeSupportLoadState) loadFrameworkWithBaseName:(NSString*)base_name hintPath:(NSString*)hint_path searchHintPathFirst:(bool)search_hint_path_first skipDLopen:(bool)skip_dl_open
{
	// Check if we've already loaded this framework. Escape if we have.
	if([self isBridgeSupportLoaded:base_name])
	{
		return kBridgeSupportLoadAlreadyCached;
	}
	/* let the outside world decide if it wants to try to reload (maybe there is a new hint path?)
	// Already tried to load once and failed. Skip further attempts
	if([failedFrameworkMap objectForKey:base_name])
	{
		return kBridgeSupportLoadError;
	}
	*/
	
	// Unless exempted, we need to load the dynamic library
	// We are going to ignore loading errors in case the error is just a multiple load.
	NSString* full_path_to_framework = nil;
	if(!skip_dl_open)
	{
		full_path_to_framework = [self loadFrameworkDylibWithBaseName:base_name hintPath:hint_path searchHintPathFirst:search_hint_path_first];		
	}
	
	
	// NOTE: It is possible to have a framework without BridgeSupport information.
	// In this case, we may still want to load the framework because its symbols are being indirectly used
	// by something else that is directly used. So the full path check needs to happen after the
	// the dlopens.
	
	// Find if/where the bridge support data is for the given framework name
	NSString* found_full_path = [self fullPathForFrameworkBaseName:base_name hintPath:hint_path searchHintPathFirst:search_hint_path_first];
	if(nil == found_full_path)
	{
		[failedFrameworkMap setObject:[NSNumber numberWithBool:YES] forKey:base_name];
		return kBridgeSupportLoadNotAvailable;
	}
	
	NSString* full_path_to_support_dylib = nil;
	if(!skip_dl_open)
	{
		// We also need to load the support dynamic library which contains symbols for things like inline functions
		// This may not exist so we don't care about errors
		full_path_to_support_dylib = [self loadSupportDylibWithBaseName:base_name atPath:found_full_path];
	}
	

	// Next, we need the BridgeSupport controller to load in the xml data if it hasn't already.
	NSString* full_path_to_bridge_support = [self loadBridgeSupportWithBaseName:base_name atPath:found_full_path];
	if(nil == full_path_to_bridge_support)
	{
		[failedFrameworkMap setObject:[NSNumber numberWithBool:YES] forKey:base_name];
		return kBridgeSupportLoadError;
	}
	
	// Save these paths just in case we need them later
	BridgeSupportDataObject* current_object = [bridgeSupportMap objectForKey:base_name];
	current_object.skipDLopen = skip_dl_open;
	current_object.fullFilePathAndNameOfBridgeSupport = full_path_to_bridge_support;
	current_object.fullFilePathAndNameOfSupportDylib = full_path_to_support_dylib;
	current_object.fullFilePathAndNameOfFramework = full_path_to_framework;
	
	// remove a failed to load marker if it exists
	[failedFrameworkMap removeObjectForKey:base_name];
	
	// Finally, we need to register all the items associated with this library into our Lua state
	
	return kBridgeSupportLoadOkay;
	
	
}

- (BridgeSupportDataObject*) bridgeSupportDataObjectForFramework:(NSString*)base_name
{
	return [[[bridgeSupportMap objectForKey:base_name] retain] autorelease];
}

- (NSDictionary*) xmlHashForFramework:(NSString*)base_name
{
	BridgeSupportDataObject* bridge_support_data_object = [self bridgeSupportDataObjectForFramework:base_name];
	return [[bridge_support_data_object.xmlHashForFramework retain] autorelease];
}


- (NSDictionary*) listOfDependsOnNamesForFramework:(NSString*)base_name
{
	BridgeSupportDataObject* bridge_support_data_object = [self bridgeSupportDataObjectForFramework:base_name];
	return [[bridge_support_data_object.listOfDependsOnFrameworkNames retain] autorelease];
}

- (bool) checkForKeyName:(NSString*)key_name
{
	if([masterXmlHash objectForKey:key_name])
	{
		return true;
	}
	else
	{
		return false;
	}
}
@end







