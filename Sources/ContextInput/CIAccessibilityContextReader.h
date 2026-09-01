#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>
#import "CIModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface CIAccessibilityContextReader : NSObject
+ (BOOL)isTrusted;
+ (BOOL)requestTrustPrompt;
+ (void)openAccessibilitySettings;
- (nullable AXUIElementRef)copyFocusedEditableElement CF_RETURNS_RETAINED;
- (nullable CIScreenContext *)readContextAroundElement:(AXUIElementRef)focused;
@end

NS_ASSUME_NONNULL_END
