//
//  ParseSupportMethod.h
//  LuaCocoa
//
//  Created by Eric Wing on 10/28/09.
//  Copyright 2009 PlayControl Software, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ParseSupportFunction.h"

@interface ParseSupportMethod : ParseSupportFunction
{
	bool notFound; // for forwardInvocation
	NSString* className;
}
- (id) initWithClassName:(NSString *)class_name methodName:(NSString*)method_name isInstance:(bool)is_instance theReceiver:(id)the_receiver isClassMethod:(bool)is_class_method stringMethodSignature:(const char*)method_signature;
- (id) initWithClassName:(NSString *)class_name methodName:(NSString*)method_name isInstance:(bool)is_instance theReceiver:(id)the_receiver isClassMethod:(bool)is_class_method;

- (id) initWithClassName:(NSString *)class_name methodName:(NSString*)method_name isInstance:(bool)is_instance theReceiver:(id)the_receiver isClassMethod:(bool)is_class_method;
- (id) initWithClassName:(NSString *)class_name methodName:(NSString*)method_name isInstance:(bool)is_instance theReceiver:(id)the_receiver isClassMethod:(bool)is_class_method stringMethodSignature:(const char*)method_signature;


@property(assign) bool notFound;
@property(copy, readonly) NSString* className;

@end
