/*
 *  TextEditorSupport.c
 *  LuaCocoa
 *
 *  Copyright 2008 Eric Wing. All rights reserved.
 *
 */

#include "TextEditorSupport.h"


void TextEditorSupport_LaunchTextEditorWithFile(NSString* file_name, NSInteger line_number)
{
	NSString* app_name = nil;
	NSString* file_extension = nil;
	
	if(line_number < 0)
	{
		line_number = 0;
	}
	
	BOOL ret_flag = [[NSWorkspace sharedWorkspace] getInfoForFile:file_name application:&app_name type:&file_extension];
	if(YES == ret_flag)
	{
		//			NSLog(@"file_name=%@, ext=%@", app_name, file_extension);
		NSString* base_app_name = [app_name lastPathComponent];
		if([base_app_name isEqualToString:@"Xcode.app"])
		{
			// FIXME: Should try to dynamically find correct path for xed
			NSString* line_number_string_arg = [NSString stringWithFormat:@"%d", line_number];
			@try
			{
				[NSTask launchedTaskWithLaunchPath:@"/usr/bin/xed" arguments:[NSArray arrayWithObjects:@"-l", line_number_string_arg, file_name, nil]];
			}
			@catch(NSException* the_exception)
			{
				[[NSWorkspace sharedWorkspace] openFile:file_name];
			}
		}
		else if([base_app_name isEqualToString:@"TextMate.app"])
		{
			/*
			NSString* line_number_string_arg = [NSString stringWithFormat:@"%d", line_number];
			//				NSString* mate_path = [NSString stringWithFormat:@"%s/bin/mate", getenv("TM_SUPPORT_PATH")];
			NSString* mate_path = [NSString stringWithFormat:@"%@/Contents/SharedSupport/Support/bin/mate", app_name];
			@try
			{
				[NSTask launchedTaskWithLaunchPath:mate_path arguments:[NSArray arrayWithObjects:@"-l", line_number_string_arg, file_name, nil]];
			}
			@catch(NSException* the_exception)
			{
				[[NSWorkspace sharedWorkspace] openFile:file_name];
			}
			*/
			// TextMate's URL scheme found here:
			// http://blog.macromates.com/2007/the-textmate-url-scheme/
			NSString* url_string = [NSString stringWithFormat:@"txmt://open?url=file://%@&line=%d", file_name, line_number];
			url_string = [url_string stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
			NSURL* textmate_url = [NSURL URLWithString:url_string];
			[[NSWorkspace sharedWorkspace] openURL:textmate_url];
		}
		else if([base_app_name isEqualToString:@"TextWrangler.app"])
		{
			// FIXME: Should try to dynamically find correct path for xed
			NSString* line_number_string_arg = [NSString stringWithFormat:@"%d", line_number];
			NSString* wrangler_path = [NSString stringWithFormat:@"%@/Contents/Resources/edit", app_name];
			@try
			{
				[NSTask launchedTaskWithLaunchPath:wrangler_path arguments:[NSArray arrayWithObjects:@"-l", line_number_string_arg, file_name, nil]];
			}
			@catch(NSException* the_exception)
			{
				[[NSWorkspace sharedWorkspace] openFile:file_name];
			}
		}
		else if([base_app_name isEqualToString:@"MacVim.app"])
		{
		/*
			NSString* line_number_string_arg = [NSString stringWithFormat:@"+%d", line_number];
			NSString* gvim_path = [NSString stringWithFormat:@"%@/Contents/MacOS/Vim", app_name];
			@try
			{
				[NSTask launchedTaskWithLaunchPath:gvim_path arguments:[NSArray arrayWithObjects:@"-g", line_number_string_arg, file_name, nil]];
			}
			@catch(NSException* the_exception)
			{
				[[NSWorkspace sharedWorkspace] openFile:file_name];
			}
		*/
			// Found better way asking on the MacVim mailing list.
			// This solves the already open problem.
			//	mvim://open?url=file:///Users/ewing/TEMP/fee.lua&line=3
			// see ":h mvim://"
			// This is based on TextMate's URL scheme found here:
			// http://blog.macromates.com/2007/the-textmate-url-scheme/
			NSString* url_string = [NSString stringWithFormat:@"mvim://open?url=file://%@&line=%d", file_name, line_number];
			url_string = [url_string stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
			NSURL* mvim_url = [NSURL URLWithString:url_string];
			[[NSWorkspace sharedWorkspace] openURL:mvim_url];
			
		}
		else if([base_app_name isEqualToString:@"BBEdit.app"])
		{
			// FIXME: Should try to dynamically find correct path for xed
			NSString* line_number_string_arg = [NSString stringWithFormat:@"+%d", line_number];
			NSString* bbedit_path = [NSString stringWithFormat:@"%@/Contents/MacOS/bbedit_tool", app_name];
			@try
			{
				[NSTask launchedTaskWithLaunchPath:bbedit_path arguments:[NSArray arrayWithObjects:line_number_string_arg, file_name, nil]];
			}
			@catch(NSException* the_exception)
			{
				[[NSWorkspace sharedWorkspace] openFile:file_name];
			}
		}
		else
		{
			[[NSWorkspace sharedWorkspace] openFile:file_name];
		}
	}
	else
	{
		[[NSWorkspace sharedWorkspace] openFile:file_name withApplication:@"TextEdit.app"];
	}
}
