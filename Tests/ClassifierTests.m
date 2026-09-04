#import <Foundation/Foundation.h>
#import "CIApplicationCapabilities.h"
#import "CIContextTextSanitizer.h"
#import "CIDraftSanitizer.h"
#import "CILanguageClassifier.h"

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

        NSDictionary *shellRoleApplication = @{
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

        CILanguageDecision *emoji = [classifier classifyText:@"👍 🎉" reason:@"test"];
        CIExpect(emoji == nil, @"emoji-only text is ambiguous");

        if (failures == 0) {
            puts("All classifier tests passed.");
        }
    }
    return (int)failures;
}
