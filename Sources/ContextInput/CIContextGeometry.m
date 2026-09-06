#import "CIContextGeometry.h"

@implementation CIContextGeometry

+ (NSNumber *)proximityScoreForCandidate:(CGRect)candidate
                                  focused:(CGRect)focused
                          hasFocusedFrame:(BOOL)hasFocusedFrame {
    if (candidate.size.width <= 0 || candidate.size.height <= 0) {
        return nil;
    }
    if (!hasFocusedFrame) {
        return @(10000.0 - CGRectGetMaxY(candidate));
    }

    // Accessibility coordinates start at the top-left of the primary display.
    CGFloat verticalGap = CGRectGetMinY(focused) - CGRectGetMaxY(candidate);
    if (verticalGap < -8 || verticalGap > 1600) {
        return nil;
    }

    CGFloat horizontalOverlap = fmin(CGRectGetMaxX(candidate), CGRectGetMaxX(focused)) -
        fmax(CGRectGetMinX(candidate), CGRectGetMinX(focused));
    CGFloat shorterWidth = fmin(candidate.size.width, focused.size.width);
    CGFloat minimumOverlap = fmin(36.0, shorterWidth * 0.18);
    if (horizontalOverlap < minimumOverlap) {
        return nil;
    }
    CGFloat nonnegativeGap = verticalGap > 0 ? verticalGap : 0;
    CGFloat centerDistance = fabs(CGRectGetMidX(candidate) - CGRectGetMidX(focused));
    return @(nonnegativeGap + (centerDistance * 0.08));
}

@end
