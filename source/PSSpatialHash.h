//
//  PSSpatialHash.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 18.06.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath_fixp.h"

@class PSMotorcycle, MPDecimal;

@interface PSSpatialHash : NSObject

- (id) initWithGridSize: (vmintfix_t) size numCells: (size_t) ncells;

- (void) addEdgeSegments: (NSArray*) segments;

- (id) crashMotorcycleIntoEdges: (PSMotorcycle*) cycle withLimit: (MPDecimal*) limit;

@end
