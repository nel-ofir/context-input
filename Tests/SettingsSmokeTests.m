#import <AppKit/AppKit.h>
#import "CIAppController.h"

@interface CIAppController (SettingsTest)
- (void)buildSettingsWindow;
- (void)updateInterface;
@end

// Does not launch monitoring, activate another app, or select any input source.
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        CIAppController *controller = [[CIAppController alloc] init];
        [controller buildSettingsWindow];
        [controller setValue:[@"Before: Hebrew → target: ABC • +250 ms: ABC; one reapply accepted • +650 ms: ABC • "
            stringByPaddingToLength:700 withString:@"Diagnostic text. " startingAtIndex:0]
            forKey:@"lastSwitchSummary"];
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
        puts("Settings layout smoke test passed.");
    }
    return 0;
}
