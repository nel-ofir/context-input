#import "CIModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface CIAppLanguagePreferences : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (nullable NSNumber *)languageForBundleIdentifier:(nullable NSString *)bundleIdentifier;
- (void)setLanguage:(nullable NSNumber *)language
  forBundleIdentifier:(NSString *)bundleIdentifier;
- (NSArray<NSString *> *)configuredBundleIdentifiers;
@end

NS_ASSUME_NONNULL_END
