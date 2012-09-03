//
//  RS274Parser.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 31.08.2012.
//  Copyright (c) 2012 Dömötör Gulyás. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface RS274Parser : NSObject

@property(nonatomic,strong) NSArray* commandBlocks;

- (NSArray*) parseString: (NSString*) text named: (NSString*) name;

@end



@interface RS274Command : NSObject

@property(nonatomic) int commandLetter;
@property(nonatomic,strong) id value;

@end



@interface RS274Operator : NSObject

@property(nonatomic) long precedenceLevel;
@property(nonatomic,strong) id name;
@property(nonatomic,strong) NSArray* operands;

@end

