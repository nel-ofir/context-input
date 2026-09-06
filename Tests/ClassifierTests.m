#import <Foundation/Foundation.h>
#import "CIApplicationCapabilities.h"
#import "CIContextGeometry.h"
#import "CIContextTextSanitizer.h"
#import "CIDraftSanitizer.h"
#import "CILanguageClassifier.h"
#import "CISwitchVerificationPolicy.h"

static NSInteger failures = 0;

static void CIExpect(BOOL condition, NSString *message) {
    if (!condition) {
        failures += 1;
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    }
}

int main(void) {
    @autoreleasepool {
        CILanguageClassifier *classifier = [[CILanguageClassifier alloc] init];

        // Exhaust all policy combinations, including cancellation before either check.
        for (NSUInteger bits = 0; bits < 16; bits++) {
            BOOL matches = (bits & 1) != 0;
            BOOL final = (bits & 2) != 0;
            BOOL focused = (bits & 4) != 0;
            BOOL interacted = (bits & 8) != 0;
            CISwitchVerificationAction expected;
            if (!focused || interacted) expected = CISwitchVerificationCancel;
            else if (final) expected = matches ? CISwitchVerificationVerified : CISwitchVerificationFailed;
            else if (!matches) expected = CISwitchVerificationRetry;
            else expected = CISwitchVerificationWait;
            CIExpect([CISwitchVerificationPolicy actionWithTargetMatches:matches
                finalCheck:final focusIsCurrent:focused
                userInteracted:interacted] == expected,
                [NSString stringWithFormat:@"switch verification policy combination %lu", (unsigned long)bits]);
        }

        for (NSString *role in @[@"AXWindow", @"AXApplication", @"AXTextField", @"AXTextArea"]) {
            for (NSString *value in @[@"Command Input.", @"קלט פקודה"]) {
                NSString *draft = [CIDraftSanitizer draftFromAccessibilityValue:value
                    placeholderValue:nil numberOfCharacters:nil applicationName:@"Any App"
                    elementRole:role];
                BOOL editable = [role isEqualToString:@"AXTextField"] || [role isEqualToString:@"AXTextArea"];
                CIExpect(editable ? [draft isEqualToString:value] : draft == nil,
                    @"window/application announcements are not drafts; real editable values are preserved");
            }
        }

        NSDictionary *shellRoleApplication = @{
            @"LSApplicationCategoryType": @"public.app-category.developer-tools",
            @"CFBundleDocumentTypes": @[
                @{
                    @"CFBundleTypeName": @"Terminal shell script",
                    @"CFBundleTypeRole": @"Shell",
                    @"LSItemContentTypes": @[@"com.apple.terminal.shell-script"],
                },
            ],
        };
        CIExpect([CIApplicationCapabilities
                     infoDictionaryDeclaresTerminalSupport:shellRoleApplication],
                 @"declared shell document role identifies a terminal-capable app");

        NSDictionary *terminalUTIApplication = @{
            @"LSApplicationCategoryType": @"public.app-category.utilities",
            @"CFBundleDocumentTypes": @[
                @{
                    @"CFBundleTypeRole": @"Viewer",
                    @"LSItemContentTypes": @[@"com.apple.terminal.shell-script"],
                },
            ],
        };
        CIExpect([CIApplicationCapabilities
                     infoDictionaryDeclaresTerminalSupport:terminalUTIApplication],
                 @"terminal shell-script UTI identifies a terminal-capable app");

        NSDictionary *businessApplicationWithShellHandler = @{
            @"LSApplicationCategoryType": @"public.app-category.business",
            @"CFBundleDocumentTypes": @[
                @{
                    @"CFBundleTypeRole": @"Shell",
                    @"LSItemContentTypes": @[@"com.apple.terminal.shell-script"],
                },
            ],
        };
        CIExpect(![CIApplicationCapabilities
                      infoDictionaryDeclaresTerminalSupport:businessApplicationWithShellHandler],
                 @"a business app is never treated as an opaque terminal merely for handling shell files");

        NSDictionary *ordinaryDeveloperTool = @{
            @"LSApplicationCategoryType": @"public.app-category.developer-tools",
            @"CFBundleDocumentTypes": @[
                @{
                    @"CFBundleTypeRole": @"Editor",
                    @"LSItemContentTypes": @[@"public.source-code"],
                },
            ],
        };
        CIExpect(![CIApplicationCapabilities
                      infoDictionaryDeclaresTerminalSupport:ordinaryDeveloperTool],
                 @"developer-tool category alone does not imply a terminal");
        CIExpect([CIApplicationCapabilities isOpaqueAccessibilityRole:@"AXWindow"],
                 @"an opaque window can represent a custom terminal surface");
        CIExpect([CIApplicationCapabilities isOpaqueAccessibilityRole:@"AXUnknown"],
                 @"an unknown role can represent a custom terminal surface");
        CIExpect(![CIApplicationCapabilities isOpaqueAccessibilityRole:@"AXButton"],
                 @"normal controls are not treated as opaque terminal surfaces");
        CIExpect(![CIApplicationCapabilities isOpaqueAccessibilityRole:@"AXTextField"],
                 @"native text fields stay on the normal classification path");

        CGRect composerFrame = CGRectMake(200, 900, 800, 100);
        CIExpect([CIContextGeometry proximityScoreForCandidate:CGRectMake(20, 820, 185, 40)
                                                       focused:composerFrame
                                               hasFocusedFrame:YES] == nil,
                 @"a tiny border overlap does not admit text from an adjacent sidebar");
        CIExpect([CIContextGeometry proximityScoreForCandidate:CGRectMake(250, 820, 300, 40)
                                                       focused:composerFrame
                                               hasFocusedFrame:YES] != nil,
                 @"message text in the composer's horizontal column is retained");
        CIExpect([CIContextGeometry proximityScoreForCandidate:CGRectMake(250, 820, 20, 40)
                                                       focused:composerFrame
                                               hasFocusedFrame:YES] != nil,
                 @"narrow message text remains valid when it fully overlaps the composer");

        NSString *whatsAppMessage = [CIContextTextSanitizer
            textFromAccessibilityText:@"message, לא איפה אתם?, 23Augustat11:49, Received from אמא עבודה"
                    elementIdentifier:@"WAMessageBubbleTableViewCell"
                      applicationName:@"WhatsApp"];
        CIExpect([whatsAppMessage isEqualToString:@"לא איפה אתם?"],
                 @"WhatsApp delivery metadata is removed from a received message");

        NSString *whatsAppOwnMessage = [CIContextTextSanitizer
            textFromAccessibilityText:@"Your message, בתיק שלי הסתדרת?, 23Augustat11:48, Sent to אמא עבודה, Delivered"
                    elementIdentifier:@"WAMessageBubbleTableViewCell"
                      applicationName:@"WhatsApp"];
        CIExpect([whatsAppOwnMessage isEqualToString:@"בתיק שלי הסתדרת?"],
                 @"WhatsApp delivery metadata is removed from a sent message");

        NSString *whatsAppSystemNotice = [CIContextTextSanitizer
            textFromAccessibilityText:@"Syncing paused. Open WhatsApp on your phone to continue syncing."
                    elementIdentifier:nil
                      applicationName:@"WhatsApp"];
        CIExpect(whatsAppSystemNotice == nil, @"WhatsApp synchronization UI is not conversation evidence");

        NSString *whatsAppTitle = [CIContextTextSanitizer
            conversationTitleFromContainerDescription:@"Messages in chat with אמא עבודה"
                                      applicationName:@"WhatsApp"];
        CIExpect([whatsAppTitle isEqualToString:@"אמא עבודה"],
                 @"WhatsApp local conversation title is extracted");

        NSString *slackPausedNotifications = [CIContextTextSanitizer
            textFromAccessibilityText:@"paused their notifications"
                    elementIdentifier:nil
                      applicationName:@"Slack"];
        CIExpect(slackPausedNotifications == nil,
                 @"Slack's split paused-notifications status is not conversation evidence");

        NSString *slackCompletePausedNotifications = [CIContextTextSanitizer
            textFromAccessibilityText:@"Hili Seker Amiel has paused their notifications"
                    elementIdentifier:nil
                      applicationName:@"Slack"];
        CIExpect(slackCompletePausedNotifications == nil,
                 @"Slack's complete paused-notifications status is not conversation evidence");

        NSString *slackRealMessage = [CIContextTextSanitizer
            textFromAccessibilityText:@"הכל טוב, אבקש ממנו"
                    elementIdentifier:nil
                      applicationName:@"Slack"];
        CIExpect([slackRealMessage isEqualToString:@"הכל טוב, אבקש ממנו"],
                 @"Slack conversation messages remain available as evidence");

        NSString *slackWrappedHebrewMessage = [CIContextTextSanitizer
            textFromAccessibilityText:@"Nel Ofir: 12:04 .בכיף PM."
                    elementIdentifier:nil
                      applicationName:@"Slack"];
        CIExpect([slackWrappedHebrewMessage isEqualToString:@"בכיף"],
                 @"Slack's RTL parent message label is reduced to its Hebrew body");

        NSString *slackWrappedLongerHebrewMessage = [CIContextTextSanitizer
            textFromAccessibilityText:@"Hili Seker Amiel: 12:03 .אחלה תודה PM."
                    elementIdentifier:nil
                      applicationName:@"Slack"];
        CIExpect([slackWrappedLongerHebrewMessage isEqualToString:@"אחלה תודה"],
                 @"Slack author and timestamp metadata do not become language evidence");

        NSString *slackLogicalOrderHebrewMessage = [CIContextTextSanitizer
            textFromAccessibilityText:@"Nel Ofir: 12:04 PM. \u2067בכיף\u2069."
                    elementIdentifier:nil
                      applicationName:@"Slack"];
        CIExpect([slackLogicalOrderHebrewMessage isEqualToString:@"בכיף"],
                 @"Slack's logical timestamp order and bidi markers are stripped");

        NSString *slackLogicalOrderEnglishMessage = [CIContextTextSanitizer
            textFromAccessibilityText:@"Nel Ofir: 12:04 PM. Sounds good."
                    elementIdentifier:nil
                      applicationName:@"Slack"];
        CIExpect([slackLogicalOrderEnglishMessage isEqualToString:@"Sounds good"],
                 @"Slack's English message body is preserved without author metadata");

        NSString *explicitPlaceholder = [CIDraftSanitizer
            draftFromAccessibilityValue:@"Do anything"
                       placeholderValue:@"Do anything"
                     numberOfCharacters:nil
                        applicationName:@"ChatGPT"];
        CIExpect(explicitPlaceholder == nil, @"explicit placeholder is not a draft");

        NSString *zeroLengthPlaceholder = [CIDraftSanitizer
            draftFromAccessibilityValue:@"Localized placeholder"
                       placeholderValue:nil
                     numberOfCharacters:@0
                        applicationName:@"Some app"];
        CIExpect(zeroLengthPlaceholder == nil, @"zero editable characters identifies placeholder text");

        NSString *chatGPTPlaceholder = [CIDraftSanitizer
            draftFromAccessibilityValue:@"Do anything"
                       placeholderValue:nil
                     numberOfCharacters:@11
                        applicationName:@"ChatGPT"];
        CIExpect(chatGPTPlaceholder == nil, @"ChatGPT synthesized AXValue is not a draft");

        NSString *realDraft = [CIDraftSanitizer
            draftFromAccessibilityValue:@"An actual reply"
                       placeholderValue:nil
                     numberOfCharacters:@15
                        applicationName:@"ChatGPT"];
        CIExpect([realDraft isEqualToString:@"An actual reply"], @"real draft remains authoritative");

        NSString *sameWordsElsewhere = [CIDraftSanitizer
            draftFromAccessibilityValue:@"Do anything"
                       placeholderValue:nil
                     numberOfCharacters:@11
                        applicationName:@"Slack"];
        CIExpect([sameWordsElsewhere isEqualToString:@"Do anything"],
                 @"placeholder workaround stays scoped to ChatGPT and Codex");

        CILanguageDecision *hebrew = [classifier classifyText:@"אפשר לבדוק את זה עכשיו?"
                                                       reason:@"test"];
        CIExpect(hebrew.language == CIInputLanguageHebrew, @"detects Hebrew");
        CIExpect(hebrew.confidence >= 0.8, @"Hebrew confidence is high");

        CILanguageDecision *english = [classifier classifyText:@"Can you check this now?"
                                                        reason:@"test"];
        CIExpect(english.language == CIInputLanguageEnglish, @"detects English");
        CIExpect(english.confidence >= 0.8, @"English confidence is high");

        CILanguageDecision *linkedHebrew = [classifier
            classifyText:@"תבדוק בבקשה https://developer.apple.com/documentation"
                  reason:@"test"];
        CIExpect(linkedHebrew.language == CIInputLanguageHebrew, @"ignores URL text");

        CILanguageDecision *draft = [classifier
            classifyDraft:@"I already started an English reply"
               nearbyTexts:@[@"ההודעה האחרונה בעברית"]];
        CIExpect(draft.language == CIInputLanguageEnglish, @"existing draft wins");
        CIExpect([draft.reason isEqualToString:@"the existing draft"], @"draft reason is reported");

        CILanguageDecision *urlField = [classifier
            classifyDraft:@"https://ecom.gov.il/voucherspa/confirmation/209"
               nearbyTexts:@[@"אתר ממשלתי בעברית"]];
        CIExpect(urlField.language == CIInputLanguageEnglish, @"URL field value outranks Hebrew page text");
        CIExpect([urlField.reason isEqualToString:@"the existing field value"], @"URL fallback reason is reported");

        CILanguageDecision *hebrewDraftWithURL = [classifier
            classifyDraft:@"אפשר לבדוק https://developer.apple.com"
               nearbyTexts:@[@"An older English message"]];
        CIExpect(hebrewDraftWithURL.language == CIInputLanguageHebrew, @"URL does not dominate a Hebrew draft");

        CILanguageDecision *nearest = [classifier
            classifyDraft:nil
               nearbyTexts:@[
                   @"👍",
                   @"ההודעה הקרובה בעברית ומייצגת את המשך השיחה",
                   @"An older English message",
               ]];
        CIExpect(nearest.language == CIInputLanguageHebrew,
                 @"recent substantive message outweighs an older message");

        CILanguageDecision *hebrewConversation = [classifier
            classifyDraft:nil
               nearbyTexts:@[
                   @"Give feedback",
                   @"Open in",
                   @"Edited build_yagel_factcheck.py",
                   @"Worked for 15m 5s",
                   @"מוכן. יצרתי מסמך Word מלא הכולל בדיקה של כל הסעיפים, פירוש פשוט לכל סעיף ודירוג נכונות.",
                   @"המסמך מוכן?",
               ]];
        CIExpect(hebrewConversation.language == CIInputLanguageHebrew,
                 @"Hebrew conversation outranks nearby English UI and filenames");
        CIExpect([hebrewConversation.reason isEqualToString:@"the recent conversation context"],
                 @"conversation aggregation reason is reported");

        CILanguageDecision *englishConversation = [classifier
            classifyDraft:nil
               nearbyTexts:@[
                   @"משוב",
                   @"פתח",
                   @"The implementation is ready. I verified the debug build and the complete English conversation should select the English keyboard.",
                   @"Can you test the new version?",
               ]];
        CIExpect(englishConversation.language == CIInputLanguageEnglish,
                 @"English conversation outranks short Hebrew controls");

        CILanguageDecision *mixedWhatsAppConversation = [classifier
            classifyDraft:nil
               nearbyTexts:@[
                   @"😺 😺 😺 אריזה משפחתית",
                   @"Bae, Yarden, Yarden Hadar, אמא, You",
                   @"Yarden",
                   @"Today",
                   @"Bae Forwarded",
                   @"חיים שלי",
                   @"אמאאאא אני שרופה עליהם",
                   @"בחיי אני מתרגשת",
               ]];
        CIExpect(mixedWhatsAppConversation.language == CIInputLanguageHebrew,
                 @"Hebrew WhatsApp conversation outranks English names and labels");

        CILanguageDecision *shortHebrewWhatsAppConversation = [classifier
            classifyDraft:nil
               nearbyTexts:@[
                   @"אמא עבודה",
                   @"תקבל מייל לאישור",
                   @"סבבה",
                   @"עדכונים לפוליסה שלך בהראל אני משלמת על ביטוח תאונות אישיות על דו גלגלי סתם גם על ירדן",
                   @"מה את שולחת?",
                   @"Nelofir1@gmail.com",
                   @"ללוש מה המייל שלך?",
                   @"Thursday",
                   @"תודה",
                   @"במטוס מחכים להמריא",
                   @"יופי טיסה נעימה",
                   @"לא איפה אתם?",
               ]];
        CIExpect(shortHebrewWhatsAppConversation.language == CIInputLanguageHebrew,
                 @"many short Hebrew WhatsApp messages classify as Hebrew");

        CILanguageDecision *slackConversationWithEnglishAttachment = [classifier
            classifyDraft:nil
               nearbyTexts:@[
                   @"בכיף",
                   @"Nel Ofir",
                   @"אחלה תודה",
                   @"Hili Seker Amiel",
                   @"יש בעיית קליטה אז אם לא זמין אפשר בוואטסאפ",
                   @"0524631337",
                   @"מעולה תודה",
                   @"הכל טוב, אבקש ממנו",
                   @"אבל יש מצב שאתה מבקש ממנו טלפון שאני אוכל ליצור איתו קשר?",
                   @"Translate New",
                   @"Today",
                   @"Anton Nosovitsky is a Head of Data and Platform Leader specializing in building intelligent data platforms under strict constraints. Proven experience capturing evidence, architecting decisions, platform migrations, and cross-functional team leadership.",
                   @"PROFESSIONAL SUMMARY Head of Data and Platform Leader specializing in building intelligent data platforms under strict constraints. PROFESSIONAL EXPERIENCE CyberproAI, Raanana, Israel. Built the company's core data platform from zero to production within a year.",
                   @"Messages",
                   @"Add canvas",
                   @"Files and links",
                   @"Search RiverPool",
                   @"Message Hili Seker Amiel",
               ]];
        CIExpect(slackConversationWithEnglishAttachment.language == CIInputLanguageHebrew,
                 @"recent Hebrew Slack messages outrank an older English attachment and UI");

        CILanguageDecision *slackConversationBelowPausedNotice = [classifier
            classifyDraft:nil
               nearbyTexts:@[
                   @"Hili Seker Amiel",
                   @"בכיף",
                   @"Nel Ofir",
                   @"אחלה תודה",
                   @"יש בעיית קליטה אז אם לא זמין אפשר בוואטסאפ",
                   @"0524631337",
                   @"מעולה תודה",
                   @"הכל טוב, אבקש ממנו",
               ]];
        CIExpect(slackConversationBelowPausedNotice.language == CIInputLanguageHebrew,
                 @"Hebrew Slack messages win after a nearby status notice is removed");

        CILanguageDecision *metadataWeightedSlackConversation = [classifier
            classifyDraft:nil
               nearbyTexts:@[
                   @"Hili Seker Amiel",
                   @"Delivery status and notification settings",
                   @"בכיף",
                   @"Nel Ofir",
                   @"אחלה תודה",
                   @"הכל טוב, אבקש ממנו",
                   @"מעולה תודה",
                   @"יש בעיית קליטה אז אפשר לנסות שוב בוואטסאפ",
               ]];
        CIExpect(metadataWeightedSlackConversation.language == CIInputLanguageHebrew,
                 @"a clear Hebrew node consensus breaks a sub-80-percent metadata tie");

        CILanguageDecision *englishNodeConsensus = [classifier
            classifyDraft:nil
               nearbyTexts:@[
                   @"הילה כהן",
                   @"הגדרות התראות ופעולות נוספות",
                   @"Sounds good",
                   @"Thank you",
                   @"Please send it when it is ready",
                   @"I will call them now",
                   @"Perfect, talk soon",
               ]];
        CIExpect(englishNodeConsensus.language == CIInputLanguageEnglish,
                 @"the node-consensus tie-breaker protects English conversations symmetrically");

        CILanguageDecision *englishSlackConversationWithHebrewAttachment = [classifier
            classifyDraft:nil
               nearbyTexts:@[
                   @"Sounds good",
                   @"Nel Ofir",
                   @"Thank you, I will call them now",
                   @"Hili Seker Amiel",
                   @"Please send me the phone number when you have it",
                   @"Perfect, thanks",
                   @"I could not reach them, so I will try WhatsApp",
                   @"Translate New",
                   @"Today",
                   @"You are welcome",
                   @"מסמך מצורף ארוך בעברית שמתאר פרויקט, ניסיון מקצועי, תהליכי עבודה, החלטות ארכיטקטורה ותוצאות עסקיות. הטקסט הזה ישן יותר מההודעות האחרונות ולכן אסור לו לשנות את שפת התגובה הנוכחית.",
                   @"תקציר מקצועי ארוך בעברית עם פרטים רבים על ניסיון בניהול, פיתוח תוכנה, תשתיות נתונים ושיתוף פעולה בין צוותים. זהו תוכן של קובץ מצורף ולא ההודעה האחרונה בשיחה.",
               ]];
        CIExpect(englishSlackConversationWithHebrewAttachment.language == CIInputLanguageEnglish,
                 @"recent English Slack messages outrank an older Hebrew attachment");

        CILanguageDecision *emoji = [classifier classifyText:@"👍 🎉" reason:@"test"];
        CIExpect(emoji == nil, @"emoji-only text is ambiguous");

        if (failures == 0) {
            puts("All classifier tests passed.");
        }
    }
    return (int)failures;
}
