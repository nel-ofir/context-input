#import "CIAppController.h"
#import "CIAccessibilityContextReader.h"
#import "CIInputSourceManager.h"
#import "CILanguageClassifier.h"
#import "CISwitchVerificationPolicy.h"
#import <ServiceManagement/ServiceManagement.h>
#import <Sparkle/Sparkle.h>
#import <math.h>

static NSString *const CIEnabledDefaultsKey = @"enabled";
static NSString *const CIEnglishSourceDefaultsKey = @"englishSourceID";
static NSString *const CIHebrewSourceDefaultsKey = @"hebrewSourceID";

@interface CISettingsContentView : NSView
@end
@implementation CISettingsContentView
- (BOOL)isFlipped { return YES; }
@end

@interface CIAppController ()
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL accessibilityGranted;
@property(nonatomic, copy) NSString *englishSourceIdentifier;
@property(nonatomic, copy) NSString *hebrewSourceIdentifier;
@property(nonatomic, copy) NSArray<CIKeyboardInputSource *> *inputSources;
@property(nonatomic, copy) NSString *statusMessage;
@property(nonatomic, copy) NSString *lastApplication;
@property(nonatomic, copy) NSString *lastFocusDescription;
@property(nonatomic, copy) NSString *lastContext;
@property(nonatomic, copy) NSString *lastDecision;
@property(nonatomic, copy) NSString *lastReason;
@property(nonatomic, copy) NSString *lastContextSamples;
@property(nonatomic, copy) NSString *activeInputSourceName;
@property(nonatomic, copy) NSString *lastSwitchSummary;
@property(nonatomic) double lastConfidence;
@property(nonatomic) NSUInteger lastContextItemCount;

@property(nonatomic, assign) AXUIElementRef lastFocusedElement;
@property(nonatomic) NSInteger focusGeneration;
@property(nonatomic) NSInteger permissionCheckCounter;
@property(nonatomic, strong) NSTimer *pollTimer;
@property(nonatomic, strong) id globalMouseMonitor;
@property(nonatomic, strong) id globalKeyMonitor;
@property(nonatomic) NSInteger inputInteractionGeneration;
@property(nonatomic) NSInteger switchSequence;
@property(nonatomic, strong) CIInputSourceManager *inputSourceManager;
@property(nonatomic, strong) CIAccessibilityContextReader *contextReader;
@property(nonatomic, strong) CILanguageClassifier *classifier;
@property(nonatomic, strong) SPUStandardUpdaterController *updaterController;

@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSWindow *settingsWindow;
@property(nonatomic, strong) NSButton *enabledCheckbox;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSTextField *permissionLabel;
@property(nonatomic, strong) NSButton *permissionButton;
@property(nonatomic, strong) NSPopUpButton *englishPopup;
@property(nonatomic, strong) NSPopUpButton *hebrewPopup;
@property(nonatomic, strong) NSButton *launchAtLoginCheckbox;
@property(nonatomic, strong) NSTextField *activeSourceLabel;
@property(nonatomic, strong) NSTextField *applicationLabel;
@property(nonatomic, strong) NSTextField *focusLabel;
@property(nonatomic, strong) NSTextField *decisionLabel;
@property(nonatomic, strong) NSTextField *reasonLabel;
@property(nonatomic, strong) NSTextField *samplesLabel;
@property(nonatomic, strong) NSTextField *contextLabel;
@property(nonatomic, strong) NSTextField *switchLabel;
@end

@implementation CIAppController

- (instancetype)init {
    self = [super init];
    if (self) {
        _inputSourceManager = [[CIInputSourceManager alloc] init];
        _contextReader = [[CIAccessibilityContextReader alloc] init];
        _classifier = [[CILanguageClassifier alloc] init];

        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        _enabled = [defaults objectForKey:CIEnabledDefaultsKey] == nil
            ? YES
            : [defaults boolForKey:CIEnabledDefaultsKey];
        _englishSourceIdentifier = [defaults stringForKey:CIEnglishSourceDefaultsKey];
        _englishSourceIdentifier = _englishSourceIdentifier != nil ? _englishSourceIdentifier : @"";
        _hebrewSourceIdentifier = [defaults stringForKey:CIHebrewSourceDefaultsKey];
        _hebrewSourceIdentifier = _hebrewSourceIdentifier != nil ? _hebrewSourceIdentifier : @"";
        _statusMessage = @"Starting…";
        _lastApplication = @"—";
        _lastFocusDescription = @"—";
        _lastContext = @"Focus a text box to begin";
        _lastDecision = @"—";
        _lastReason = @"—";
        _lastContextSamples = @"—";
        _activeInputSourceName = @"Unknown";
        _lastSwitchSummary = @"No switch evaluated yet";
        [self refreshInputSources];
    }
    return self;
}

