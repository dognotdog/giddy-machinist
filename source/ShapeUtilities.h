//
//  ShapeUtilities.h
//
//

#import <Foundation/Foundation.h>

@class NSBezierPath;

@interface ShapeUtilities : NSObject

+ (NSBezierPath*) createBezierPathFromData: (NSData*) data;

@end
