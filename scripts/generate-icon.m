#import <AppKit/AppKit.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "usage: generate-icon output.png\n");
            return 2;
        }

        const NSInteger size = 1024;
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL
                          pixelsWide:size
                          pixelsHigh:size
                       bitsPerSample:8
                     samplesPerPixel:4
                            hasAlpha:YES
                            isPlanar:NO
                      colorSpaceName:NSCalibratedRGBColorSpace
                         bytesPerRow:0
                        bitsPerPixel:0];
        NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = context;

        NSRect iconRect = NSMakeRect(72, 72, 880, 880);
        NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:iconRect xRadius:205 yRadius:205];
        NSGradient *gradient = [[NSGradient alloc]
            initWithStartingColor:[NSColor colorWithSRGBRed:0.38 green:0.34 blue:0.91 alpha:1]
                       endingColor:[NSColor colorWithSRGBRed:0.08 green:0.50 blue:0.61 alpha:1]];
        [gradient drawInBezierPath:background angle:-45];

        [[NSColor colorWithWhite:1 alpha:0.20] setStroke];
        NSBezierPath *divider = [NSBezierPath bezierPath];
        divider.lineWidth = 5;
        [divider moveToPoint:NSMakePoint(215, 512)];
        [divider lineToPoint:NSMakePoint(809, 512)];
        [divider stroke];

        NSFont *hebrewFont = [NSFont fontWithName:@"Arial Hebrew" size:430];
        hebrewFont = hebrewFont != nil ? hebrewFont : [NSFont systemFontOfSize:430 weight:NSFontWeightSemibold];
        NSDictionary *hebrewAttributes = @{
            NSFontAttributeName: hebrewFont,
            NSForegroundColorAttributeName: NSColor.whiteColor,
        };
        [@"א" drawAtPoint:NSMakePoint(275, 240) withAttributes:hebrewAttributes];

        NSDictionary *englishAttributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:390 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: NSColor.whiteColor,
        };
        [@"A" drawAtPoint:NSMakePoint(560, 235) withAttributes:englishAttributes];

        [NSGraphicsContext restoreGraphicsState];
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSString *outputPath = [NSString stringWithUTF8String:argv[1]];
        if (![png writeToFile:outputPath atomically:YES]) {
            fprintf(stderr, "could not write icon\n");
            return 1;
        }
    }
    return 0;
}
