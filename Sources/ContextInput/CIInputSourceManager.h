#import <Foundation/Foundation.h>
#import "CIModels.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const CIInputSourceErrorDomain;

typedef NS_ERROR_ENUM(CIInputSourceErrorDomain, CIInputSourceErrorCode) {
    CIInputSourceErrorSourceNotFound = 1,
    CIInputSourceErrorSelectionFailed = 2,
};

@interface CIInputSourceManager : NSObject
- (NSArray<CIKeyboardInputSource *> *)availableKeyboardSources;
- (nullable CIKeyboardInputSource *)currentSource;
- (nullable NSString *)bestSourceIdentifierForLanguage:(CIInputLanguage)language
                                                sources:(NSArray<CIKeyboardInputSource *> *)sources;
- (BOOL)selectSourceIdentifier:(NSString *)identifier error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
