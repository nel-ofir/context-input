#import "CILanguageClassifier.h"
#import <NaturalLanguage/NaturalLanguage.h>
#import <math.h>

@interface CILanguageClassifier ()
- (CILanguageDecision *)classifyText:(NSString *)text
                              reason:(NSString *)reason
                          stripLinks:(BOOL)stripLinks;
- (CILanguageDecision *)classifyConversationTexts:(NSArray<NSString *> *)nearbyTexts;
- (CILanguageDecision *)classifyRepeatedMessageBodies:(NSArray<NSString *> *)nearbyTexts;
- (CILanguageDecision *)classifyConversationTexts:(NSArray<NSString *> *)nearbyTexts
                                             limit:(NSUInteger)limit
                                 minimumConfidence:(double)minimumConfidence;
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
    CILanguageDecision *messageBodyDecision = [self classifyRepeatedMessageBodies:nearbyTexts];
    if (messageBodyDecision != nil) {
        return messageBodyDecision;
    }

    // Accessibility APIs often expose attachments, link previews, or documents as
    // very large text nodes. First ask whether the geometrically nearest context is
    // already decisive. This models how a person chooses the language from the latest
    // messages and prevents an older document from diluting a clear local consensus.
    NSUInteger recentLimit = nearbyTexts.count < 10 ? nearbyTexts.count : 10;
    CILanguageDecision *recentDecision = [self classifyConversationTexts:nearbyTexts
                                                                    limit:recentLimit
                                                        minimumConfidence:0.62];
    if (recentDecision != nil || nearbyTexts.count <= recentLimit) {
        return recentDecision;
    }

    // If the nearest items are mixed or mostly controls, use the wider context as a
    // fallback. The per-node cap below still prevents a single enormous container
    // from receiving unlimited influence.
    NSUInteger fullLimit = nearbyTexts.count < 32 ? nearbyTexts.count : 32;
    return [self classifyConversationTexts:nearbyTexts
                                     limit:fullLimit
                         minimumConfidence:0.55];
}

- (CILanguageDecision *)classifyRepeatedMessageBodies:(NSArray<NSString *> *)nearbyTexts {
    NSUInteger hebrewBodies = 0;
    NSUInteger englishBodies = 0;
    NSString *hebrewEvidence = nil;
    NSString *englishEvidence = nil;
    NSUInteger limit = nearbyTexts.count < 32 ? nearbyTexts.count : 32;

    for (NSUInteger childIndex = 0; childIndex < limit; childIndex++) {
        NSString *child = [self sanitizedText:nearbyTexts[childIndex] stripLinks:YES];
        NSUInteger childHebrew = 0;
        NSUInteger childLatin = 0;
        [self countScriptsInText:child hebrew:&childHebrew latin:&childLatin];
        NSUInteger childLetters = childHebrew + childLatin;
        if (childLetters < 3 || child.length > 500) {
            continue;
        }
        double childHebrewShare = (double)childHebrew / (double)childLetters;
        double childEnglishShare = (double)childLatin / (double)childLetters;
        if (childHebrewShare < 0.80 && childEnglishShare < 0.80) {
            continue;
        }

        for (NSUInteger parentIndex = 0; parentIndex < limit; parentIndex++) {
            if (parentIndex == childIndex) {
                continue;
            }
            NSString *parent = [self sanitizedText:nearbyTexts[parentIndex] stripLinks:YES];
            if (parent.length < child.length + 8 ||
                [parent rangeOfString:@"\\b\\d{1,2}:\\d{2}\\b"
                              options:NSRegularExpressionSearch].location == NSNotFound) {
                continue;
            }
            NSRange childRange = [parent rangeOfString:child
                                               options:NSCaseInsensitiveSearch];
            // Timestamped wrappers begin with the author. A repeated leaf at the
            // beginning is metadata; a later repeated leaf is the message body.
            if (childRange.location == NSNotFound || childRange.location == 0) {
                continue;
            }
            if (childHebrewShare >= 0.80) {
                hebrewBodies += 1;
                if (hebrewEvidence == nil) hebrewEvidence = child;
            } else {
                englishBodies += 1;
                if (englishEvidence == nil) englishEvidence = child;
            }
            break;
        }
    }

    NSUInteger bodyCount = hebrewBodies + englishBodies;
    if (bodyCount < 2 || hebrewBodies == englishBodies) {
        return nil;
    }
    CIInputLanguage language = hebrewBodies > englishBodies
        ? CIInputLanguageHebrew
        : CIInputLanguageEnglish;
    NSUInteger winningBodies = hebrewBodies > englishBodies
        ? hebrewBodies
        : englishBodies;
    double confidence = (double)winningBodies / (double)bodyCount;
    if (confidence < 0.60) {
        return nil;
    }
    NSString *evidence = language == CIInputLanguageHebrew
        ? hebrewEvidence
        : englishEvidence;
    return [[CILanguageDecision alloc]
        initWithLanguage:language
              confidence:confidence
                evidence:[self previewForText:evidence]
                  reason:@"the repeated message bodies"];
}

- (CILanguageDecision *)classifyConversationTexts:(NSArray<NSString *> *)nearbyTexts
                                             limit:(NSUInteger)limit
                                 minimumConfidence:(double)minimumConfidence {
    double hebrewEvidence = 0;
    double englishEvidence = 0;
    double strongestHebrewEvidence = 0;
    double strongestEnglishEvidence = 0;
    NSString *strongestHebrewText = nil;
    NSString *strongestEnglishText = nil;
    NSUInteger dominantHebrewItems = 0;
    NSUInteger dominantEnglishItems = 0;

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
        double codePenalty = [self codePenaltyForText:cleaned];
        double hebrewShare = (double)hebrewCount / (double)total;
        double englishShare = (double)latinCount / (double)total;
        double weight = cappedLetters * substanceMultiplier * recencyMultiplier * codePenalty;
        double candidateHebrew = weight * hebrewShare;
        double candidateEnglish = weight * englishShare;
        hebrewEvidence += candidateHebrew;
        englishEvidence += candidateEnglish;

        // Distinct message-sized nodes are a useful guard against metadata-heavy
        // wrappers. Only clear, non-code single-script items vote here; names or
        // controls in the other script must be outnumbered by at least two items.
        if (codePenalty >= 0.5 && hebrewShare >= 0.80) {
            dominantHebrewItems += 1;
        } else if (codePenalty >= 0.5 && englishShare >= 0.80) {
            dominantEnglishItems += 1;
        }

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
    NSUInteger dominantItemCount = dominantHebrewItems + dominantEnglishItems;
    BOOL hebrewNodeConsensus = dominantHebrewItems >= 3 &&
        dominantHebrewItems >= dominantEnglishItems + 2;
    BOOL englishNodeConsensus = dominantEnglishItems >= 3 &&
        dominantEnglishItems >= dominantHebrewItems + 2;
    if (confidence < 0.80 && (hebrewNodeConsensus || englishNodeConsensus)) {
        language = hebrewNodeConsensus ? CIInputLanguageHebrew : CIInputLanguageEnglish;
        NSUInteger winningItems = hebrewNodeConsensus
            ? dominantHebrewItems
            : dominantEnglishItems;
        confidence = dominantItemCount > 0
            ? (double)winningItems / (double)dominantItemCount
            : confidence;
    }
    if (confidence < minimumConfidence) {
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
