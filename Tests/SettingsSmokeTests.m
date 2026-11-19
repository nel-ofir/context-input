#import <AppKit/AppKit.h>
#import "CIAppController.h"
#import "CIAppLanguagePreferences.h"

@interface CIAppController (SettingsTest)
- (void)buildSettingsWindow;
- (void)updateInterface;
- (void)showSettings:(id)sender;
- (CILanguageDecision *)decisionForContext:(CIScreenContext *)context;
- (void)appLanguagePopupChanged:(NSPopUpButton *)sender;
- (void)updateAppLanguagePopup;
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

        NSString *suiteName = [@"com.contextinput.app-default-test." stringByAppendingString:
            NSUUID.UUID.UUIDString];
        NSUserDefaults *testDefaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
        CIAppLanguagePreferences *preferences = [[CIAppLanguagePreferences alloc]
            initWithDefaults:testDefaults];
        [controller setValue:preferences forKey:@"appLanguagePreferences"];
        [controller setValue:@"com.example.chat" forKey:@"selectedAppIdentifier"];
        NSPopUpButton *appLanguagePopup = [controller valueForKey:@"appLanguagePopup"];
        [appLanguagePopup selectItemWithTag:1];
        [controller appLanguagePopupChanged:appLanguagePopup];
        CIScreenContext *context = [[CIScreenContext alloc]
            initWithApplicationName:@"Example Chat"
                 bundleIdentifier:@"com.example.chat"
                             draft:nil
                       nearbyTexts:@[@"This conversation is in English."]
                      terminalLike:YES focusDescription:@"AXTextArea"];
        CILanguageDecision *decision = [controller decisionForContext:context];
        if (decision.language != CIInputLanguageHebrew ||
            ![decision.reason isEqualToString:@"the app default"] ||
            ![preferences.configuredBundleIdentifiers containsObject:@"com.example.chat"]) {
            fputs("FAIL: Hebrew app default must override context and terminal fallback when the draft is empty.\n", stderr);
            return 1;
        }
        context.draft = @"שלום";
        if ([controller decisionForContext:context].language != CIInputLanguageHebrew ||
            ![[controller decisionForContext:context].reason isEqualToString:@"the existing draft"]) {
            fputs("FAIL: Hebrew text in the field must take precedence over the app default.\n", stderr);
            return 1;
        }
        if ([controller decisionForContext:[[CIScreenContext alloc]
            initWithApplicationName:@"Other App" bundleIdentifier:@"com.example.other"
            draft:@"Please answer in English." nearbyTexts:@[]
            terminalLike:NO focusDescription:@"AXTextArea"]].language != CIInputLanguageEnglish) {
            fputs("FAIL: An app default must not affect other apps.\n", stderr);
            return 1;
        }
        NSPopUpButton *appPopup = [controller valueForKey:@"appPopup"];
        if (![appPopup.selectedItem.representedObject isEqualToString:@"com.example.chat"] ||
            appLanguagePopup.selectedItem.tag != 1) {
            fputs("FAIL: Settings must show the saved app and selected language.\n", stderr);
            return 1;
        }
        CIAppLanguagePreferences *reloaded = [[CIAppLanguagePreferences alloc]
            initWithDefaults:testDefaults];
        if ([reloaded languageForBundleIdentifier:@"com.example.chat"].integerValue != CIInputLanguageHebrew) {
            fputs("FAIL: App default must persist across instances.\n", stderr);
            return 1;
        }
        [appLanguagePopup selectItemWithTag:2];
        [controller appLanguagePopupChanged:appLanguagePopup];
        if ([controller decisionForContext:context].language != CIInputLanguageHebrew) {
            fputs("FAIL: A Hebrew draft must override an English app default.\n", stderr);
            return 1;
        }
        context.draft = @"English draft";
        if ([controller decisionForContext:context].language != CIInputLanguageEnglish) {
            fputs("FAIL: English text in the field must be selected.\n", stderr);
            return 1;
        }
        [appLanguagePopup selectItemWithTag:1];
        [controller appLanguagePopupChanged:appLanguagePopup];
        if ([controller decisionForContext:context].language != CIInputLanguageEnglish) {
            fputs("FAIL: An English draft must override a Hebrew app default.\n", stderr);
            return 1;
        }
        context.draft = @"?";
        if ([controller decisionForContext:context].language != CIInputLanguageHebrew) {
            fputs("FAIL: Ambiguous draft text must fall back to the app default.\n", stderr);
            return 1;
        }
        context.draft = @"Please answer in English.";
        [appLanguagePopup selectItemWithTag:0];
        [controller appLanguagePopupChanged:appLanguagePopup];
        if ([preferences languageForBundleIdentifier:@"com.example.chat"] != nil ||
            ![[controller decisionForContext:context].reason isEqualToString:@"the existing draft"]) {
            fputs("FAIL: Use conversation must remove the override and restore normal classification.\n", stderr);
            return 1;
        }
        [testDefaults removePersistentDomainForName:suiteName];
        puts("Settings layout smoke test passed.");
    }
    return 0;
}
