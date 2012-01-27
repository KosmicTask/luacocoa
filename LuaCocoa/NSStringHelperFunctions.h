//
//  NSStringHelperFunctions.h
//  LuaCocoa
//
//  Created by Eric Wing on 7/18/11.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#ifndef LuaCocoa_NSStringHelperFunctions_h
#define LuaCocoa_NSStringHelperFunctions_h

#import <Foundation/Foundation.h>

/**
 * For a string like _foo or ___foo, returns just foo.
 * Otherwise, you get back the same string.
 * @return Returns a new autoreleased string. (Calls copy autorelease if no change needed.)
 */
NSString* NSStringHelperFunctions_StripLeadingUnderscores(NSString* nsstring);

/**
 * For a string like {CGPoint="x"d"y"d"}, returns {CGPoint=dd}.
 * @return Returns a new autoreleased string.
 */
NSString* NSStringHelperFunctions_StripQuotedCharacters(NSString* nsstring);

/**
 * Used for my decimal point detection. Is not localized because BridgeSupport is not localized.
 */
bool NSStringHelperFunctions_HasSinglePeriod(NSString* nsstring);

/**
 * For a string like "fooBar", returns "FooBar".
 * @return Returns a new autoreleased string.
 */
NSString* NSStringHelperFunctions_CapitalizeFirstCharacter(NSString* nsstring);


/* Unused functions */
#if 0
/**
 * For a string like {CGPoint="x"d"y"d"}, returns {CGPoint=xdyd}.
 * @return Returns a new autoreleased string.
 */
NSString* NSStringHelperFunctions_StripQuotes(NSString* nsstring);
/**
 * For a string like "foo", returns just foo.
 * If there is only a leading quote, it will strip it.
 * If there is only a trailing quote, it will strip it.
 * Otherwise, you get back the same string.
 * @return Returns a new autoreleased string. (Calls copy autorelease if no change needed.)
 */
NSString* NSStringHelperFunctions_StripSurroundingQuotes(NSString* nsstring);
#endif



#endif // LuaCocoa_NSStringHelperFunctions_h
