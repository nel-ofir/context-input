#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CIInputLanguage) {
    CIInputLanguageHebrew,
    CIInputLanguageEnglish,
};

FOUNDATION_EXPORT NSString *CIInputLanguageDisplayName(CIInputLanguage language);
FOUNDATION_EXPORT NSString *CIInputLanguageShortName(CIInputLanguage language);

@interface CIKeyboardInputSource : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSArray<NSString *> *languages;
- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                         languages:(NSArray<NSString *> *)languages;
@end

@interface CILanguageDecision : NSObject
@property(nonatomic) CIInputLanguage language;
@property(nonatomic) double confidence;
@property(nonatomic, copy) NSString *evidence;
@property(nonatomic, copy) NSString *reason;
- (instancetype)initWithLanguage:(CIInputLanguage)language
                       confidence:(double)confidence
                         evidence:(NSString *)evidence
                           reason:(NSString *)reason;
@end

@interface CIScreenContext : NSObject
@property(nonatomic, copy) NSString *applicationName;
@property(nonatomic, copy, nullable) NSString *bundleIdentifier;
@property(nonatomic, copy, nullable) NSString *draft;
@property(nonatomic, copy) NSArray<NSString *> *nearbyTexts;
@property(nonatomic) BOOL terminalLike;
@property(nonatomic) BOOL opaqueTerminal;
@property(nonatomic, copy) NSString *focusDescription;
- (instancetype)initWithApplicationName:(NSString *)applicationName
                       bundleIdentifier:(nullable NSString *)bundleIdentifier
                                   draft:(nullable NSString *)draft
                             nearbyTexts:(NSArray<NSString *> *)nearbyTexts
                            terminalLike:(BOOL)terminalLike
                        focusDescription:(NSString *)focusDescription;
@end

NS_ASSUME_NONNULL_END
