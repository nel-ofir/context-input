#import "CISwitchVerificationPolicy.h"

@implementation CISwitchVerificationPolicy
+ (CISwitchVerificationAction)actionWithTargetMatches:(BOOL)targetMatches
                                requiresReassertion:(BOOL)requiresReassertion
                                         finalCheck:(BOOL)finalCheck
                                     focusIsCurrent:(BOOL)focusIsCurrent
                                     userInteracted:(BOOL)userInteracted {
    if (!focusIsCurrent || userInteracted) {
        return CISwitchVerificationCancel;
    }
    if (finalCheck) {
        return targetMatches ? CISwitchVerificationVerified : CISwitchVerificationFailed;
    }
    return !targetMatches || requiresReassertion
        ? CISwitchVerificationRetry : CISwitchVerificationWait;
}
@end
