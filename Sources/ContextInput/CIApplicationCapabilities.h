#import <Foundation/Foundation.h>

@class NSRunningApplication;

NS_ASSUME_NONNULL_BEGIN

@interface CIApplicationCapabilities : NSObject
+ (BOOL)infoDictionaryDeclaresTerminalSupport:(NSDictionary *)infoDictionary;
+ (BOOL)applicationDeclaresTerminalSupport:(NSRunningApplication *)application;
+ (BOOL)isOpaqueAccessibilityRole:(nullable NSString *)role;
@end

NS_ASSUME_NONNULL_END