- (void)dealloc {
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [_pollTimer invalidate];
    if (_globalMouseMonitor != nil) {
        [NSEvent removeMonitor:_globalMouseMonitor];
    }
    if (_globalKeyMonitor != nil) {
        [NSEvent removeMonitor:_globalKeyMonitor];
    }
    if (_lastFocusedElement != NULL) {
        CFRelease(_lastFocusedElement);
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    self.updaterController = [[SPUStandardUpdaterController alloc]
        initWithStartingUpdater:YES updaterDelegate:nil userDriverDelegate:nil];
    [self configureApplicationMenu];
    [self configureStatusItem];

    self.accessibilityGranted = [CIAccessibilityContextReader requestTrustPrompt];
    [self updateMonitorStatus];
    [self startPolling];
    [self startMouseMonitoring];
    [self startInputMonitoring];
    [NSWorkspace.sharedWorkspace.notificationCenter
        addObserver:self selector:@selector(frontmostApplicationChanged:)
        name:NSWorkspaceDidActivateApplicationNotification object:nil];

    if (!self.accessibilityGranted) {
        [self showSettings:nil];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self.pollTimer invalidate];
    self.pollTimer = nil;
    if (self.globalMouseMonitor != nil) {
        [NSEvent removeMonitor:self.globalMouseMonitor];
        self.globalMouseMonitor = nil;
    }
    if (self.globalKeyMonitor != nil) {
        [NSEvent removeMonitor:self.globalKeyMonitor];
        self.globalKeyMonitor = nil;
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

#pragma mark - Focus monitoring

- (void)frontmostApplicationChanged:(NSNotification *)notification {
    (void)notification;
    // Window-level AX identities may survive leaving and returning to an app.
    [self clearLastFocus];
    [self pollFocusedElement:nil];
}

- (void)startInputMonitoring {
    if (!self.accessibilityGranted || self.globalKeyMonitor != nil) {
        return;
    }
    CIAppController *__weak weakSelf = self;
    self.globalKeyMonitor = [NSEvent
        addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskFlagsChanged
        handler:^(NSEvent *event) {
            // Never inspect or store key characters/codes. Any keyboard activity,
            // including modifiers used for manual language switching, cancels retries.
            (void)event;
            weakSelf.inputInteractionGeneration += 1;
        }];
}

- (void)startMouseMonitoring {
    if (self.globalMouseMonitor != nil) {
        return;
    }
    CIAppController *__weak weakSelf = self;
    self.globalMouseMonitor = [NSEvent
        addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown
                                     handler:^(NSEvent *event) {
        (void)event;
        // A single-page app may reuse the exact same textarea when its selected
        // conversation changes. The identity-only poll cannot see that transition,
        // so every external click gets one bounded, debounced focus reevaluation.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            CIAppController *strongSelf = weakSelf;
            if (strongSelf == nil || !strongSelf.enabled || !strongSelf.accessibilityGranted) {
                return;
            }
            [strongSelf clearLastFocus];
            [strongSelf pollFocusedElement:nil];
        });
    }];
}

- (void)startPolling {
    [self.pollTimer invalidate];
    self.pollTimer = [NSTimer timerWithTimeInterval:0.25
                                             target:self
                                           selector:@selector(pollFocusedElement:)
                                           userInfo:nil
                                            repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.pollTimer forMode:NSRunLoopCommonModes];
    [self pollFocusedElement:nil];
}

- (void)pollFocusedElement:(NSTimer *)timer {
    self.permissionCheckCounter = (self.permissionCheckCounter + 1) % 4;
    if (self.permissionCheckCounter == 0 || !self.accessibilityGranted) {
        BOOL trusted = [CIAccessibilityContextReader isTrusted];
        if (trusted != self.accessibilityGranted) {
            self.accessibilityGranted = trusted;
            if (trusted) {
                [self clearLastFocus];
                [self startInputMonitoring];
            }
            [self updateMonitorStatus];
        }
    }

    if (!self.enabled || !self.accessibilityGranted) {
        return;
    }

    AXUIElementRef focused = [self.contextReader copyFocusedEditableElement];
    if (focused == NULL) {
        [self clearLastFocus];
        return;
    }

    if (self.lastFocusedElement != NULL && CFEqual(self.lastFocusedElement, focused)) {
        CFRelease(focused);
        return;
    }

    [self clearLastFocus];
    self.lastFocusedElement = focused;
    self.focusGeneration += 1;
    NSInteger generation = self.focusGeneration;
    CFRetain(focused);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.14 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation == self.focusGeneration &&
            self.lastFocusedElement != NULL &&
            CFEqual(self.lastFocusedElement, focused)) {
            [self evaluateFocusedElement:focused];
        }
        CFRelease(focused);
    });
}

