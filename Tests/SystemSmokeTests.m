#import <Foundation/Foundation.h>
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
    }
    return 0;
}
