#import "CIModels.h"

NSString *CIInputLanguageDisplayName(CIInputLanguage language) {
    return language == CIInputLanguageHebrew ? @"Hebrew" : @"English";
}

NSString *CIInputLanguageShortName(CIInputLanguage language) {
    return language == CIInputLanguageHebrew ? @"HE" : @"EN";
}

@implementation CIKeyboardInputSource

- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                         languages:(NSArray<NSString *> *)languages {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _name = [name copy];
        _languages = [languages copy];
    }
    return self;
}

@end

@implementation CILanguageDecision

- (instancetype)initWithLanguage:(CIInputLanguage)language
                       confidence:(double)confidence
                         evidence:(NSString *)evidence
                           reason:(NSString *)reason {
    self = [super init];
    if (self) {
        _language = language;
        _confidence = confidence;
        _evidence = [evidence copy];
        _reason = [reason copy];
    }
    return self;
}

@end

@implementation CIScreenContext

- (instancetype)initWithApplicationName:(NSString *)applicationName
                       bundleIdentifier:(NSString *)bundleIdentifier
                                   draft:(NSString *)draft
                             nearbyTexts:(NSArray<NSString *> *)nearbyTexts
                            terminalLike:(BOOL)terminalLike
                        focusDescription:(NSString *)focusDescription {
    self = [super init];
    if (self) {
        _applicationName = [applicationName copy];
        _bundleIdentifier = [bundleIdentifier copy];
        _draft = [draft copy];
        _nearbyTexts = [nearbyTexts copy];
        _terminalLike = terminalLike;
        _focusDescription = [focusDescription copy];
    }
    return self;
}

@end