- (void)evaluateFocusedElement:(AXUIElementRef)focused {
    if (!self.enabled || !self.accessibilityGranted) {
        return;
    }

    AXUIElementRef current = [self.contextReader copyFocusedEditableElement];
    BOOL stillFocused = current != NULL && CFEqual(current, focused);
    if (current != NULL) {
        CFRelease(current);
    }
    if (!stillFocused) {
        return;
    }

    CIScreenContext *context = [self.contextReader readContextAroundElement:focused];
    if (context == nil || [context.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier]) {
        return;
    }
    self.switchSequence += 1;

    CILanguageDecision *decision = [self.classifier classifyDraft:context.draft
                                                      nearbyTexts:context.nearbyTexts];
    if (decision == nil && context.terminalLike) {
        decision = [[CILanguageDecision alloc]
            initWithLanguage:CIInputLanguageEnglish
                  confidence:1.0
                    evidence:@"Terminal input defaults to English when no stronger text is available"
                      reason:@"the focused terminal"];
    }
    self.lastApplication = context.applicationName;
    self.lastFocusDescription = context.focusDescription;
    self.lastContextItemCount = context.nearbyTexts.count;
    NSUInteger sampleCount = context.nearbyTexts.count < 3 ? context.nearbyTexts.count : 3;
    self.lastContextSamples = sampleCount > 0
        ? [[context.nearbyTexts subarrayWithRange:NSMakeRange(0, sampleCount)]
            componentsJoinedByString:@" • "]
        : @"—";
    NSString *evidence = decision.evidence;
    evidence = evidence != nil ? evidence : context.nearbyTexts.firstObject;
    self.lastContext = evidence != nil ? evidence : @"No usable nearby text found";

    if (decision == nil) {
        self.lastSwitchSummary = @"No keyboard switch requested: insufficient context";
        self.lastDecision = @"No change";
        self.lastReason = @"No confident Hebrew or English context";
        self.lastConfidence = 0;
        [self updateInterface];
        return;
    }

    self.lastDecision = CIInputLanguageDisplayName(decision.language);
    self.lastReason = decision.reason;
    self.lastConfidence = decision.confidence;
    NSString *sourceIdentifier = decision.language == CIInputLanguageHebrew
        ? self.hebrewSourceIdentifier
        : self.englishSourceIdentifier;
    if (sourceIdentifier.length == 0) {
        self.lastSwitchSummary = @"No keyboard switch requested: target source is missing";
        self.statusMessage = [NSString stringWithFormat:@"Add a %@ input source in System Settings",
                              CIInputLanguageDisplayName(decision.language)];
        [self updateInterface];
        return;
    }

    CIKeyboardInputSource *before = [self.inputSourceManager currentSource];
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:NSDate.date
        dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
    self.lastSwitchSummary = [NSString stringWithFormat:@"%@ • Before: %@ → target: %@",
        timestamp, before.name != nil ? before.name : @"Unknown", sourceIdentifier];
    if ([before.identifier isEqualToString:sourceIdentifier]) {
        self.statusMessage = @"Watching focused text fields";
        NSString *currentName = [self.inputSourceManager currentSource].name;
        self.activeInputSourceName = currentName != nil ? currentName : @"Unknown";
        self.lastSwitchSummary = [self.lastSwitchSummary stringByAppendingString:@" • Already reported selected"];
        [self verifySourceIdentifier:sourceIdentifier focused:focused];
        [self updateInterface];
        return;
    }

    NSError *error = nil;
    if (![self.inputSourceManager selectSourceIdentifier:sourceIdentifier error:&error]) {
        self.statusMessage = error.localizedDescription != nil
            ? error.localizedDescription
            : @"Could not change the input source";
        self.lastSwitchSummary = [self.lastSwitchSummary stringByAppendingFormat:
            @" • Selection failed: %@", self.statusMessage];
    } else {
        self.statusMessage = @"Watching focused text fields";
        NSString *currentName = [self.inputSourceManager currentSource].name;
        self.activeInputSourceName = currentName != nil
            ? currentName
            : CIInputLanguageDisplayName(decision.language);
        self.lastSwitchSummary = [self.lastSwitchSummary stringByAppendingFormat:
            @" • Request accepted; immediate: %@", self.activeInputSourceName];
    }
    [self verifySourceIdentifier:sourceIdentifier focused:focused];
    [self updateInterface];
}

