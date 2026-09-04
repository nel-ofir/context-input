#import <Foundation/Foundation.h>
#import "CIApplicationCapabilities.h"
#import "CIInputSourceManager.h"

int main(void) {
    @autoreleasepool {
        CIInputSourceManager *manager = [[CIInputSourceManager alloc] init];
        NSArray<CIKeyboardInputSource *> *sources = [manager availableKeyboardSources];
        CIKeyboardInputSource *current = [manager currentSource];
        if (sources.count == 0 || current == nil) {
            fprintf(stderr, "No selectable keyboard input source was found.\n");
            return 1;
        }

        BOOL currentAppearsInSources = NO;
        for (CIKeyboardInputSource *source in sources) {
            if ([source.identifier isEqualToString:current.identifier]) {
                currentAppearsInSources = YES;
                break;
            }
        }
        if (!currentAppearsInSources) {
            fprintf(stderr, "The current input source was missing from the selectable list.\n");
            return 1;
        }
        printf("Input-source smoke test passed (%lu selectable, current: %s).\n",
               (unsigned long)sources.count,
               current.name.UTF8String);

        NSArray<NSDictionary<NSString *, id> *> *applicationChecks = @[
            @{
                @"name": @"Apple Terminal",
                @"path": @"/System/Applications/Utilities/Terminal.app",
                @"expected": @YES,
            },
            @{
                @"name": @"Warp",
                @"path": @"/Applications/Warp.app",
                @"expected": @YES,
            },
            @{
                @"name": @"Cursor",
                @"path": @"/Applications/Cursor.app",
                @"expected": @NO,
            },
        ];
        for (NSDictionary<NSString *, id> *check in applicationChecks) {
            NSString *path = check[@"path"];
            NSBundle *bundle = [NSBundle bundleWithPath:path];
            if (bundle == nil) {
                continue;
            }
            BOOL actual = [CIApplicationCapabilities
                infoDictionaryDeclaresTerminalSupport:bundle.infoDictionary];
            BOOL expected = [check[@"expected"] boolValue];
            if (actual != expected) {
                fprintf(stderr, "Terminal capability mismatch for %s.\n",
                        [check[@"name"] UTF8String]);
                return 1;
            }
            printf("Capability check passed (%s: terminal host = %s).\n",
                   [check[@"name"] UTF8String], actual ? "yes" : "no");
        }
    }
    return 0;
}
