#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CIContextTextSanitizer : NSObject
+ (nullable NSString *)textFromAccessibilityText:(NSString *)text
                                elementIdentifier:(nullable NSString *)elementIdentifier
                                  applicationName:(NSString *)applicationName;
+ (nullable NSString *)conversationTitleFromContainerDescription:(nullable NSString *)description
                                                  applicationName:(NSString *)applicationName;
@end

NS_ASSUME_NONNULL_END
