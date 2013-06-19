//
//  PSWavefrontSnapshot.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 28.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

@import AppKit;

#import <Foundation/Foundation.h>

#import "VectorMath.h"

@class PSWaveFront, PSRealVertex, MPDecimal;


/*!
 @description The wavefront snapshot contains the offset wavefronts at a given time, while keeping track of the wavefront objects.
 */
@interface PSWaveFrontSnapshot : NSObject

@property(nonatomic, strong) MPDecimal*		time;
@property(nonatomic, strong) NSArray*		loops;

@property(nonatomic, readonly) NSBezierPath* waveFrontPath;

- (NSBezierPath*) thinWallAreaLessThanWidth: (double) width;

@end

@interface PSWaveFrontSegment : NSObject

@property(nonatomic, strong) MPDecimal*		time;
@property(nonatomic, readonly) MPDecimal*	finalTerminationTime;

@property(nonatomic, strong) NSArray* waveFronts;
@property(nonatomic, weak) PSWaveFrontSegment* leftSegment;
@property(nonatomic, weak) PSWaveFrontSegment* rightSegment;
@property(nonatomic, strong) PSRealVertex* leftVertex;
@property(nonatomic, strong) PSRealVertex* rightVertex;


@end
