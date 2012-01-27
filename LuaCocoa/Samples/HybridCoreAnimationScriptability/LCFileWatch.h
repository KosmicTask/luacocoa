//
//  LCFileWatch.h
//  LuaCocoa
//
//  Copyright 2008 Eric Wing. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifndef _LCFILEWATCH_H_
#define _LCFILEWATCH_H_

#import <Foundation/Foundation.h>
#include <sys/stat.h>


#ifdef __cplusplus
extern "C" {
#endif
	
FSEventStreamRef FileWatch_StartMonitoringFolder(NSString* folder_path, FSEventStreamCallback callback_function, FSEventStreamContext* callback_user_data);
void FileWatch_StopMonitoringFolder(FSEventStreamRef event_stream);
	
	
@interface LCFileWatch : NSObject
{
	NSString* originalFileName;
	NSString* absoluteFileName;
	struct stat lastModifiedTimeStat;
}


@property(copy) NSString* originalFileName;
@property(copy) NSString* absoluteFileName;
@property(assign) struct stat lastModifiedTimeStat;

- (id) initWithFile:(NSString*)the_file;
- (void) clearTimeStamp:(struct stat*)file_stat;
- (struct stat) lastTimeModification:(NSString*)absolute_file;
- (BOOL) fileHasBeenChanged;
- (void) updateTimeStat;


@end
	
#ifdef __cplusplus
}
#endif

#endif //_LCFILEWATCH_H_