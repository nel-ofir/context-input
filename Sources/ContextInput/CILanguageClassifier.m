#import "CILanguageClassifier.h"
#import <NaturalLanguage/NaturalLanguage.h>
#import <math.h>

@interface CILanguageClassifier ()
- (CILanguageDecision *)classifyText:(NSString *)text
                              reason:(NSString *)reason
                          stripLinks:(BOOL)stripLinks;
- (CILanguageDecision *)classifyConversationTexts:(NSArray<NSString *> *)nearbyTexts;
- (NSString *)sanitizedText:(NSString *)text stripLinks:(BOOL)stripLinks;
- (void)countScriptsInText:(NSString *)text hebrew:(NSUInteger *)hebrew latin:(NSUInteger *)latin;
- (double)codePenaltyForText:(NSString *)text;
- (NSString *)previewForText:(NSString *)text;
@end

@implementation CILanguageClassifier

- (CILanguageDecision *)classifyDraft:(NSString *)draft
                           nearbyTexts:(NSArray<NSString *> *)nearbyTexts {
    if (draft.length > 0) {
        CILanguageDecision *draftDecision = [self classifyText:draft
                                                         reason:@"the existing draft"
                                                     stripLinks:YES];
        // A URL bar or an email-only field becomes empty after link stripping. In that
        // case the field's own Latin characters are still decisive and outrank the page.
        if (draftDecision == nil) {
            draftDecision = [self classifyText:draft
                                         reason:@"the existing field value"
                                     stripLinks:NO];
        }
        if (draftDecision != nil) {
            return draftDecision;
        }
    }

    return [self classifyConversationTexts:nearbyTexts];
}

- (CILanguageDecision *)classifyText:(NSString *)text reason:(NSString *)reason {
    return [self classifyText:text reason:reason stripLinks:YES];
}

- (CILanguageDecision *)classifyText:(NSString *)text
                              reason:(NSString *)reason
                          stripLinks:(BOOL)stripLinks {
    NSString *cleaned = [self sanitizedText:text stripLinks:stripLinks];
    NSUInteger hebrewCount = 0;
    NSUInteger latinCount = 0;
    [self countScriptsInText:cleaned hebrew:&hebrewCount latin:&latinCount];

    NSUInteger total = hebrewCount + latinCount;
    if (total < 2) {
        return nil;
    }

    double hebrewShare = (double)hebrewCount / (double)total;
    double englishShare = (double)latinCount / (double)total;

    NLLanguageRecognizer *recognizer = [[NLLanguageRecognizer alloc] init];
    recognizer.languageConstraints = @[NLLanguageHebrew, NLLanguageEnglish];
    [recognizer processString:cleaned];
    NSDictionary<NLLanguage, NSNumber *> *hypotheses = [recognizer languageHypothesesWithMaximum:2];
    double modelHebrew = hypotheses[NLLanguageHebrew].doubleValue;
    double modelEnglish = hypotheses[NLLanguageEnglish].doubleValue;

    // Script is the primary signal because Hebrew and English have distinct scripts.
    // Apple's local model is a secondary signal for mixed text and short edge cases.
    double hebrewScore = (0.78 * hebrewShare) + (0.22 * modelHebrew);
    double englishScore = (0.78 * englishShare) + (0.22 * modelEnglish);
    CIInputLanguage language = hebrewScore > englishScore
        ? CIInputLanguageHebrew
        : CIInputLanguageEnglish;
    double scriptConfidence = fmax(hebrewShare, englishShare);
    double modelConfidence = fmax(modelHebrew, modelEnglish);
    double combinedConfidence = (0.78 * scriptConfidence) + (0.22 * modelConfidence);
    double confidence = fmin(1.0, fmax(scriptConfidence, combinedConfidence));
    if (confidence < 0.55) {
        return nil;
    }

    NSString *evidence = [self previewForText:cleaned];
    return [[CILanguageDecision alloc] initWithLanguage:language
                                             confidence:confidence
                                               evidence:evidence
                                                 reason:reason];
}

