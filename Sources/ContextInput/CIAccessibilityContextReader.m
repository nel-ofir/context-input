#import "CIAccessibilityContextReader.h"
#import "CIApplicationCapabilities.h"
#import "CIContextTextSanitizer.h"
#import "CIDraftSanitizer.h"
#import <AppKit/AppKit.h>

@interface CIAccessibilityCandidate : NSObject
@property(nonatomic, copy) NSString *text;
@property(nonatomic) CGRect frame;
@property(nonatomic) CGFloat score;
@end

@implementation CIAccessibilityCandidate
@end

static id _Nullable CIAXAttribute(AXUIElementRef element, CFStringRef name) {
    CFTypeRef copied = NULL;
    AXError error = AXUIElementCopyAttributeValue(element, name, &copied);
    return error == kAXErrorSuccess && copied != NULL ? CFBridgingRelease(copied) : nil;
}

static NSString *_Nullable CIAXStringAttribute(AXUIElementRef element, CFStringRef name) {
    id value = CIAXAttribute(element, name);
    if ([value isKindOfClass:NSString.class]) {
        return value;
    }
    if ([value isKindOfClass:NSAttributedString.class]) {
        return ((NSAttributedString *)value).string;
    }
    return nil;
}

static NSString *_Nullable CIAXSearchableAttribute(AXUIElementRef element, CFStringRef name) {
    id value = CIAXAttribute(element, name);
    if ([value isKindOfClass:NSString.class]) {
        return value;
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        for (id item in value) {
            if ([item isKindOfClass:NSString.class]) {
                [parts addObject:item];
            }
        }
        return [parts componentsJoinedByString:@" "];
    }
    return nil;
}

static BOOL CIAXFrame(AXUIElementRef element, CGRect *result) {
    id positionObject = CIAXAttribute(element, kAXPositionAttribute);
    id sizeObject = CIAXAttribute(element, kAXSizeAttribute);
    if (positionObject == nil || sizeObject == nil) {
        return NO;
    }
    AXValueRef position = (__bridge AXValueRef)positionObject;
    AXValueRef size = (__bridge AXValueRef)sizeObject;
    if (CFGetTypeID(position) != AXValueGetTypeID() || CFGetTypeID(size) != AXValueGetTypeID()) {
        return NO;
    }

    CGPoint point = CGPointZero;
    CGSize dimensions = CGSizeZero;
    if (!AXValueGetValue(position, kAXValueCGPointType, &point) ||
        !AXValueGetValue(size, kAXValueCGSizeType, &dimensions)) {
        return NO;
    }
    *result = (CGRect){point, dimensions};
    return YES;
}

@interface CIAccessibilityContextReader ()
@property(nonatomic) AXUIElementRef systemWideElement;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *terminalCapabilityCache;
- (id)contextRootObjectForFocused:(AXUIElementRef)focused
                            window:(AXUIElementRef)window
                      focusedFrame:(CGRect)focusedFrame
                   hasFocusedFrame:(BOOL)hasFocusedFrame;
- (nullable AXUIElementRef)copyOpaqueTerminalElementForApplication:
    (NSRunningApplication *)application CF_RETURNS_RETAINED;
- (BOOL)applicationDeclaresTerminalSupport:(NSRunningApplication *)application;
- (BOOL)applicationForElementDeclaresTerminalSupport:(AXUIElementRef)element;
@end

@implementation CIAccessibilityContextReader