- (void)verifySourceIdentifier:(NSString *)identifier
                      focused:(AXUIElementRef)focused {
    NSInteger generation = self.focusGeneration;
    NSInteger sequence = self.switchSequence;
    NSInteger inputGeneration = self.inputInteractionGeneration;
    pid_t pid = 0;
    AXUIElementGetPid(focused, &pid);
    __block BOOL stopped = NO;
    __block NSString *history = self.lastSwitchSummary;
    for (NSNumber *delay in @[@0.25, @0.65]) {
        BOOL finalCheck = delay.doubleValue > 0.5;
        CFRetain(focused);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (stopped || sequence != self.switchSequence) {
                CFRelease(focused);
                return;
            }
            BOOL sameFocus = self.enabled && self.accessibilityGranted &&
                generation == self.focusGeneration &&
                NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier == pid;
            if (sameFocus) {
                AXUIElementRef currentFocus = [self.contextReader copyFocusedEditableElement];
                sameFocus = currentFocus != NULL && CFEqual(currentFocus, focused);
                if (currentFocus != NULL) CFRelease(currentFocus);
            }
            CIKeyboardInputSource *observed = [self.inputSourceManager currentSource];
            // If the cancellation monitor could not be installed, do not risk
            // reasserting a keyboard after the user starts typing.
            BOOL interacted = inputGeneration != self.inputInteractionGeneration ||
                self.globalKeyMonitor == nil;
            CISwitchVerificationAction action = [CISwitchVerificationPolicy
                actionWithTargetMatches:[observed.identifier isEqualToString:identifier]
                finalCheck:finalCheck
                focusIsCurrent:sameFocus userInteracted:interacted];
            if (action == CISwitchVerificationCancel) {
                history = [history stringByAppendingFormat:@" • Verification stopped (%@)",
                    !sameFocus ? @"focus changed" : @"keyboard activity or unavailable activity monitor"];
                stopped = YES;
            } else {
                history = [history stringByAppendingFormat:@" • +%ld ms: %@",
                    (long)lround(delay.doubleValue * 1000), observed.name != nil ? observed.name : @"Unknown"];
                self.activeInputSourceName = observed.name != nil ? observed.name : @"Unknown";
                if (action == CISwitchVerificationRetry) {
                    NSError *error = nil;
                    BOOL accepted = [self.inputSourceManager selectSourceIdentifier:identifier error:&error];
                    history = [history stringByAppendingFormat:@"; one reapply %@",
                        accepted ? @"accepted" : (error.localizedDescription != nil ? error.localizedDescription : @"failed")];
                } else if (action == CISwitchVerificationVerified) {
                    history = [history stringByAppendingString:@" • macOS reports target source; typing not verified"];
                    self.statusMessage = @"Watching focused text fields";
                    stopped = YES;
                } else if (action == CISwitchVerificationFailed) {
                    history = [history stringByAppendingString:@" • Target source did not remain selected"];
                    self.statusMessage = @"Keyboard switch did not hold — see Last switch";
                    stopped = YES;
                }
            }
            // Opening Settings refreshes the live source but never overwrites this history.
            self.lastSwitchSummary = history;
            [self updateInterface];
            CFRelease(focused);
        });
    }
}

- (void)clearLastFocus {
    self.focusGeneration += 1;
    if (self.lastFocusedElement != NULL) {
        CFRelease(self.lastFocusedElement);
        self.lastFocusedElement = NULL;
    }
}

- (void)updateMonitorStatus {
    if (!self.enabled) {
        self.statusMessage = @"Paused";
    } else if (!self.accessibilityGranted) {
        self.statusMessage = @"Accessibility permission is required";
    } else {
        self.statusMessage = @"Watching focused text fields";
    }
    [self updateInterface];
}

#pragma mark - Input sources and startup

