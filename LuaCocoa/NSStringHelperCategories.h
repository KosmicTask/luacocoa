//
//  NSStringHelperCategories.h
//  LuaCocoa
//
//  Created by Eric Wing on 10/18/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//
#warning "NSStringHelperCategories is obsolete and replaced by NSStringHelperFunctions"

#ifndef LuaCocoa_NSStringHelpeCategories_h
#define LuaCocoa_NSStringHelpeCategories_h

#import <Foundation/Foundation.h>

@interface NSString (LuaCocoa)

/**
 * For a string like _foo or ___foo, returns just foo.
 * Otherwise, you get back the same string.
 * @return Returns a new autoreleased string. (Calls copy autorelease if no change needed.)
 */
- (NSString*) stripLeadingUnderscores;

/**
 * For a string like {CGPoint="x"d"y"d"}, returns {CGPoint=xdyd}.
 * @return Returns a new autoreleased string.
 */
- (NSString*) stripQuotes;

/**
 * For a string like {CGPoint="x"d"y"d"}, returns {CGPoint=dd}.
 * @return Returns a new autoreleased string.
 */
- (NSString*) stripQuotedCharacters;

/**
 * For a string like "foo", returns just foo.
 * If there is only a leading quote, it will strip it.
 * If there is only a trailing quote, it will strip it.
 * Otherwise, you get back the same string.
 * @return Returns a new autoreleased string. (Calls copy autorelease if no change needed.)
 */
- (NSString*) stripSurroundingQuotes;

/**
 * Used for my decimal point detection. Is not localized because BridgeSupport is not localized.
 */
- (bool) hasSinglePeriod;

/**
 * For a string like "fooBar", returns "FooBar".
 * @return Returns a new autoreleased string.
 */
- (NSString*) capitalizeFirstCharacter;




@end

#endif /* LuaCocoa_NSStringHelpeCategories_h */
