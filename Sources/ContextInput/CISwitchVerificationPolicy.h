#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, CISwitchVerificationAction) {
    CISwitchVerificationCancel,
    CISwitchVerificationRetry,
    CISwitchVerificationWait,
    CISwitchVerificationVerified,
    CISwitchVerificationFailed,
};

@interface CISwitchVerificationPolicy : NSObject
+ (CISwitchVerificationAction)actionWithTargetMatches:(BOOL)targetMatches
                                         finalCheck:(BOOL)finalCheck
                                     focusIsCurrent:(BOOL)focusIsCurrent
                                     userInteracted:(BOOL)userInteracted;
@end