- (CILanguageDecision *)classifyConversationTexts:(NSArray<NSString *> *)nearbyTexts {
    double hebrewEvidence = 0;
    double englishEvidence = 0;
    double strongestHebrewEvidence = 0;
    double strongestEnglishEvidence = 0;
    NSString *strongestHebrewText = nil;
    NSString *strongestEnglishText = nil;
    NSUInteger limit = nearbyTexts.count < 32 ? nearbyTexts.count : 32;

    for (NSUInteger index = 0; index < limit; index++) {
        NSString *cleaned = [self sanitizedText:nearbyTexts[index] stripLinks:YES];
        NSUInteger hebrewCount = 0;
        NSUInteger latinCount = 0;
        [self countScriptsInText:cleaned hebrew:&hebrewCount latin:&latinCount];
        NSUInteger total = hebrewCount + latinCount;
        if (total < 2) {
            continue;
        }

        // Cap each accessibility node so a huge older container cannot overwhelm
        // several newer messages. Short controls are deliberately weak evidence.
        double cappedLetters = total < 240 ? (double)total : 240.0;
        double substanceMultiplier = 1.0;
        if (total < 8) {
            substanceMultiplier = 0.18;
        } else if (total < 18) {
            substanceMultiplier = 0.35;
        } else if (total < 40) {
            substanceMultiplier = 0.70;
        }
        double recencyMultiplier = 1.0 / (1.0 + (0.07 * (double)index));
        double weight = cappedLetters * substanceMultiplier * recencyMultiplier *
            [self codePenaltyForText:cleaned];
        double candidateHebrew = weight * ((double)hebrewCount / (double)total);
        double candidateEnglish = weight * ((double)latinCount / (double)total);
        hebrewEvidence += candidateHebrew;
        englishEvidence += candidateEnglish;

        if (candidateHebrew > strongestHebrewEvidence) {
            strongestHebrewEvidence = candidateHebrew;
            strongestHebrewText = cleaned;
        }
        if (candidateEnglish > strongestEnglishEvidence) {
            strongestEnglishEvidence = candidateEnglish;
            strongestEnglishText = cleaned;
        }
    }

    double totalEvidence = hebrewEvidence + englishEvidence;
    if (totalEvidence < 2) {
        return nil;
    }
    CIInputLanguage language = hebrewEvidence > englishEvidence
        ? CIInputLanguageHebrew
        : CIInputLanguageEnglish;
    double winningEvidence = fmax(hebrewEvidence, englishEvidence);
    double confidence = winningEvidence / totalEvidence;
    if (confidence < 0.55) {
        return nil;
    }
    NSString *evidence = language == CIInputLanguageHebrew
        ? strongestHebrewText
        : strongestEnglishText;
    if (evidence.length == 0) {
        return nil;
    }
    return [[CILanguageDecision alloc]
        initWithLanguage:language
              confidence:confidence
                evidence:[self previewForText:evidence]
                  reason:@"the recent conversation context"];
}

- (void)countScriptsInText:(NSString *)text hebrew:(NSUInteger *)hebrew latin:(NSUInteger *)latin {
    *hebrew = 0;
    *latin = 0;
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if ((character >= 0x05D0 && character <= 0x05EA) ||
            (character >= 0x05F0 && character <= 0x05F2) ||
            (character >= 0xFB1D && character <= 0xFB4F)) {
            *hebrew += 1;
        } else if ((character >= 'A' && character <= 'Z') ||
                   (character >= 'a' && character <= 'z') ||
                   (character >= 0x00C0 && character <= 0x024F)) {
            *latin += 1;
        }
    }
}

- (double)codePenaltyForText:(NSString *)text {
    if ([text containsString:@"_"] || [text containsString:@"/"] ||
        [text rangeOfString:@"\\.(py|js|ts|swift|m|h|json|md|docx|pdf|html|css)\\b"
                    options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) {
        return 0.16;
    }

    NSUInteger letters = 0;
    NSUInteger codeMarkers = 0;
    NSCharacterSet *letterSet = NSCharacterSet.letterCharacterSet;
    NSCharacterSet *markerSet = [NSCharacterSet characterSetWithCharactersInString:@"{}[]()<>=;:$#%+*|\\`~0123456789"];
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if ([letterSet characterIsMember:character]) {
            letters += 1;
        } else if ([markerSet characterIsMember:character]) {
            codeMarkers += 1;
        }
    }
    if (letters > 0 && (double)codeMarkers / (double)letters > 0.45) {
        return 0.28;
    }
    return 1.0;
}

- (NSString *)previewForText:(NSString *)text {
    return text.length <= 180
        ? text
        : [[text substringToIndex:180] stringByAppendingString:@"…"];
}

- (NSString *)sanitizedText:(NSString *)text stripLinks:(BOOL)stripLinks {
    NSString *withoutLinks = text;
    if (stripLinks) {
        withoutLinks = [text stringByReplacingOccurrencesOfString:@"https?://\\S+|www\\.\\S+|\\b\\S+@\\S+\\b"
                                                       withString:@" "
                                                          options:NSRegularExpressionSearch | NSCaseInsensitiveSearch
                                                            range:NSMakeRange(0, text.length)];
    }
    NSString *collapsed = [withoutLinks stringByReplacingOccurrencesOfString:@"\\s+"
                                                                   withString:@" "
                                                                      options:NSRegularExpressionSearch
                                                                        range:NSMakeRange(0, withoutLinks.length)];
    return [collapsed stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

@end
