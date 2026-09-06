#import "CISwitchVerificationPolicy.h"

@implementation CISwitchVerificationPolicy
+ (CISwitchVerificationAction)actionWithTargetMatches:(BOOL)targetMatches
                                         finalCheck:(BOOL)finalCheck
                                     focusIsCurrent:(BOOL)focusIsCurrent
                                     userInteracted:(BOOL)userInteracted {
    if (!focusIsCurrent || userInteracted) {
        return CISwitchVerificationCancel;
    }
    if (finalCheck) {
        return targetMatches ? CISwitchVerificationVerified : CISwitchVerificationFailed;
    }
    return !targetMatches ? CISwitchVerificationRetry : CISwitchVerificationWait;
}
@end
