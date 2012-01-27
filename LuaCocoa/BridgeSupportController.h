//
//  BridgeSupportController.h
//  LuaCocoa
//
//  Created by Eric Wing on 10/20/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum _BridgeSupportLoadState
{
	kBridgeSupportLoadError = 0,
	kBridgeSupportLoadOkay = 1,
	kBridgeSupportLoadNotAvailable = 2,
	kBridgeSupportLoadAlreadyCached = 3,
} BridgeSupportLoadState;

// Optimization: I am not currently using the raw xml data after I load it.
// So I don't need to save it if I don't need it.
#define LUACOCOA_SAVE_RAW_XML_DATA 0


@class BridgeSupportDataObject;

@interface BridgeSupportController : NSObject
{
	NSMutableArray*			paths;
	NSMutableArray*			xmlDocuments;

	NSMutableDictionary* masterXmlHash;

	NSArray* bridgeSupportSearchPaths;
	NSArray* frameworkSearchPaths;
	
	// Need a dictionary that maps map[framework_name] = xmlHashForFramework;
	// Need a dictionary that maps map[framework_name] = @listOfDependsOnFrameworkNames
	// Need a dictionary that maps map[framework_name] = xmlDocuments
	// Will map framework base name to BridgeSupportDataObject
	NSMutableDictionary* bridgeSupportMap;

	// Optimization: Map to keep track of which frameworks we already tried to load but failed
	NSMutableDictionary* failedFrameworkMap;

}

@property(retain, readonly) NSDictionary* masterXmlHash;

+ (id) sharedController;

/**
 * Loads a framework, its BridgeSupport XML, and its support dylib.
 * @base_name The base name of the framework like "Cocoa" or "OpenGL".
 * @hint_path A string containing a path to where your bridge support metadata is located. Can be nil.
 * search_hint_path_first If true, your specified path will be searched before default paths, otherwise it is searched last.
 * @skip_dl_open If true, dlopen will not be called on the framework or support dylib. This is useful for cases where another language bridge may be in use and already loaded these libraries.
 * @return Returns kBridgeSupportLoadError if found and loaded, kBridgeSupportLoadNotAvailable if bridge support files are not available, otherwise returns kBridgeSupportLoadError.
 */
- (BridgeSupportLoadState) loadFrameworkWithBaseName:(NSString*)base_name hintPath:(NSString*)hint_path searchHintPathFirst:(bool)search_hint_path_first skipDLopen:(bool)skip_dl_open;
- (BridgeSupportDataObject*) bridgeSupportDataObjectForFramework:(NSString*)base_name;
- (NSDictionary*) xmlHashForFramework:(NSString*)base_name;
- (NSDictionary*) listOfDependsOnNamesForFramework:(NSString*)base_name;

/**
 * For a specific framework, has BridgeSupport been loaded?
 */
- (bool) isBridgeSupportLoaded:(NSString*)base_name;

/**
 * For a specific framework, has BridgeSupport failed to load before?
 */
- (bool) isBridgeSupportFailedToLoad:(NSString*)base_name;

/**
 * Returns true if the keyname is loaded in BridgeSupport.
 */
- (bool) checkForKeyName:(NSString*)key_name;

@end

// Support object for BridgeSupportController
@interface BridgeSupportDataObject : NSObject
{
	bool bridgeSupportLoaded; // might not need this
	bool skipDLopen; // might not need this
	NSString* frameworkBaseName; // might not need this
	NSString* fullFilePathAndNameOfBridgeSupport; // might not need this
	NSString* fullFilePathAndNameOfSupportDylib; // might not need this
	NSString* fullFilePathAndNameOfFramework; // might not need this
	NSMutableDictionary* listOfDependsOnFrameworkNames; // key=base_name, value=(hint)path to framework or NSNull
	NSMutableDictionary* xmlHashForFramework;

#if LUACOCOA_SAVE_RAW_XML_DATA
	NSString* rawBridgeSupportData; // might not need this...save a bunch of memory
#endif
}

@property(assign) bool bridgeSupportLoaded;
@property(assign) bool skipDLopen;
@property(retain) NSString* frameworkBaseName;
@property(retain) NSString* fullFilePathAndNameOfBridgeSupport;
@property(retain) NSString* fullFilePathAndNameOfSupportDylib;
@property(retain) NSString* fullFilePathAndNameOfFramework;
@property(retain) NSMutableDictionary* listOfDependsOnFrameworkNames;
@property(retain) NSMutableDictionary* xmlHashForFramework;
#if LUACOCOA_SAVE_RAW_XML_DATA
@property(retain) NSString* rawBridgeSupportData;
#endif

@end