- (void)refreshInputSources {
    self.inputSources = [self.inputSourceManager availableKeyboardSources];
    if (self.englishSourceIdentifier.length == 0 ||
        ![self sourceExists:self.englishSourceIdentifier]) {
        NSString *bestEnglish = [self.inputSourceManager
            bestSourceIdentifierForLanguage:CIInputLanguageEnglish
                                    sources:self.inputSources];
        self.englishSourceIdentifier = bestEnglish != nil ? bestEnglish : @"";
    }
    if (self.hebrewSourceIdentifier.length == 0 ||
        ![self sourceExists:self.hebrewSourceIdentifier]) {
        NSString *bestHebrew = [self.inputSourceManager
            bestSourceIdentifierForLanguage:CIInputLanguageHebrew
                                    sources:self.inputSources];
        self.hebrewSourceIdentifier = bestHebrew != nil ? bestHebrew : @"";
    }
    NSString *currentName = [self.inputSourceManager currentSource].name;
    self.activeInputSourceName = currentName != nil ? currentName : @"Unknown";
    [self persistSourceSelections];
    [self reloadSourcePopups];
    [self updateInterface];
}

- (BOOL)sourceExists:(NSString *)identifier {
    for (CIKeyboardInputSource *source in self.inputSources) {
        if ([source.identifier isEqualToString:identifier]) {
            return YES;
        }
    }
    return NO;
}

- (void)persistSourceSelections {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:self.englishSourceIdentifier forKey:CIEnglishSourceDefaultsKey];
    [defaults setObject:self.hebrewSourceIdentifier forKey:CIHebrewSourceDefaultsKey];
}

- (void)reloadSourcePopups {
    if (self.englishPopup == nil || self.hebrewPopup == nil) {
        return;
    }
    [self populatePopup:self.englishPopup selectedIdentifier:self.englishSourceIdentifier];
    [self populatePopup:self.hebrewPopup selectedIdentifier:self.hebrewSourceIdentifier];
}

- (void)populatePopup:(NSPopUpButton *)popup selectedIdentifier:(NSString *)selectedIdentifier {
    [popup removeAllItems];
    if (self.inputSources.count == 0) {
        [popup addItemWithTitle:@"No keyboard input sources found"];
        popup.lastItem.representedObject = @"";
        popup.enabled = NO;
        return;
    }

    popup.enabled = YES;
    for (CIKeyboardInputSource *source in self.inputSources) {
        [popup addItemWithTitle:source.name];
        popup.lastItem.representedObject = source.identifier;
        if ([source.identifier isEqualToString:selectedIdentifier]) {
            [popup selectItem:popup.lastItem];
        }
    }
}

- (void)setLaunchAtLogin:(BOOL)shouldLaunch {
    SMAppService *service = SMAppService.mainAppService;
    NSError *error = nil;
    BOOL success = YES;
    if (shouldLaunch && service.status != SMAppServiceStatusEnabled) {
        success = [service registerAndReturnError:&error];
    } else if (!shouldLaunch && service.status != SMAppServiceStatusNotRegistered) {
        success = [service unregisterAndReturnError:&error];
    }
    if (!success) {
        [NSApp presentError:error];
    }
    self.launchAtLoginCheckbox.state = service.status == SMAppServiceStatusEnabled
        ? NSControlStateValueOn
        : NSControlStateValueOff;
}

#pragma mark - Actions

- (void)toggleEnabled:(id)sender {
    self.enabled = !self.enabled;
    [NSUserDefaults.standardUserDefaults setBool:self.enabled forKey:CIEnabledDefaultsKey];
    [self clearLastFocus];
    [self updateMonitorStatus];
}

- (void)enabledCheckboxChanged:(NSButton *)sender {
    self.enabled = sender.state == NSControlStateValueOn;
    [NSUserDefaults.standardUserDefaults setBool:self.enabled forKey:CIEnabledDefaultsKey];
    [self clearLastFocus];
    [self updateMonitorStatus];
}

- (void)englishPopupChanged:(NSPopUpButton *)sender {
    NSString *identifier = sender.selectedItem.representedObject;
    self.englishSourceIdentifier = identifier != nil ? identifier : @"";
    [self persistSourceSelections];
    [self clearLastFocus];
}

- (void)hebrewPopupChanged:(NSPopUpButton *)sender {
    NSString *identifier = sender.selectedItem.representedObject;
    self.hebrewSourceIdentifier = identifier != nil ? identifier : @"";
    [self persistSourceSelections];
    [self clearLastFocus];
}

- (void)launchAtLoginChanged:(NSButton *)sender {
    [self setLaunchAtLogin:sender.state == NSControlStateValueOn];
}

