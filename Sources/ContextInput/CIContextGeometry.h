#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface CIContextGeometry : NSObject
+ (nullable NSNumber *)proximityScoreForCandidate:(CGRect)candidate
                                           focused:(CGRect)focused
                                   hasFocusedFrame:(BOOL)hasFocusedFrame;
@end

NS_ASSUME_NONNULL_END
