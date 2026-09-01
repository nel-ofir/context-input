#import "CIInputSourceManager.h"
#import <Carbon/Carbon.h>

NSErrorDomain const CIInputSourceErrorDomain = @"com.contextinput.input-source";

@implementation CIInputSourceManager

- (NSArray<CIKeyboardInputSource *> *)availableKeyboardSources {
    NSMutableArray<CIKeyboardInputSource *> *results = [NSMutableArray array];
    for (id rawSource in [self selectableSources]) {
        TISInputSourceRef source = (__bridge TISInputSourceRef)rawSource;
        CIKeyboardInputSource *converted = [self keyboardSourceFromTISSource:source];
        if (converted != nil) {
            [results addObject:converted];
        }
    }

    [results sortUsingComparator:^NSComparisonResult(CIKeyboardInputSource *left,
                                                       CIKeyboardInputSource *right) {
        NSComparisonResult nameResult = [left.name localizedCaseInsensitiveCompare:right.name];
        return nameResult == NSOrderedSame
            ? [left.identifier compare:right.identifier]
            : nameResult;
    }];
    return results;
}

- (CIKeyboardInputSource *)currentSource {
    TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
    if (source == NULL) {
        return nil;
    }
    CIKeyboardInputSource *result = [self keyboardSourceFromTISSource:source];
    CFRelease(source);
    return result;
}

- (NSString *)bestSourceIdentifierForLanguage:(CIInputLanguage)language
                                       sources:(NSArray<CIKeyboardInputSource *> *)sources {
    NSString *code = language == CIInputLanguageHebrew ? @"he" : @"en";
    for (CIKeyboardInputSource *source in sources) {
        for (NSString *sourceLanguage in source.languages) {
            if ([[sourceLanguage lowercaseString] hasPrefix:code]) {
                return source.identifier;
            }
        }
    }

    NSArray<NSString *> *hints = language == CIInputLanguageHebrew
        ? @[@"hebrew", @".he", @"israel"]
        : @[@"abc", @".us", @"british", @"english"];
    for (CIKeyboardInputSource *source in sources) {
        NSString *searchable = [[NSString stringWithFormat:@"%@ %@", source.identifier, source.name] lowercaseString];
        for (NSString *hint in hints) {
            if ([searchable containsString:hint]) {
                return source.identifier;
            }
        }
    }
    return nil;
}

- (BOOL)selectSourceIdentifier:(NSString *)identifier error:(NSError **)error {
    for (id rawSource in [self selectableSources]) {
        TISInputSourceRef source = (__bridge TISInputSourceRef)rawSource;
        NSString *sourceIdentifier = [self propertyForSource:source key:kTISPropertyInputSourceID];
        if (![sourceIdentifier isEqualToString:identifier]) {
            continue;
        }

        OSStatus status = TISSelectInputSource(source);
        if (status == noErr) {
            return YES;
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:CIInputSourceErrorDomain
                                         code:CIInputSourceErrorSelectionFailed
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"macOS could not select the keyboard input source (status %d).", (int)status]
            }];
        }
        return NO;
    }

    if (error != NULL) {
        *error = [NSError errorWithDomain:CIInputSourceErrorDomain
                                     code:CIInputSourceErrorSourceNotFound
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"The selected keyboard input source is no longer available."
        }];
    }
    return NO;
}

- (NSArray *)selectableSources {
    CFArrayRef copied = TISCreateInputSourceList(NULL, false);
    if (copied == NULL) {
        return @[];
    }
    NSArray *allSources = CFBridgingRelease(copied);
    NSMutableArray *selectable = [NSMutableArray array];

    for (id rawSource in allSources) {
        TISInputSourceRef source = (__bridge TISInputSourceRef)rawSource;
        NSNumber *canSelect = [self propertyForSource:source key:kTISPropertyInputSourceIsSelectCapable];
        NSNumber *enabled = [self propertyForSource:source key:kTISPropertyInputSourceIsEnabled];
        NSString *category = [self propertyForSource:source key:kTISPropertyInputSourceCategory];
        if (canSelect.boolValue && enabled.boolValue &&
            [category isEqualToString:(__bridge NSString *)kTISCategoryKeyboardInputSource]) {
            [selectable addObject:rawSource];
        }
    }
    return selectable;
}

- (CIKeyboardInputSource *)keyboardSourceFromTISSource:(TISInputSourceRef)source {
    NSString *identifier = [self propertyForSource:source key:kTISPropertyInputSourceID];
    if (identifier.length == 0) {
        return nil;
    }
    NSString *name = [self propertyForSource:source key:kTISPropertyLocalizedName];
    name = name != nil ? name : identifier;
    NSArray<NSString *> *languages = [self propertyForSource:source key:kTISPropertyInputSourceLanguages];
    languages = languages != nil ? languages : @[];
    return [[CIKeyboardInputSource alloc] initWithIdentifier:identifier name:name languages:languages];
}

- (id)propertyForSource:(TISInputSourceRef)source key:(CFStringRef)key {
    void *value = TISGetInputSourceProperty(source, key);
    return value == NULL ? nil : (__bridge id)value;
}

@end
