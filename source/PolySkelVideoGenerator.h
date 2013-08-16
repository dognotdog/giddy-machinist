//
//  PolySkelVideoGenerator.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 15.08.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

@class PolygonSkeletizer;

@interface PolySkelVideoGenerator : NSObject

- (void) recordMovieToURL: (NSURL*) movieUrl withSize: (CGSize) size skeleton: (PolygonSkeletizer*) skeletizer finishedCallback: (void(^)(void)) finishedCallback;


@end
