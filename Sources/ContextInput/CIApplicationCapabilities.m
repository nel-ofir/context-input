#import "CIApplicationCapabilities.h"
#import <AppKit/AppKit.h>

@implementation CIApplicationCapabilities

+ (BOOL)infoDictionaryDeclaresTerminalSupport:(NSDictionary *)infoDictionary {
    NSString *category = [infoDictionary[@"LSApplicationCategoryType"]
        isKindOfClass:NSString.class]
        ? infoDictionary[@"LSApplicationCategoryType"]
        : nil;
    BOOL terminalCategory = [@[
        @"public.app-category.developer-tools",
        @"public.app-category.utilities",
    ] containsObject:category];
    if (!terminalCategory) {
        return NO;
    }

    id documentTypesObject = infoDictionary[@"CFBundleDocumentTypes"];
    if (![documentTypesObject isKindOfClass:NSArray.class]) {
        return NO;
    }

    for (id documentTypeObject in (NSArray *)documentTypesObject) {
        if (![documentTypeObject isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSDictionary *documentType = (NSDictionary *)documentTypeObject;
        id roleObject = documentType[@"CFBundleTypeRole"];
        if ([roleObject isKindOfClass:NSString.class] &&
            [(NSString *)roleObject localizedCaseInsensitiveCompare:@"Shell"] == NSOrderedSame) {
            return YES;
        }

        id contentTypesObject = documentType[@"LSItemContentTypes"];
        if (![contentTypesObject isKindOfClass:NSArray.class]) {
            continue;
        }
        for (id contentTypeObject in (NSArray *)contentTypesObject) {
            if ([contentTypeObject isKindOfClass:NSString.class] &&
                [(NSString *)contentTypeObject isEqualToString:@"com.apple.terminal.shell-script"]) {
                return YES;
            }
        }
    }
    return NO;
}

+ (BOOL)applicationDeclaresTerminalSupport:(NSRunningApplication *)application {
    if (application.bundleURL == nil) {
        return NO;
    }
    NSBundle *bundle = [NSBundle bundleWithURL:application.bundleURL];
    return bundle != nil && [self infoDictionaryDeclaresTerminalSupport:bundle.infoDictionary];
}

+ (BOOL)isOpaqueAccessibilityRole:(NSString *)role {
    if (role.length == 0) {
        return YES;
    }
    return [@[
        @"AXApplication",
        @"AXWindow",
        @"AXGroup",
        @"AXUnknown",
        @"AXScrollArea",
        @"AXWebArea",
        @"AXSplitGroup",
        @"AXLayoutArea",
        @"AXLayoutItem",
    ] containsObject:role];
}

@end
