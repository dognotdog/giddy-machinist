//
//  PSWavefrontSnapshot.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 28.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath.h"

@class PSWaveFront, PSVertex;


/*!
 @description The wavefront snapshot contains the offset wavefronts at a given time, while keeping track of the wavefront objects.
 */
@interface PSWaveFrontSnapshot : NSObject

@property(nonatomic) double time;

@property(nonatomic, strong) NSArray* loops;

@property(nonatomic, readonly) NSBezierPath* waveFrontPath;

@end

@interface PSWaveFrontSegment : NSObject

@property(nonatomic) double time;

@property(nonatomic, strong) PSWaveFront* waveFront;
@property(nonatomic, strong) PSVertex* leftVertex;
@property(nonatomic, strong) PSVertex* rightVertex;


@end
