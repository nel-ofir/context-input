#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import "CILanguageClassifier.h"

// Synthetic AX trees only. No other application's UI is inspected by these tests.
// Real AX element handles provide Core Foundation identity/lifetime semantics;
// all attribute reads are routed to the in-memory fixture below.
static NSMapTable *attributes;
static int nextNode = 200000;
static AXError FixtureCopyAttribute(AXUIElementRef element, CFStringRef name, CFTypeRef *out) {
    id value = [[attributes objectForKey:(__bridge id)element] objectForKey:(__bridge NSString *)name];
    *out = value ? CFRetain((__bridge CFTypeRef)value) : NULL;
    return value ? kAXErrorSuccess : kAXErrorAttributeUnsupported;
}
static AXError FixtureGetPid(AXUIElementRef element, pid_t *pid) {
    (void)element;
    *pid = NSProcessInfo.processInfo.processIdentifier;
    return kAXErrorSuccess;
}
static AXError FixtureTimeout(AXUIElementRef element, float seconds) {
    (void)element;
    (void)seconds;
    return kAXErrorSuccess;
}
#define AXUIElementCopyAttributeValue FixtureCopyAttribute
#define AXUIElementGetPid FixtureGetPid
#define AXUIElementSetMessagingTimeout FixtureTimeout
#pragma clang diagnostic push
// Including an implementation makes Clang apply header-only completeness checks.
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "CIAccessibilityContextReader.m"
#pragma clang diagnostic pop
#undef AXUIElementCopyAttributeValue
#undef AXUIElementGetPid
#undef AXUIElementSetMessagingTimeout

static id Node(NSString *role, CGRect frame, NSString *text) {
    id node = CFBridgingRelease(AXUIElementCreateApplication(nextNode++));
    CGPoint position = frame.origin;
    CGSize size = frame.size;
    NSMutableDictionary *values = [@{
        @"AXRole": role,
        @"AXPosition": CFBridgingRelease(AXValueCreate(kAXValueCGPointType, &position)),
        @"AXSize": CFBridgingRelease(AXValueCreate(kAXValueCGSizeType, &size)),
        @"AXChildren": @[],
    } mutableCopy];
    if (text) values[@"AXValue"] = text;
    [attributes setObject:values forKey:node];
    return node;
}
static void Children(id parent, NSArray *children) {
    [attributes objectForKey:parent][@"AXChildren"] = children;
    for (id child in children) [attributes objectForKey:child][@"AXParent"] = parent;
}
static NSInteger failures;
static void Expect(BOOL result, NSString *message) {
    if (!result) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); }
}

static void TestComposerContainer(BOOL separateContainer, NSString *body, CIInputLanguage expected,
                                 BOOL crowdedWindow, BOOL incompleteVisibleChildren) {
    attributes = [NSMapTable strongToStrongObjectsMapTable];
    id window = Node(@"AXWindow", CGRectMake(0, 0, 1400, 1000), nil);
    id pane = Node(@"AXGroup", CGRectMake(250, 80, 800, 900), nil);
    id composer = Node(@"AXGroup", CGRectMake(250, 580, 800, 400), nil);
    id focus = Node(@"AXTextArea", CGRectMake(300, 870, 700, 80), @"");
    id message = Node(@"AXStaticText", CGRectMake(300, 720, 650, 70), body);
    if (crowdedWindow) {
        id sidebar = Node(@"AXGroup", CGRectMake(0, 80, 240, 900), nil);
        id document = Node(@"AXGroup", CGRectMake(1060, 80, 340, 900), nil);
        NSMutableArray *irrelevant = [NSMutableArray array];
        for (NSInteger index = 0; index < 1900; index++) {
            [irrelevant addObject:Node(@"AXStaticText", CGRectMake(1070, 100, 300, 40),
                expected == CIInputLanguageHebrew ? @"English document and unrelated thread" : @"מסמך בעברית בשיחה אחרת")];
        }
        Children(document, irrelevant);
        Children(sidebar, @[Node(@"AXStaticText", CGRectMake(10, 780, 220, 40), @"Unrelated English session")]);
        // No intermediate pane ancestor: fallback must scan the window, and
        // reverse traversal encounters the large document before the messages.
        Children(window, @[sidebar, message, composer, document]);
        Children(composer, @[focus]);
    } else {
        Children(window, @[pane]);
    }
    if (crowdedWindow) {
        // The message and composer are already direct window children.
    } else if (separateContainer) {
        Children(pane, @[message, composer]);
        Children(composer, @[focus]);
    } else {
        Children(pane, @[message, focus]);
    }
    [attributes objectForKey:focus][@"AXWindow"] = window;
    if (incompleteVisibleChildren) {
        // Some renderers expose the composer in VisibleChildren but keep the
        // message list only in Children. Exercise both pane and window roots.
        if (crowdedWindow) [attributes objectForKey:window][@"AXVisibleChildren"] = @[composer];
        else [attributes objectForKey:pane][@"AXVisibleChildren"] = separateContainer ? @[composer] : @[focus];
    }
    CIAccessibilityContextReader *reader = [[CIAccessibilityContextReader alloc] init];
    CIScreenContext *context = [reader readContextAroundElement:(__bridge AXUIElementRef)focus];
    CILanguageDecision *decision = [[[CILanguageClassifier alloc] init]
        classifyDraft:context.draft nearbyTexts:context.nearbyTexts];
    fprintf(stdout, "%s %s: %lu context items\n", separateContainer ? "nested" : "flat",
        expected == CIInputLanguageHebrew ? "Hebrew" : "English", (unsigned long)context.nearbyTexts.count);
    Expect(decision != nil && decision.language == expected,
        [NSString stringWithFormat:@"%@ composer container must find the %@ message",
            separateContainer ? @"nested" : @"flat", CIInputLanguageDisplayName(expected)]);
    Expect(context.nearbyTexts.count == 1, @"only the active conversation body should be collected");
    if (separateContainer || incompleteVisibleChildren) {
        Expect([context.focusDescription containsString:@"context fallback:"],
            @"diagnostics should identify use of the fallback");
    }
}

