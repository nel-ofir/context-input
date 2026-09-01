#import <Foundation/Foundation.h>
#import "CIModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface CILanguageClassifier : NSObject
- (nullable CILanguageDecision *)classifyDraft:(nullable NSString *)draft
                                   nearbyTexts:(NSArray<NSString *> *)nearbyTexts;
- (nullable CILanguageDecision *)classifyText:(NSString *)text reason:(NSString *)reason;
@end

NS_ASSUME_NONNULL_END
