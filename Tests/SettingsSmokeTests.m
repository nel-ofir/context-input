#import <AppKit/AppKit.h>
#import "CIAppController.h"

@interface CIAppController (SettingsTest)
- (void)buildSettingsWindow;
- (void)updateInterface;
- (void)showSettings:(id)sender;
@end

@interface CIReopenTestController : CIAppController
@property(nonatomic) BOOL didRequestSettings;
@end

@implementation CIReopenTestController
- (void)showSettings:(id)sender {
    self.didRequestSettings = YES;
}
@end

// Does not launch monitoring, activate another app, or select any input source.
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        CIAppController *controller = [[CIAppController alloc] init];
        [controller buildSettingsWindow];
        [controller setValue:[@"Before: Hebrew → target: ABC • +250 ms: ABC • +650 ms: ABC • "
            stringByPaddingToLength:700 withString:@"Diagnostic text. " startingAtIndex:0]
            forKey:@"lastSwitchSummary"];
        [controller setValue:@"root=window focusFrame=ok stop=window reached\nInitial: nodes=1800 depth=24 depthCuts=1 budget=exhausted textRoles=1200 missingFrames=0 geometry=0/1200 pruned=0 candidates=0\nFallback (1 scopes): nodes=1800 depth=24 depthCuts=1 budget=exhausted textRoles=1200 missingFrames=0 geometry=0/1200 pruned=0 candidates=0"
            forKey:@"lastScanDiagnostics"];
        [controller updateInterface];
        NSWindow *window = [controller valueForKey:@"settingsWindow"];
        [window setContentSize:NSMakeSize(590, 450)];
        [window.contentView layoutSubtreeIfNeeded];
        NSScrollView *scroll = (NSScrollView *)window.contentView.subviews.firstObject;
        NSView *document = scroll.documentView;
        NSTextField *label = [controller valueForKey:@"switchLabel"];
        NSRect labelRect = [label convertRect:label.bounds toView:document];
        BOOL fits = [scroll isKindOfClass:NSScrollView.class] && scroll.hasVerticalScroller &&
            document.frame.size.height > scroll.contentView.bounds.size.height &&
            document.frame.size.width <= scroll.contentView.bounds.size.width + 1 &&
            labelRect.size.height > 20 && NSMaxY(labelRect) <= document.bounds.size.height;
        fprintf(stdout, "Settings layout: document %.0fx%.0f, viewport %.0fx%.0f, diagnostics height %.0f.\n",
            document.frame.size.width, document.frame.size.height,
            scroll.contentView.bounds.size.width, scroll.contentView.bounds.size.height, labelRect.size.height);
        if (!fits) {
            fputs("FAIL: Settings diagnostics must fit the scrollable document.\n", stderr);
            return 1;
        }
        NSTextField *scanLabel = [controller valueForKey:@"reasonLabel"];
        NSRect scanRect = [scanLabel convertRect:scanLabel.bounds toView:document];
        if (![scanLabel.stringValue containsString:@"Scan: root=window"] ||
            scanRect.size.height <= 40 || NSMaxY(scanRect) > NSMinY(labelRect)) {
            fputs("FAIL: Scan diagnostics must wrap and not overlap later fields.\n", stderr);
            return 1;
        }

        CIReopenTestController *reopenController = [[CIReopenTestController alloc] init];
        BOOL handled = [reopenController applicationShouldHandleReopen:NSApplication.sharedApplication
                                                     hasVisibleWindows:NO];
        if (!handled || !reopenController.didRequestSettings) {
            fputs("FAIL: Reopening the running menu-bar app must reveal Settings.\n", stderr);
            return 1;
        }
        puts("Settings layout smoke test passed.");
    }
    return 0;
}
