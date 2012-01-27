//
//  NSStringHelperCategories.m
//  LuaCocoa
//
//  Created by Eric Wing on 10/18/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "NSStringHelperCategories.h"

@implementation NSString (LuaCocoa)

- (NSString*) stripLeadingUnderscores
{
	if([self hasPrefix:@"_"])
	{
		// String may have multiple underscores
		__strong const char* current_char = [self UTF8String];
		NSUInteger number_of_underscores = 0;
		while('_' == *current_char)
		{
			number_of_underscores++;
			current_char++;
		}
		
		return [self substringFromIndex:number_of_underscores];
	}
	else
	{
		return [[self copy] autorelease];
	}
	
}

- (NSString*) stripQuotes
{
	NSMutableString* stripped_string = [self mutableCopy];
	[stripped_string replaceOccurrencesOfString:@"\"" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [stripped_string length])];
	return [stripped_string autorelease];
}

- (NSString*) stripQuotedCharacters
{
	__strong const char* c_string = [self UTF8String];
	NSUInteger string_length = strlen(c_string) + 1;
	char temp_string[string_length];
	NSUInteger i=0;
	NSUInteger j=0;
	for(i=0, j=0; i<string_length; i++)
	{
		if('\"' == c_string[i])
		{
			do
			{
				i++;
			} while('\"' != c_string[i]);
		}
		else
		{
			temp_string[j] = c_string[i];
			j++;
		}
	}
	j++;
	temp_string[j] = '\0';
	return [NSString stringWithUTF8String:temp_string];
}

- (NSString*) stripSurroundingQuotes
{
	if([self hasPrefix:@"\""] && [self hasSuffix:@"\""])
	{
		return [self substringWithRange:NSMakeRange(1, [self length]-2)];
	}
	else if([self hasPrefix:@"\""])
	{
		return [self substringFromIndex:1];
	}
	else if([self hasSuffix:@"\""])
	{
		return [self substringToIndex:[self length]-1];
	}
	else
	{
		return [[self copy] autorelease];
	}
}

- (bool) hasSinglePeriod
{
    if([self length] == 0)
	{
		return false;
	}
	NSUInteger number_of_periods = 0;
    for(NSUInteger i=0; i<[self length]; i++) 
    {
        unichar single_char = [self characterAtIndex:i];
		if('.' == single_char)
		{
			number_of_periods++;
		}
    }
	return(1 == number_of_periods);
}

- (NSString*) capitalizeFirstCharacter
{
	NSString* first_cap_char = [[self substringToIndex:1] capitalizedString];
	return [self stringByReplacingCharactersInRange:NSMakeRange(0,1) withString:first_cap_char];
}

@end