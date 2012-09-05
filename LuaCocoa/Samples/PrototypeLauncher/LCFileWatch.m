//
//  LCFileWatch.h
//  LuaCocoa
//
//  Copyright 2008 Eric Wing. All rights reserved.
//

#import "LCFileWatch.h"


FSEventStreamRef FileWatch_StartMonitoringFolder(NSString* folder_path, FSEventStreamCallback callback_function, FSEventStreamContext* callback_user_data)
{
	if(nil == folder_path)
	{
		return NULL;
	}
    /* Define variables and create a CFArray object containing
	 
	 CFString objects containing paths to watch.
	 
     */
	
	
	NSMutableArray* paths_to_watch = [NSMutableArray arrayWithObject:folder_path];
	
	FSEventStreamRef event_stream;
	CFAbsoluteTime time_latency = 0.25; /* Latency in seconds */
	/*
	 FSEventStreamContext callback_info =
	 {
	 0,
	 self,
	 CFRetain,
	 CFRelease,
	 NULL
	 };
	 */	
    /* Create the stream, passing in a callback, */
	event_stream = FSEventStreamCreate(
		NULL,
		callback_function,
		callback_user_data,
		(CFArrayRef)paths_to_watch,
		kFSEventStreamEventIdSinceNow, /* Or a previous event ID */
		time_latency,
		kFSEventStreamCreateFlagNone /* Flags explained in reference */
	);
	
	
	/* Create the stream before calling this. */
	//	FSEventStreamScheduleWithRunLoop(event_stream, [NSRunLoop currentRunLoop], kCFRunLoopDefaultMode);
	//	FSEventStreamScheduleWithRunLoop(event_stream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	FSEventStreamScheduleWithRunLoop(event_stream, [[NSRunLoop currentRunLoop] getCFRunLoop], kCFRunLoopDefaultMode);
	
    FSEventStreamStart(event_stream);
	
	return event_stream;
}

void FileWatch_StopMonitoringFolder(FSEventStreamRef event_stream)
{
	if(NULL != event_stream)
	{
		FSEventStreamStop(event_stream);
		FSEventStreamInvalidate(event_stream);
		FSEventStreamRelease(event_stream);		
	}
}


@implementation LCFileWatch

@synthesize originalFileName;
@synthesize absoluteFileName;
@synthesize lastModifiedTimeStat;

- (id) initWithFile:(NSString*)the_file
{
	self = [super init];
	if(nil != self)
	{
		self.originalFileName = the_file;
		if([the_file isAbsolutePath])
		{
			self.absoluteFileName = the_file;
		}
		else
		{
			// Warning: Expecting a .app bundle.
			self.absoluteFileName = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:the_file];
		}
		/*
		 if([self.absoluteFileName fileExistsAtPath])
		 {
		 }
		 */
		self.lastModifiedTimeStat = [self lastTimeModification:self.absoluteFileName];		
	}
	return self;
}

- (void) dealloc
{
	[originalFileName release];
	[absoluteFileName release];
	[super dealloc];
}

- (void) clearTimeStamp:(struct stat*)file_stat
{
	memset( file_stat, 0, sizeof( struct stat ) );
	
}

- (struct stat) lastTimeModification:(NSString*)absolute_file
{
	struct stat current_time_stamp;
	if(!absolute_file)
	{
		[self clearTimeStamp:&current_time_stamp];
		
		return current_time_stamp;
	}
	int error_flag = stat([absolute_file fileSystemRepresentation], &current_time_stamp);
	if(error_flag)
	{
		[self clearTimeStamp:&current_time_stamp];
		NSLog(@"Got error in FileWatch lastTimeModification");
	}
	return current_time_stamp;
}

- (BOOL) fileHasBeenChanged
{
	struct stat current_time_stamp = [self lastTimeModification:self.absoluteFileName];
#ifdef __APPLE__
	if(current_time_stamp.st_mtimespec.tv_sec > self.lastModifiedTimeStat.st_mtimespec.tv_sec )
#else
		if( now.st_mtime > _filetime.st_mtime)
#endif
		{
			return YES;
		}
		else
		{
			return NO;
		}
	
}

- (void) updateTimeStat
{
	struct stat current_time_stamp = [self lastTimeModification:self.absoluteFileName];
#ifdef __APPLE__
	if(current_time_stamp.st_mtimespec.tv_sec > self.lastModifiedTimeStat.st_mtimespec.tv_sec )
	{
#else
		if( now.st_mtime > _filetime.st_mtime)
#endif
		{
			self.lastModifiedTimeStat = current_time_stamp;
		}
	}
}

- (BOOL) isEqual:(id)to_object
{
	if([to_object isKindOfClass:[LCFileWatch class]])
	{
		return [[self absoluteFileName] isEqual:[to_object absoluteFileName]];
	}
	return NO;
}

- (NSUInteger) hash
{
	return [[self absoluteFileName] hash];
}

- (NSString*) description
{
	return [self absoluteFileName];
}


@end
