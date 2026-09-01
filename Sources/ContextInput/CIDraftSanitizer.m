#import "CIDraftSanitizer.h"

@implementation CIDraftSanitizer

+ (NSString *)draftFromAccessibilityValue:(NSString *)value
                          placeholderValue:(NSString *)placeholder
                        numberOfCharacters:(NSNumber *)numberOfCharacters
                           applicationName:(NSString *)applicationName {
    if (value.length == 0) {
        return nil;
    }

    if (placeholder.length > 0 &&
        [value localizedCaseInsensitiveCompare:placeholder] == NSOrderedSame) {
        return nil;
    }

    // AXNumberOfCharacters describes editable content, whereas AXValue may be a
    // synthesized accessible value. A nonempty AXValue with zero editable
    // characters is therefore UI placeholder text, not a draft.
    if (numberOfCharacters != nil && numberOfCharacters.integerValue == 0) {
        return nil;
    }

    // ChatGPT's current macOS accessibility bridge exposes these empty-composer
    // placeholders as AXValue and omits AXPlaceholderValue. Keep this narrow to
    // ChatGPT/Codex so an identical sentence typed in another app remains a draft.
    BOOL chatGPTLike = [applicationName localizedCaseInsensitiveContainsString:@"chatgpt"] ||
        [applicationName localizedCaseInsensitiveContainsString:@"codex"];
    if (chatGPTLike) {
        NSSet<NSString *> *knownEmptyComposerValues = [NSSet setWithArray:@[
            @"do anything",
            @"ask anything",
            @"message chatgpt",
            @"message codex",
        ]];
        if ([knownEmptyComposerValues containsObject:value.lowercaseString]) {
            return nil;
        }
    }

    return value;
}

@end
