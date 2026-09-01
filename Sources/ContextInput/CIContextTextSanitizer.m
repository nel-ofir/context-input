#import "CIContextTextSanitizer.h"

@implementation CIContextTextSanitizer

+ (NSString *)textFromAccessibilityText:(NSString *)text
                       elementIdentifier:(NSString *)elementIdentifier
                         applicationName:(NSString *)applicationName {
    if (text.length == 0) {
        return nil;
    }
    BOOL isWhatsApp = [applicationName localizedCaseInsensitiveContainsString:@"whatsapp"];
    if (!isWhatsApp) {
        return text;
    }

    NSString *cleaned = [text stringByReplacingOccurrencesOfString:
        @"[\u200E\u200F\u202A-\u202E\u2066-\u2069\uFFFC]"
                                                      withString:@""
                                                         options:NSRegularExpressionSearch
                                                           range:NSMakeRange(0, text.length)];
    NSString *lowercase = cleaned.lowercaseString;
    if ([lowercase containsString:@"syncing paused. open whatsapp"] ||
        [lowercase containsString:@"end-to-end encrypted"]) {
        return nil;
    }

    if ([elementIdentifier isEqualToString:@"WAMessageBubbleTableViewCell"]) {
        NSArray<NSString *> *prefixes = @[@"your message,", @"message,"];
        for (NSString *prefix in prefixes) {
            if ([cleaned.lowercaseString hasPrefix:prefix]) {
                cleaned = [cleaned substringFromIndex:prefix.length];
                break;
            }
        }

        NSRange timestamp = [cleaned
            rangeOfString:@"(?:\\d{1,2}\\s*[A-Za-z]+|Today|Yesterday)\\s*at\\s*\\d{1,2}:\\d{2}"
                  options:NSRegularExpressionSearch | NSCaseInsensitiveSearch];
        if (timestamp.location != NSNotFound) {
            cleaned = [cleaned substringToIndex:timestamp.location];
        } else {
            NSRange deliveryMetadata = [cleaned
                rangeOfString:@",\\s*(?:Sent to|Received from).*$"
                      options:NSRegularExpressionSearch | NSCaseInsensitiveSearch];
            if (deliveryMetadata.location != NSNotFound) {
                cleaned = [cleaned substringToIndex:deliveryMetadata.location];
            }
        }
    }

    NSCharacterSet *edgeCharacters = [NSCharacterSet
        characterSetWithCharactersInString:@" \t\r\n,"];
    cleaned = [cleaned stringByTrimmingCharactersInSet:edgeCharacters];
    return cleaned.length > 0 ? cleaned : nil;
}

+ (NSString *)conversationTitleFromContainerDescription:(NSString *)description
                                         applicationName:(NSString *)applicationName {
    if (![applicationName localizedCaseInsensitiveContainsString:@"whatsapp"] ||
        description.length == 0) {
        return nil;
    }
    NSString *prefix = @"Messages in chat with ";
    if (![description hasPrefix:prefix] || description.length <= prefix.length) {
        return nil;
    }
    return [description substringFromIndex:prefix.length];
}

@end
