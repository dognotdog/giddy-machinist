//
//  GM3DPrinterDescription.m
//  Giddy Machinist
//
//  Created by Dömötör Gulyás on 28.04.2013.
//  Copyright (c) 2013 Dömötör Gulyás. All rights reserved.
//

#import "GM3DPrinterDescription.h"

@implementation GM3DPrinterDescription

+ (id) defaultPrinterDescription
{
	GM3DPrinterDescription* desc = [[GM3DPrinterDescription alloc] init];
	
	desc.extruderDescriptions = @[[GMExtruderDescription defaultExtruderDescription]];
	
	return desc;
}

@end

@implementation GMExtruderDescription

+ (id) defaultExtruderDescription
{
	GMExtruderDescription* desc = [[GMExtruderDescription alloc] init];
	desc.nozzleDiameter = 0.00035;
	
	
	return desc;
}

- (double) freeExtrusionDiameter
{
	return self.nozzleDiameter+0.00008;
}

@end



@implementation GM3DPrintSettings

+ (id) defaultPrintSettings
{
	GM3DPrintSettings* settings = [[GM3DPrintSettings alloc] init];
	
	settings.layerHeight = 0.0002;
	settings.numPerimeters = 3;
	
	settings.printerDescription = [GM3DPrinterDescription defaultPrinterDescription];
	
	
	
	
	return settings;
	
}

- (double) extrusionWidthForExtruder: (long) extruderIndex
{
	GMExtruderDescription* edesc = [self.printerDescription.extruderDescriptions objectAtIndex: extruderIndex];
	
	double freeExtrusionArea = 0.25*M_PI*edesc.freeExtrusionDiameter*edesc.freeExtrusionDiameter;
	
	double extrusionWidth = freeExtrusionArea/self.layerHeight;
	
	return extrusionWidth;
}

@end