static void TestNoConversation(BOOL withDraft) {
    attributes = [NSMapTable strongToStrongObjectsMapTable];
    id window = Node(@"AXWindow", CGRectMake(0, 0, 1500, 1100), nil);
    id composer = Node(@"AXGroup", CGRectMake(300, 580, 700, 400), nil);
    id focus = Node(@"AXTextArea", CGRectMake(300, 870, 700, 80), withDraft ? @"Hello, please review my draft." : @"");
    id sidebar = Node(@"AXStaticText", CGRectMake(0, 720, 240, 70), @"הודעה בעברית בשיחה אחרת");
    id panel = Node(@"AXStaticText", CGRectMake(1100, 720, 300, 70), @"מסמך בעברית בצד החלון");
    id below = Node(@"AXStaticText", CGRectMake(300, 990, 600, 70), @"טקסט מתחת לשדה ההקלדה");
    Children(window, @[sidebar, composer, panel, below]);
    Children(composer, @[focus]);
    [attributes objectForKey:focus][@"AXWindow"] = window;
    CIScreenContext *context = [[[CIAccessibilityContextReader alloc] init]
        readContextAroundElement:(__bridge AXUIElementRef)focus];
    CILanguageDecision *decision = [[[CILanguageClassifier alloc] init]
        classifyDraft:context.draft nearbyTexts:context.nearbyTexts];
    Expect(context.nearbyTexts.count == 0, @"fallback must not use other columns or text below the composer");
    Expect(withDraft ? (decision != nil && decision.language == CIInputLanguageEnglish) : decision == nil,
        @"empty conversations abstain; existing drafts retain priority");
}
int main(void) {
    @autoreleasepool {
        for (NSNumber *incomplete in @[@NO, @YES]) {
            TestComposerContainer(NO, @"לא נמצאו מיילים רלוונטיים היום. יומן הריצות עודכן.", CIInputLanguageHebrew, NO, incomplete.boolValue);
            TestComposerContainer(YES, @"לא נמצאו מיילים רלוונטיים היום. יומן הריצות עודכן.", CIInputLanguageHebrew, NO, incomplete.boolValue);
            TestComposerContainer(YES, @"The report is ready. Please review the latest changes.", CIInputLanguageEnglish, NO, incomplete.boolValue);
            TestComposerContainer(YES, @"המסמך מוכן לבדיקה, תודה רבה על העזרה.", CIInputLanguageHebrew, YES, incomplete.boolValue);
            TestComposerContainer(YES, @"The document is ready for review. Thank you for your help.", CIInputLanguageEnglish, YES, incomplete.boolValue);
        }
        TestNoConversation(NO);
        TestNoConversation(YES);
        if (failures) return 1;
        puts("Context reader layout tests passed.");
    }
    return 0;
}
