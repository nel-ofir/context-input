#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CIDraftSanitizer : NSObject
+ (nullable NSString *)draftFromAccessibilityValue:(nullable NSString *)value
                                   placeholderValue:(nullable NSString *)placeholder
                                 numberOfCharacters:(nullable NSNumber *)numberOfCharacters
                                    applicationName:(NSString *)applicationName;
@end

NS_ASSUME_NONNULL_END
