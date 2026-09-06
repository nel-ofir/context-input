#import "CIContextTextSanitizer.h"

@implementation CIContextTextSanitizer

+ (NSString *)textFromAccessibilityText:(NSString *)text
                       elementIdentifier:(NSString *)elementIdentifier
                         applicationName:(NSString *)applicationName {
    if (text.length == 0) {
        return nil;
    }
    BOOL isSlack = [applicationName localizedCaseInsensitiveContainsString:@"slack"];
    if (isSlack) {
        NSString *slackText = [text stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *lowercaseSlackText = slackText.lowercaseString;
        BOOL pausedNotificationsFragment =
            [lowercaseSlackText isEqualToString:@"paused their notifications"] ||
            [lowercaseSlackText isEqualToString:@"paused notifications"] ||
            [lowercaseSlackText isEqualToString:@"has"];
        BOOL completePausedNotificationsNotice =
            [lowercaseSlackText containsString:@" has paused their notifications"] ||
            [lowercaseSlackText containsString:@" has paused notifications"];
        if (pausedNotificationsFragment || completePausedNotificationsNotice) {
            return nil;
        }

        // Chromium exposes a Slack message both as a leaf text node and as a
        // parent label. In right-to-left conversations that parent is formatted
        // like "Author: 12:04 .message PM.". Strip the author and timestamp so
        // they cannot turn a short Hebrew reply into English evidence; the
        // reader's normal exact deduplication then collapses parent and leaf.
        static NSRegularExpression *messageWrapperExpression;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            messageWrapperExpression = [NSRegularExpression
                regularExpressionWithPattern:@"^.+?:\\s*\\d{1,2}:\\d{2}\\s+\\.(.+?)\\s+(?:AM|PM)\\.?$"
                                       options:NSRegularExpressionCaseInsensitive
                                         error:nil];
        });
        NSTextCheckingResult *wrapperMatch = [messageWrapperExpression
            firstMatchInString:slackText
                       options:0
                         range:NSMakeRange(0, slackText.length)];
        if (wrapperMatch.numberOfRanges > 1) {
            NSString *message = [slackText substringWithRange:[wrapperMatch rangeAtIndex:1]];
            message = [message stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceAndNewlineCharacterSet];
            return message.length > 0 ? message : nil;
        }
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
