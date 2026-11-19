#import "CIAppLanguagePreferences.h"

static NSString *const CIAppLanguagesDefaultsKey = @"appDefaultLanguages";

@interface CIAppLanguagePreferences ()
@property(nonatomic, strong) NSUserDefaults *defaults;
@end

@implementation CIAppLanguagePreferences

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (self) _defaults = defaults;
    return self;
}

- (nullable NSNumber *)languageForBundleIdentifier:(nullable NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) return nil;
    id stored = [self.defaults dictionaryForKey:CIAppLanguagesDefaultsKey][bundleIdentifier];
    if (![stored isKindOfClass:NSString.class]) return nil;
    if ([stored isEqualToString:@"he"]) return @(CIInputLanguageHebrew);
    if ([stored isEqualToString:@"en"]) return @(CIInputLanguageEnglish);
    return nil;
}

- (void)setLanguage:(nullable NSNumber *)language
  forBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) return;
    NSMutableDictionary<NSString *, NSString *> *rules =
        [[self.defaults dictionaryForKey:CIAppLanguagesDefaultsKey] mutableCopy];
    if (rules == nil) rules = [NSMutableDictionary dictionary];
    if (language != nil && language.integerValue == CIInputLanguageHebrew) {
        rules[bundleIdentifier] = @"he";
    } else if (language != nil && language.integerValue == CIInputLanguageEnglish) {
        rules[bundleIdentifier] = @"en";
    } else {
        [rules removeObjectForKey:bundleIdentifier];
    }
    [self.defaults setObject:rules forKey:CIAppLanguagesDefaultsKey];
}

- (NSArray<NSString *> *)configuredBundleIdentifiers {
    NSDictionary *rules = [self.defaults dictionaryForKey:CIAppLanguagesDefaultsKey];
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    for (id bundleIdentifier in rules) {
        if ([bundleIdentifier isKindOfClass:NSString.class] &&
            [self languageForBundleIdentifier:bundleIdentifier] != nil) {
            [identifiers addObject:bundleIdentifier];
        }
    }
    return [identifiers sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

@end
