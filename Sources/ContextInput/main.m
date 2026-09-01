#import <AppKit/AppKit.h>
#import "CIAppController.h"

int main(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        CIAppController *controller = [[CIAppController alloc] init];
        application.delegate = controller;
        [application run];
    }
    return 0;
}
