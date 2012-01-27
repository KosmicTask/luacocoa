//
//  NSStringHelperFunctions.c
//  LuaCocoa
//
//  Created by Eric Wing on 7/18/11.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import "NSStringHelperFunctions.h"


NSString* NSStringHelperFunctions_StripLeadingUnderscores(NSString* nsstring)
{
	if([nsstring hasPrefix:@"_"])
	{
		// String may have multiple underscores
		__strong const char* current_char = [nsstring UTF8String];
		NSUInteger number_of_underscores = 0;
		while('_' == *current_char)
		{
			number_of_underscores++;
			current_char++;
		}
		
		return [nsstring substringFromIndex:number_of_underscores];
	}
	else
	{
		return [[nsstring copy] autorelease];
	}
	
}

NSString* NSStringHelperFunctions_StripQuotedCharacters(NSString* nsstring)
{
	__strong const char* c_string = [nsstring UTF8String];
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


bool NSStringHelperFunctions_HasSinglePeriod(NSString* nsstring)
{
    if([nsstring length] == 0)
	{
		return false;
	}
	NSUInteger number_of_periods = 0;
    for(NSUInteger i=0; i<[nsstring length]; i++) 
    {
        unichar single_char = [nsstring characterAtIndex:i];
		if('.' == single_char)
		{
			number_of_periods++;
		}
    }
	return(1 == number_of_periods);
}

NSString* NSStringHelperFunctions_CapitalizeFirstCharacter(NSString* nsstring)
{
	NSString* first_cap_char = [[nsstring substringToIndex:1] capitalizedString];
	return [nsstring stringByReplacingCharactersInRange:NSMakeRange(0,1) withString:first_cap_char];
}

/* Unused functions */
#if 0
NSString* NSStringHelperFunctions_StripQuotes(NSString* nsstring)
{
	NSMutableString* stripped_string = [nsstring mutableCopy];
	[nsstring replaceOccurrencesOfString:@"\"" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [nsstring length])];
	return [nsstring autorelease];
}

NSString* NSStringHelperFunctions_StripSurroundingQuotes(NSString* nsstring)
{
	if([nsstring hasPrefix:@"\""] && [nsstring hasSuffix:@"\""])
	{
		return [nsstring substringWithRange:NSMakeRange(1, [nsstring length]-2)];
	}
	else if([nsstring hasPrefix:@"\""])
	{
		return [nsstring substringFromIndex:1];
	}
	else if([nsstring hasSuffix:@"\""])
	{
		return [nsstring substringToIndex:[nsstring length]-1];
	}
	else
	{
		return [[nsstring copy] autorelease];
	}
}
#endif