- (void)requestAccessibility:(id)sender {
    self.accessibilityGranted = [CIAccessibilityContextReader requestTrustPrompt];
    [self startInputMonitoring];
    [self updateMonitorStatus];
    if (!self.accessibilityGranted) {
        [CIAccessibilityContextReader openAccessibilitySettings];
    }
}

- (void)quitApplication:(id)sender {
    [NSApp terminate:nil];
}

- (void)checkForUpdates:(id)sender {
    [self.updaterController checkForUpdates:sender];
}

- (void)closeSettings:(id)sender {
    [self.settingsWindow performClose:sender];
}

#pragma mark - Application menu

- (void)configureApplicationMenu {
    // Menu-bar utilities do not receive the standard document app menu from a
    // storyboard. Install one explicitly so macOS can resolve common keyboard
    // equivalents, particularly Command-W while Settings is key.
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];

    NSMenuItem *applicationMenuItem = [[NSMenuItem alloc] initWithTitle:@"ContextInput"
                                                                  action:nil
                                                           keyEquivalent:@""];
    NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:@"ContextInput"];
    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"Settings…"
                                                      action:@selector(showSettings:)
                                               keyEquivalent:@","];
    settings.target = self;
    [applicationMenu addItem:settings];
    NSMenuItem *updates = [[NSMenuItem alloc] initWithTitle:@"Check for Updates…"
                                                     action:@selector(checkForUpdates:)
                                              keyEquivalent:@""];
    updates.target = self;
    [applicationMenu addItem:updates];
    [applicationMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit ContextInput"
                                                  action:@selector(quitApplication:)
                                           keyEquivalent:@"q"];
    quit.target = self;
    [applicationMenu addItem:quit];
    applicationMenuItem.submenu = applicationMenu;
    [mainMenu addItem:applicationMenuItem];

    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] initWithTitle:@"Window"
                                                             action:nil
                                                      keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    NSMenuItem *close = [[NSMenuItem alloc] initWithTitle:@"Close Settings Window"
                                                   action:@selector(closeSettings:)
                                            keyEquivalent:@"w"];
    close.target = self;
    [windowMenu addItem:close];
    windowMenuItem.submenu = windowMenu;
    [mainMenu addItem:windowMenuItem];

    NSApp.mainMenu = mainMenu;
    NSApp.windowsMenu = windowMenu;
}

#pragma mark - Menu bar

- (void)configureStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"אA";
    self.statusItem.button.toolTip = @"ContextInput";
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"ContextInput"];
    menu.delegate = self;
    self.statusItem.menu = menu;
    [self rebuildMenu:menu];
}

- (void)menuWillOpen:(NSMenu *)menu {
    [self rebuildMenu:menu];
}

- (void)rebuildMenu:(NSMenu *)menu {
    [menu removeAllItems];

    NSMenuItem *status = [[NSMenuItem alloc] initWithTitle:self.statusMessage
                                                    action:nil
                                             keyEquivalent:@""];
    status.enabled = NO;
    [menu addItem:status];
    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *enabled = [[NSMenuItem alloc] initWithTitle:@"Automatic switching"
                                                     action:@selector(toggleEnabled:)
                                              keyEquivalent:@""];
    enabled.target = self;
    enabled.state = self.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:enabled];

    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"Settings…"
                                                      action:@selector(showSettings:)
                                               keyEquivalent:@","];
    settings.target = self;
    [menu addItem:settings];

    NSMenuItem *updates = [[NSMenuItem alloc] initWithTitle:@"Check for Updates…"
                                                     action:@selector(checkForUpdates:)
                                              keyEquivalent:@""];
    updates.target = self;
    [menu addItem:updates];

    if (!self.accessibilityGranted) {
        NSMenuItem *permission = [[NSMenuItem alloc] initWithTitle:@"Grant Accessibility Access…"
                                                            action:@selector(requestAccessibility:)
                                                     keyEquivalent:@""];
        permission.target = self;
        [menu addItem:permission];
    }

    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit ContextInput"
                                                  action:@selector(quitApplication:)
                                           keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];
}

#pragma mark - Settings window

