//
//  GM3DPrinterDescription.h
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 28.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GM3DPrinterDescription : NSObject

@property(nonatomic,strong) NSArray* extruderDescriptions;
@property(nonatomic,strong) NSDictionary* axisDescriptions;

+ (id) defaultPrinterDescription;

@end


@interface GMExtruderDescription : NSObject

@property(nonatomic) double nozzleDiameter;
@property(nonatomic,readonly) double freeExtrusionDiameter;

+ (id) defaultExtruderDescription;

@end

@interface GM3DPrintSettings : NSObject

@property(nonatomic) double layerHeight;
@property(nonatomic) long numPerimeters;

- (double) extrusionWidthForExtruder: (long) extruderIndex;


@property(nonatomic,strong) GM3DPrinterDescription* printerDescription;


+ (id) defaultPrintSettings;

@end

