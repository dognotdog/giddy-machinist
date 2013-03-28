//
//  PolygonExtender.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 05.11.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PolygonExtender : NSObject

@property(nonatomic) double extensionLimit;
@property(nonatomic) double mergeThreshold;


- (NSArray*) extendToOffsets: (NSArray*) offsets;

@end