- (instancetype)init {
    self = [super init];
    if (self) {
        _systemWideElement = AXUIElementCreateSystemWide();
        _terminalCapabilityCache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    if (_systemWideElement != NULL) {
        CFRelease(_systemWideElement);
    }
}

+ (BOOL)isTrusted {
    return AXIsProcessTrusted();
}

+ (BOOL)requestTrustPrompt {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

+ (void)openAccessibilitySettings {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    if (url != nil) {
        [NSWorkspace.sharedWorkspace openURL:url];
    }
}

- (AXUIElementRef)copyFocusedEditableElement {
    NSRunningApplication *frontmostApplication = NSWorkspace.sharedWorkspace.frontmostApplication;
    CFTypeRef copied = NULL;
    AXError error = AXUIElementCopyAttributeValue(
        self.systemWideElement,
        kAXFocusedUIElementAttribute,
        &copied
    );
    if (error != kAXErrorSuccess || copied == NULL || CFGetTypeID(copied) != AXUIElementGetTypeID()) {
        if (copied != NULL) {
            CFRelease(copied);
        }
        return [self copyOpaqueTerminalElementForApplication:frontmostApplication];
    }

    AXUIElementRef focused = (AXUIElementRef)copied;
    pid_t focusedProcessIdentifier = 0;
    BOOL hasFocusedProcess = AXUIElementGetPid(focused, &focusedProcessIdentifier) == kAXErrorSuccess;
    if (frontmostApplication != nil &&
        (!hasFocusedProcess || focusedProcessIdentifier != frontmostApplication.processIdentifier)) {
        // Custom rendering frameworks may make their window frontmost without
        // publishing a new focused UI element. Never reuse the stale element
        // from the previous app; terminal-capable hosts can instead provide an
        // opaque window/application fallback.
        CFRelease(focused);
        return [self copyOpaqueTerminalElementForApplication:frontmostApplication];
    }

    NSString *role = CIAXStringAttribute(focused, kAXRoleAttribute);
    role = role != nil ? role : @"";
    NSNumber *enabled = CIAXAttribute(focused, kAXEnabledAttribute);
    NSString *subrole = CIAXStringAttribute(focused, kAXSubroleAttribute);
    subrole = subrole != nil ? subrole : @"";
    BOOL secure = [subrole isEqualToString:@"AXSecureTextField"];
    BOOL standardEditableRole = [@[@"AXTextField", @"AXTextArea", @"AXComboBox", @"AXSearchField"]
        containsObject:role];
    BOOL editableSubrole = [subrole localizedCaseInsensitiveContainsString:@"text"] ||
        [subrole localizedCaseInsensitiveContainsString:@"search"];
    BOOL terminalLike = [self isTerminalLikeElement:focused];
    Boolean valueSettable = false;
    AXError settableError = AXUIElementIsAttributeSettable(
        focused,
        kAXValueAttribute,
        &valueSettable
    );
    BOOL genericEditableContainer = settableError == kAXErrorSuccess && valueSettable &&
        [@[@"AXWebArea", @"AXGroup", @"AXUnknown"] containsObject:role];
    BOOL editable = standardEditableRole || editableSubrole || terminalLike || genericEditableContainer;
    if (!editable || (enabled != nil && !enabled.boolValue) || secure) {
        CFRelease(focused);
        return NULL;
    }
    return focused;
}

- (CIScreenContext *)readContextAroundElement:(AXUIElementRef)focused {
    pid_t processIdentifier = 0;
    if (AXUIElementGetPid(focused, &processIdentifier) != kAXErrorSuccess) {
        return nil;
    }

    NSRunningApplication *runningApplication = [NSRunningApplication runningApplicationWithProcessIdentifier:processIdentifier];
    NSString *applicationName = runningApplication.localizedName;
    applicationName = applicationName != nil ? applicationName : @"Unknown app";
    NSString *bundleIdentifier = runningApplication.bundleIdentifier;
    NSString *focusRole = CIAXStringAttribute(focused, kAXRoleAttribute);
    focusRole = focusRole != nil ? focusRole : @"Unknown role";
    NSString *focusSubrole = CIAXStringAttribute(focused, kAXSubroleAttribute);
    BOOL terminalLike = [self isTerminalLikeElement:focused];
    NSString *focusDescription = focusSubrole.length > 0
        ? [NSString stringWithFormat:@"%@ / %@%@", focusRole, focusSubrole, terminalLike ? @" / terminal" : @""]
        : [NSString stringWithFormat:@"%@%@", focusRole, terminalLike ? @" / terminal" : @""];
    AXUIElementRef applicationElement = AXUIElementCreateApplication(processIdentifier);
    AXUIElementSetMessagingTimeout(applicationElement, 0.25);

    id rootObject = CIAXAttribute(focused, kAXWindowAttribute);
    if (rootObject == nil) {
        rootObject = CIAXAttribute(applicationElement, kAXFocusedWindowAttribute);
    }
    CFRelease(applicationElement);

    NSString *accessibleValue = [self normalizedText:CIAXStringAttribute(focused, kAXValueAttribute)];
    NSString *placeholder = [self normalizedText:CIAXStringAttribute(focused, kAXPlaceholderValueAttribute)];
    if (placeholder.length == 0 && accessibleValue.length > 0) {
        for (NSString *attribute in @[
            (__bridge NSString *)kAXDescriptionAttribute,
            (__bridge NSString *)kAXHelpAttribute,
        ]) {
            NSString *candidate = [self normalizedText:CIAXStringAttribute(
                focused,
                (__bridge CFStringRef)attribute
            )];
            if (candidate.length > 0 &&
                [accessibleValue localizedCaseInsensitiveCompare:candidate] == NSOrderedSame) {
                placeholder = candidate;
                break;
            }
        }
    }
    NSNumber *numberOfCharacters = CIAXAttribute(focused, kAXNumberOfCharactersAttribute);
    if (![numberOfCharacters isKindOfClass:NSNumber.class]) {
        numberOfCharacters = nil;
    }
    NSString *draft = [CIDraftSanitizer
        draftFromAccessibilityValue:accessibleValue
                   placeholderValue:placeholder
                 numberOfCharacters:numberOfCharacters
                    applicationName:applicationName
                        elementRole:focusRole];
    if (accessibleValue.length > 0 && draft.length == 0 && placeholder.length == 0) {
        placeholder = accessibleValue;
    }
    if (rootObject == nil || CFGetTypeID((__bridge CFTypeRef)rootObject) != AXUIElementGetTypeID()) {
        return [[CIScreenContext alloc] initWithApplicationName:applicationName
                                             bundleIdentifier:bundleIdentifier
                                                         draft:draft
                                                   nearbyTexts:@[]
                                                  terminalLike:terminalLike
                                              focusDescription:focusDescription];
    }

    AXUIElementRef windowRoot = (__bridge AXUIElementRef)rootObject;
    CGRect focusedFrame = CGRectZero;
    BOOL hasFocusedFrame = CIAXFrame(focused, &focusedFrame) &&
        focusedFrame.size.width > 1 && focusedFrame.size.height > 1;
    id contextRootObject = [self contextRootObjectForFocused:focused
                                                      window:windowRoot
                                                focusedFrame:focusedFrame
                                             hasFocusedFrame:hasFocusedFrame];
    AXUIElementRef root = (__bridge AXUIElementRef)contextRootObject;
    NSMutableArray<CIAccessibilityCandidate *> *candidates = [NSMutableArray array];
    NSMutableSet<NSNumber *> *visited = [NSMutableSet set];
    // Web-based conversation views can be substantially deeper than native AppKit
    // hierarchies. Keep the scan bounded, but allow enough nodes to reach the most
    // recent messages near a composer.
    NSInteger remaining = 1800;
    [self walkElement:root
              focused:focused
         focusedFrame:focusedFrame
       hasFocusedFrame:hasFocusedFrame
                depth:0
            remaining:&remaining
               visited:visited
            candidates:candidates
          terminalLike:terminalLike
       applicationName:applicationName];

    [candidates sortUsingComparator:^NSComparisonResult(CIAccessibilityCandidate *left,
                                                          CIAccessibilityCandidate *right) {
        if (left.score < right.score) return NSOrderedAscending;
        if (left.score > right.score) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    NSMutableArray<NSString *> *nearbyTexts = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSString *containerDescription = [self normalizedText:CIAXStringAttribute(
        root,
        kAXDescriptionAttribute
    )];
    NSString *conversationTitle = [CIContextTextSanitizer
        conversationTitleFromContainerDescription:containerDescription
                                   applicationName:applicationName];
    if (conversationTitle.length > 0) {
        [nearbyTexts addObject:conversationTitle];
        [seen addObject:conversationTitle.lowercaseString];
    }
    for (CIAccessibilityCandidate *candidate in candidates) {
        if ([candidate.text isEqualToString:draft]) {
            continue;
        }
        if (placeholder.length > 0 &&
            [candidate.text localizedCaseInsensitiveCompare:placeholder] == NSOrderedSame) {
            continue;
        }
        NSString *key = candidate.text.lowercaseString;
        if ([seen containsObject:key]) {
            continue;
        }
        [seen addObject:key];
        [nearbyTexts addObject:candidate.text];
        if (nearbyTexts.count == 32) {
            break;
        }
    }

    return [[CIScreenContext alloc] initWithApplicationName:applicationName
                                         bundleIdentifier:bundleIdentifier
                                                     draft:draft
                                               nearbyTexts:nearbyTexts
                                              terminalLike:terminalLike
                                          focusDescription:focusDescription];
}

- (id)contextRootObjectForFocused:(AXUIElementRef)focused
                            window:(AXUIElementRef)window
                      focusedFrame:(CGRect)focusedFrame
                   hasFocusedFrame:(BOOL)hasFocusedFrame {
    if (!hasFocusedFrame) {
        return (__bridge id)window;
    }

    id currentObject = (__bridge id)focused;
    CGFloat maximumContextWidth = fmax(
        focusedFrame.size.width * 1.55,
        focusedFrame.size.width + 420.0
    );
    CGPoint focusedCenter = CGPointMake(CGRectGetMidX(focusedFrame), CGRectGetMidY(focusedFrame));

    for (NSInteger depth = 0; depth < 16; depth++) {
        AXUIElementRef current = (__bridge AXUIElementRef)currentObject;
        id parentObject = CIAXAttribute(current, kAXParentAttribute);
        if (parentObject == nil ||
            CFGetTypeID((__bridge CFTypeRef)parentObject) != AXUIElementGetTypeID()) {
            break;
        }

        AXUIElementRef parent = (__bridge AXUIElementRef)parentObject;
        if (CFEqual(parent, window)) {
            break;
        }
        CGRect parentFrame = CGRectZero;
        if (CIAXFrame(parent, &parentFrame)) {
            CGFloat contentAbove = CGRectGetMinY(focusedFrame) - CGRectGetMinY(parentFrame);
            BOOL containsFocus = CGRectContainsPoint(parentFrame, focusedCenter);
            BOOL containsComposerBottom = CGRectGetMaxY(parentFrame) >= CGRectGetMaxY(focusedFrame) - 20.0;
            BOOL paneSized = parentFrame.size.width <= maximumContextWidth;
            if (containsFocus && containsComposerBottom && paneSized && contentAbove >= 260.0) {
                return parentObject;
            }
        }
        currentObject = parentObject;
    }
    return (__bridge id)window;
}

- (void)walkElement:(AXUIElementRef)element
             focused:(AXUIElementRef)focused
        focusedFrame:(CGRect)focusedFrame
      hasFocusedFrame:(BOOL)hasFocusedFrame
               depth:(NSInteger)depth
           remaining:(NSInteger *)remaining
              visited:(NSMutableSet<NSNumber *> *)visited
           candidates:(NSMutableArray<CIAccessibilityCandidate *> *)candidates
         terminalLike:(BOOL)terminalLike
      applicationName:(NSString *)applicationName {
    if (*remaining <= 0 || depth > 24 || CFEqual(element, focused)) {
        return;
    }
    *remaining -= 1;

    NSNumber *elementHash = @(CFHash(element));
    if ([visited containsObject:elementHash]) {
        return;
    }
    [visited addObject:elementHash];

    NSString *role = CIAXStringAttribute(element, kAXRoleAttribute);
    role = role != nil ? role : @"";
    BOOL standardTextRole = [@[
        @"AXStaticText",
        @"AXLink",
        @"AXHeading",
        @"AXCell",
        @"AXParagraph",
        @"AXListItem",
        @"AXRow",
        @"AXGroup",
        @"AXText",
        @"AXDocument",
    ]
        containsObject:role];
    BOOL terminalTextRole = terminalLike && [@[@"AXOutlineRow"] containsObject:role];
    if (standardTextRole || terminalTextRole) {
        NSString *elementIdentifier = CIAXStringAttribute(element, kAXIdentifierAttribute);
        CGRect elementFrame = CGRectZero;
        if (CIAXFrame(element, &elementFrame)) {
            NSNumber *score = [self proximityScoreForCandidate:elementFrame
                                                       focused:focusedFrame
                                               hasFocusedFrame:hasFocusedFrame];
            if (score != nil) {
                for (NSString *text in [self textValuesFromElement:element]) {
                    NSString *normalized = [self normalizedText:text];
                    normalized = [CIContextTextSanitizer
                        textFromAccessibilityText:normalized
                                elementIdentifier:elementIdentifier
                                  applicationName:applicationName];
                    if (normalized.length == 0) {
                        continue;
                    }
                    if (normalized.length > 2000) {
                        normalized = [normalized substringFromIndex:normalized.length - 2000];
                    }
                    CIAccessibilityCandidate *candidate = [[CIAccessibilityCandidate alloc] init];
                    candidate.text = normalized;
                    candidate.frame = elementFrame;
                    candidate.score = score.doubleValue;
                    [candidates addObject:candidate];
                }
            }
        }
    }

    // Accessibility children are normally in visual/document order. Walking in
    // reverse reaches the bottom of a long chat (the newest messages) before the
    // traversal budget is consumed by older content and page chrome.
    for (id childObject in [[self childrenOfElement:element] reverseObjectEnumerator]) {
        if (CFGetTypeID((__bridge CFTypeRef)childObject) != AXUIElementGetTypeID()) {
            continue;
        }
        [self walkElement:(__bridge AXUIElementRef)childObject
                  focused:focused
             focusedFrame:focusedFrame
           hasFocusedFrame:hasFocusedFrame
                    depth:depth + 1
                remaining:remaining
                   visited:visited
                candidates:candidates
              terminalLike:terminalLike
           applicationName:applicationName];
        if (*remaining <= 0) {
            break;
        }
    }
}

- (BOOL)isTerminalLikeElement:(AXUIElementRef)element {
    id currentObject = (__bridge id)element;
    NSArray<NSString *> *keywords = @[@"terminal", @"xterm", @"command line", @"console"];
    NSArray<NSString *> *attributeNames = @[
        (__bridge NSString *)kAXRoleAttribute,
        (__bridge NSString *)kAXSubroleAttribute,
        (__bridge NSString *)kAXRoleDescriptionAttribute,
        (__bridge NSString *)kAXTitleAttribute,
        (__bridge NSString *)kAXDescriptionAttribute,
        (__bridge NSString *)kAXHelpAttribute,
        (__bridge NSString *)kAXIdentifierAttribute,
        @"AXDOMIdentifier",
        @"AXDOMClassList",
    ];

    for (NSInteger depth = 0; depth < 9 && currentObject != nil; depth++) {
        AXUIElementRef current = (__bridge AXUIElementRef)currentObject;
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        for (NSString *attributeName in attributeNames) {
            NSString *value = CIAXSearchableAttribute(current, (__bridge CFStringRef)attributeName);
            if (value.length > 0) {
                [parts addObject:value];
            }
        }
        NSString *searchable = [parts componentsJoinedByString:@" "].lowercaseString;
        for (NSString *keyword in keywords) {
            if ([searchable containsString:keyword]) {
                return YES;
            }
        }

        id parentObject = CIAXAttribute(current, kAXParentAttribute);
        if (parentObject == nil ||
            CFGetTypeID((__bridge CFTypeRef)parentObject) != AXUIElementGetTypeID()) {
            break;
        }
        currentObject = parentObject;
    }

    // Some GPU-rendered apps intentionally expose only an opaque focused
    // container, so there is no text role or terminal keyword to inspect. Use
    // the bundle's declared document capabilities as a generic fallback. This
    // is limited to opaque roles, ensuring native search fields and other
    // controls inside the same app continue through the normal text path.
    NSString *role = CIAXStringAttribute(element, kAXRoleAttribute);
    return [CIApplicationCapabilities isOpaqueAccessibilityRole:role] &&
        [self applicationForElementDeclaresTerminalSupport:element];
}

- (BOOL)applicationForElementDeclaresTerminalSupport:(AXUIElementRef)element {
    pid_t processIdentifier = 0;
    if (AXUIElementGetPid(element, &processIdentifier) != kAXErrorSuccess) {
        return NO;
    }
    NSRunningApplication *application =
        [NSRunningApplication runningApplicationWithProcessIdentifier:processIdentifier];
    return application != nil && [self applicationDeclaresTerminalSupport:application];
}

- (BOOL)applicationDeclaresTerminalSupport:(NSRunningApplication *)application {

    NSString *cacheKey = application.bundleIdentifier;
    if (cacheKey.length == 0) {
        cacheKey = application.bundleURL.path;
    }
    NSNumber *cached = cacheKey.length > 0 ? self.terminalCapabilityCache[cacheKey] : nil;
    if (cached != nil) {
        return cached.boolValue;
    }

    BOOL declaresTerminalSupport =
        [CIApplicationCapabilities applicationDeclaresTerminalSupport:application];
    if (cacheKey.length > 0) {
        self.terminalCapabilityCache[cacheKey] = @(declaresTerminalSupport);
    }
    return declaresTerminalSupport;
}

- (AXUIElementRef)copyOpaqueTerminalElementForApplication:(NSRunningApplication *)application {
    if (application == nil || ![self applicationDeclaresTerminalSupport:application]) {
        return NULL;
    }

    AXUIElementRef applicationElement = AXUIElementCreateApplication(application.processIdentifier);
    AXUIElementSetMessagingTimeout(applicationElement, 0.25);
    id windowObject = CIAXAttribute(applicationElement, kAXFocusedWindowAttribute);
    if (windowObject != nil &&
        CFGetTypeID((__bridge CFTypeRef)windowObject) == AXUIElementGetTypeID()) {
        AXUIElementRef window = (__bridge AXUIElementRef)windowObject;
        NSString *windowRole = CIAXStringAttribute(window, kAXRoleAttribute);
        if ([CIApplicationCapabilities isOpaqueAccessibilityRole:windowRole]) {
            CFRetain(window);
            CFRelease(applicationElement);
            return window;
        }
    }

    NSString *applicationRole = CIAXStringAttribute(applicationElement, kAXRoleAttribute);
    if ([CIApplicationCapabilities isOpaqueAccessibilityRole:applicationRole]) {
        return applicationElement;
    }
    CFRelease(applicationElement);
    return NULL;
}

- (NSArray<NSString *> *)textValuesFromElement:(AXUIElementRef)element {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (id attributeName in @[
        (__bridge NSString *)kAXValueAttribute,
        (__bridge NSString *)kAXTitleAttribute,
        (__bridge NSString *)kAXDescriptionAttribute
    ]) {
        id value = CIAXAttribute(element, (__bridge CFStringRef)attributeName);
        if ([value isKindOfClass:NSString.class]) {
            [values addObject:value];
        } else if ([value isKindOfClass:NSAttributedString.class]) {
            [values addObject:((NSAttributedString *)value).string];
        }
    }
    return values;
}

- (NSArray *)childrenOfElement:(AXUIElementRef)element {
    id visible = CIAXAttribute(element, kAXVisibleChildrenAttribute);
    if ([visible isKindOfClass:NSArray.class] && [visible count] > 0) {
        return visible;
    }
    id children = CIAXAttribute(element, kAXChildrenAttribute);
    return [children isKindOfClass:NSArray.class] ? children : @[];
}

- (NSNumber *)proximityScoreForCandidate:(CGRect)candidate
                                  focused:(CGRect)focused
                          hasFocusedFrame:(BOOL)hasFocusedFrame {
    if (candidate.size.width <= 0 || candidate.size.height <= 0) {
        return nil;
    }
    if (!hasFocusedFrame) {
        return @(10000.0 - CGRectGetMaxY(candidate));
    }

    // Accessibility coordinates start at the top-left of the primary display.
    CGFloat verticalGap = CGRectGetMinY(focused) - CGRectGetMaxY(candidate);
    if (verticalGap < -8 || verticalGap > 1600) {
        return nil;
    }

    CGFloat horizontalOverlap = fmin(CGRectGetMaxX(candidate), CGRectGetMaxX(focused)) -
        fmax(CGRectGetMinX(candidate), CGRectGetMinX(focused));
    if (horizontalOverlap <= 0) {
        return nil;
    }
    CGFloat nonnegativeGap = verticalGap > 0 ? verticalGap : 0;
    CGFloat centerDistance = fabs(CGRectGetMidX(candidate) - CGRectGetMidX(focused));
    return @(nonnegativeGap + (centerDistance * 0.08));
}

- (NSString *)normalizedText:(NSString *)text {
    if (text.length == 0) {
        return nil;
    }
    NSString *collapsed = [text stringByReplacingOccurrencesOfString:@"\\s+"
                                                           withString:@" "
                                                              options:NSRegularExpressionSearch
                                                                range:NSMakeRange(0, text.length)];
    NSString *trimmed = [collapsed stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length > 0 ? trimmed : nil;
}

@end
