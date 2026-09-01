#import <Foundation/Foundation.h>

static void CIAppendBigEndianUInt32(NSMutableData *data, uint32_t value) {
    uint32_t encoded = CFSwapInt32HostToBig(value);
    [data appendBytes:&encoded length:sizeof(encoded)];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) {
            fprintf(stderr, "usage: package-icns iconset-directory output.icns\n");
            return 2;
        }

        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        NSString *output = [NSString stringWithUTF8String:argv[2]];
        NSArray<NSArray<NSString *> *> *entries = @[
            @[@"icp4", @"icon_16x16.png"],
            @[@"icp5", @"icon_32x32.png"],
            @[@"icp6", @"icon_32x32@2x.png"],
            @[@"ic07", @"icon_128x128.png"],
            @[@"ic08", @"icon_256x256.png"],
            @[@"ic09", @"icon_512x512.png"],
            @[@"ic10", @"icon_512x512@2x.png"],
        ];

        NSMutableArray<NSArray *> *payloads = [NSMutableArray array];
        uint64_t totalLength = 8;
        for (NSArray<NSString *> *entry in entries) {
            NSString *path = [directory stringByAppendingPathComponent:entry[1]];
            NSData *png = [NSData dataWithContentsOfFile:path];
            if (png == nil) {
                fprintf(stderr, "missing icon image: %s\n", path.UTF8String);
                return 1;
            }
            [payloads addObject:@[entry[0], png]];
            totalLength += 8 + png.length;
        }

        if (totalLength > UINT32_MAX) {
            return 1;
        }
        NSMutableData *icns = [NSMutableData dataWithCapacity:(NSUInteger)totalLength];
        [icns appendBytes:"icns" length:4];
        CIAppendBigEndianUInt32(icns, (uint32_t)totalLength);
        for (NSArray *payload in payloads) {
            NSString *type = payload[0];
            NSData *png = payload[1];
            [icns appendData:[type dataUsingEncoding:NSASCIIStringEncoding]];
            CIAppendBigEndianUInt32(icns, (uint32_t)(8 + png.length));
            [icns appendData:png];
        }

        if (![icns writeToFile:output atomically:YES]) {
            fprintf(stderr, "could not write icns file\n");
            return 1;
        }
    }
    return 0;
}