- (void)showSettings:(id)sender {
    if (self.settingsWindow == nil) {
        [self buildSettingsWindow];
    }
    [self refreshInputSources];
    [self updateInterface];
    [self.settingsWindow center];
    [self.settingsWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)buildSettingsWindow {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 590, 670)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"ContextInput Settings";
    window.releasedWhenClosed = NO;
    window.contentMinSize = NSMakeSize(590, 450);
    self.settingsWindow = window;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:window.contentView.bounds];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    [window.contentView addSubview:scroll];
    CISettingsContentView *document = [[CISettingsContentView alloc] initWithFrame:NSZeroRect];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.documentView = document;
    [NSLayoutConstraint activateConstraints:@[
        [document.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
    ]];

    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 13;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:document.topAnchor constant:22],
        [stack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-22],
    ]];

    NSTextField *title = [self label:@"ContextInput" font:[NSFont systemFontOfSize:22 weight:NSFontWeightSemibold]];
    [stack addArrangedSubview:title];
    NSString *shortVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *buildVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    shortVersion = shortVersion.length > 0 ? shortVersion : @"Unknown";
    buildVersion = buildVersion.length > 0 ? buildVersion : @"Unknown";
    NSTextField *version = [self
        label:[NSString stringWithFormat:@"Version %@ (Build %@)", shortVersion, buildVersion]
         font:[NSFont systemFontOfSize:11 weight:NSFontWeightRegular]];
    version.textColor = NSColor.secondaryLabelColor;
    [stack addArrangedSubview:version];
    [stack setCustomSpacing:3 afterView:title];
    [stack setCustomSpacing:10 afterView:version];
    NSTextField *subtitle = [self wrappingLabel:@"Fast, private Hebrew/English keyboard selection from the conversation around the focused field."];
    subtitle.textColor = NSColor.secondaryLabelColor;
    [stack addArrangedSubview:subtitle];

    self.enabledCheckbox = [NSButton checkboxWithTitle:@"Enable automatic language switching"
                                                 target:self
                                                 action:@selector(enabledCheckboxChanged:)];
    [stack addArrangedSubview:self.enabledCheckbox];

    [stack addArrangedSubview:[self sectionHeading:@"STATUS"]];
    self.statusLabel = [self wrappingLabel:@""];
    [stack addArrangedSubview:self.statusLabel];

    NSStackView *permissionRow = [NSStackView stackViewWithViews:@[]];
    permissionRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    permissionRow.alignment = NSLayoutAttributeCenterY;
    permissionRow.spacing = 12;
    self.permissionLabel = [self wrappingLabel:@""];
    [self.permissionLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.permissionButton = [NSButton buttonWithTitle:@"Grant Access"
                                               target:self
                                               action:@selector(requestAccessibility:)];
    [permissionRow addArrangedSubview:self.permissionLabel];
    [permissionRow addArrangedSubview:self.permissionButton];
    [stack addArrangedSubview:permissionRow];
    [permissionRow.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;

    [stack addArrangedSubview:[self sectionHeading:@"KEYBOARDS"]];
    self.englishPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.englishPopup.target = self;
    self.englishPopup.action = @selector(englishPopupChanged:);
    self.hebrewPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.hebrewPopup.target = self;
    self.hebrewPopup.action = @selector(hebrewPopupChanged:);
    NSGridView *keyboardGrid = [NSGridView gridViewWithViews:@[
        @[[self label:@"English keyboard" font:[NSFont systemFontOfSize:13]], self.englishPopup],
        @[[self label:@"Hebrew keyboard" font:[NSFont systemFontOfSize:13]], self.hebrewPopup],
    ]];
    keyboardGrid.rowSpacing = 8;
    keyboardGrid.columnSpacing = 16;
    keyboardGrid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    [keyboardGrid columnAtIndex:0].width = 140;
    [keyboardGrid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;
    [stack addArrangedSubview:keyboardGrid];
    [keyboardGrid.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;

    self.activeSourceLabel = [self wrappingLabel:@""];
    self.activeSourceLabel.textColor = NSColor.secondaryLabelColor;
    [stack addArrangedSubview:self.activeSourceLabel];

    [stack addArrangedSubview:[self sectionHeading:@"STARTUP"]];
    self.launchAtLoginCheckbox = [NSButton checkboxWithTitle:@"Launch ContextInput at login"
                                                       target:self
                                                       action:@selector(launchAtLoginChanged:)];
    [stack addArrangedSubview:self.launchAtLoginCheckbox];

    [stack addArrangedSubview:[self sectionHeading:@"UPDATES"]];
    NSTextField *updatesDescription = [self wrappingLabel:@"Updates are checked automatically and installed when ContextInput is idle. Context text is never included in update requests."];
    updatesDescription.textColor = NSColor.secondaryLabelColor;
    [stack addArrangedSubview:updatesDescription];
    NSButton *updatesButton = [NSButton buttonWithTitle:@"Check for Updates…"
                                                 target:self
                                                 action:@selector(checkForUpdates:)];
    [stack addArrangedSubview:updatesButton];

    [stack addArrangedSubview:[self sectionHeading:@"LAST FOCUS EVENT"]];
    self.applicationLabel = [self wrappingLabel:@""];
    self.focusLabel = [self wrappingLabel:@""];
    self.decisionLabel = [self wrappingLabel:@""];
    self.reasonLabel = [self wrappingLabel:@""];
    self.samplesLabel = [self wrappingLabel:@""];
    self.samplesLabel.selectable = YES;
    self.samplesLabel.maximumNumberOfLines = 3;
    self.contextLabel = [self wrappingLabel:@""];
    self.contextLabel.selectable = YES;
    self.contextLabel.maximumNumberOfLines = 4;
    self.switchLabel = [self wrappingLabel:@""];
    self.switchLabel.selectable = YES;
    [stack addArrangedSubview:self.applicationLabel];
    [stack addArrangedSubview:self.focusLabel];
    [stack addArrangedSubview:self.decisionLabel];
    [stack addArrangedSubview:self.reasonLabel];
    [stack addArrangedSubview:self.samplesLabel];
    [stack addArrangedSubview:self.contextLabel];
    [stack addArrangedSubview:self.switchLabel];

    NSTextField *privacy = [self wrappingLabel:@"All language context is processed locally with Apple’s Natural Language framework and secure text fields are always ignored. The only network access is a version check and signed update download from this project’s GitHub release feed."];
    privacy.textColor = NSColor.tertiaryLabelColor;
    privacy.font = [NSFont systemFontOfSize:11];
    [stack addArrangedSubview:privacy];

    for (NSView *view in stack.arrangedSubviews) {
        if (view != keyboardGrid) {
            [view.widthAnchor constraintLessThanOrEqualToAnchor:stack.widthAnchor].active = YES;
        }
    }
    [self reloadSourcePopups];
}

- (NSTextField *)label:(NSString *)text font:(NSFont *)font {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = font;
    return label;
}

- (NSTextField *)wrappingLabel:(NSString *)text {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.maximumNumberOfLines = 0;
    return label;
}

- (NSTextField *)sectionHeading:(NSString *)text {
    NSTextField *label = [self label:text font:[NSFont systemFontOfSize:11 weight:NSFontWeightSemibold]];
    label.textColor = NSColor.secondaryLabelColor;
    return label;
}

- (void)updateInterface {
    self.statusItem.button.title = self.enabled ? @"אA" : @"אA̸";
    self.statusItem.button.toolTip = self.statusMessage;
    if (self.settingsWindow == nil) {
        return;
    }

    self.enabledCheckbox.state = self.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.statusLabel.stringValue = self.statusMessage;
    self.permissionLabel.stringValue = self.accessibilityGranted
        ? @"Accessibility: Allowed"
        : @"Accessibility is required to detect focus and read visible nearby text.";
    self.permissionLabel.textColor = self.accessibilityGranted
        ? NSColor.systemGreenColor
        : NSColor.systemOrangeColor;
    self.permissionButton.hidden = self.accessibilityGranted;
    self.launchAtLoginCheckbox.state = SMAppService.mainAppService.status == SMAppServiceStatusEnabled
        ? NSControlStateValueOn
        : NSControlStateValueOff;
    self.activeSourceLabel.stringValue = [NSString stringWithFormat:@"Current input source (live): %@", self.activeInputSourceName];
    self.applicationLabel.stringValue = [NSString stringWithFormat:@"Application: %@", self.lastApplication];
    self.focusLabel.stringValue = [NSString stringWithFormat:@"Focused element: %@", self.lastFocusDescription];
    self.decisionLabel.stringValue = self.lastConfidence > 0
        ? [NSString stringWithFormat:@"Decision: %@ (%ld%%)", self.lastDecision, lround(self.lastConfidence * 100)]
        : [NSString stringWithFormat:@"Decision: %@", self.lastDecision];
    self.reasonLabel.stringValue = [NSString
        stringWithFormat:@"Reason: %@ · Context items: %lu",
                         self.lastReason,
                         (unsigned long)self.lastContextItemCount];
    self.samplesLabel.stringValue = [NSString stringWithFormat:@"Nearest context: %@", self.lastContextSamples];
    self.contextLabel.stringValue = [NSString stringWithFormat:@"Evidence: %@", self.lastContext];
    self.switchLabel.stringValue = [NSString stringWithFormat:@"Last switch: %@", self.lastSwitchSummary];
}

@end
