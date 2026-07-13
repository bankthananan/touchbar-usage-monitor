#import "TUMParsers.h"
#import "TUMModels.h"

static NSString *const TUMParserErrorDomain = @"TUMParserErrorDomain";

static NSError *TUMParserError(NSString *description) {
    return [NSError errorWithDomain:TUMParserErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static NSDate *TUMDateFromValue(id value) {
    if ([value isKindOfClass:NSNumber.class]) {
        return [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
    }
    if (![value isKindOfClass:NSString.class]) {
        return nil;
    }

    NSString *text = value;
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                              NSISO8601DateFormatWithFractionalSeconds;
    NSDate *date = [formatter dateFromString:text];
    if (date == nil) {
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        date = [formatter dateFromString:text];
    }
    return date;
}

static NSDictionary *TUMDictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static TUMWindowUsage *TUMClaudeWindow(NSDictionary *dictionary,
                                       NSInteger windowMinutes) {
    if (dictionary == nil) {
        return [TUMWindowUsage unavailableWithNote:nil];
    }
    NSNumber *utilization = [dictionary[@"utilization"] isKindOfClass:NSNumber.class]
        ? dictionary[@"utilization"]
        : nil;
    if (utilization == nil) {
        return [TUMWindowUsage unavailableWithNote:nil];
    }
    double used = utilization.doubleValue;
    if (used <= 1.0) {
        used *= 100.0;
    }
    return [TUMWindowUsage windowWithUsedPercent:used
                                   windowMinutes:windowMinutes
                                       resetDate:TUMDateFromValue(dictionary[@"resets_at"])];
}

TUMProviderUsage *TUMParseClaudeUsageJSON(NSData *data, NSError **error) {
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    NSDictionary *root = TUMDictionary(json);
    if (root == nil) {
        if (error != NULL && *error == nil) {
            *error = TUMParserError(@"Claude usage response is not a JSON object.");
        }
        return nil;
    }

    TUMProviderUsage *usage = [TUMProviderUsage usageForProviderID:@"claude"
                                                       displayName:@"Claude"];
    usage.fiveHour = TUMClaudeWindow(TUMDictionary(root[@"five_hour"]), 300);
    usage.sevenDay = TUMClaudeWindow(TUMDictionary(root[@"seven_day"]), 10080);
    if (!usage.fiveHour.available && !usage.sevenDay.available) {
        if (error != NULL) {
            *error = TUMParserError(@"Claude response contains no 5-hour or 7-day usage.");
        }
        return nil;
    }
    return usage;
}

static TUMWindowUsage *TUMCodexWindow(NSDictionary *dictionary) {
    NSNumber *used = [dictionary[@"usedPercent"] isKindOfClass:NSNumber.class]
        ? dictionary[@"usedPercent"]
        : dictionary[@"used_percent"];
    NSNumber *minutes = [dictionary[@"windowDurationMins"] isKindOfClass:NSNumber.class]
        ? dictionary[@"windowDurationMins"]
        : dictionary[@"window_minutes"];
    id resetValue = dictionary[@"resetsAt"] != nil
        ? dictionary[@"resetsAt"]
        : dictionary[@"resets_at"];
    if (![used isKindOfClass:NSNumber.class] || ![minutes isKindOfClass:NSNumber.class]) {
        return [TUMWindowUsage unavailableWithNote:nil];
    }
    return [TUMWindowUsage windowWithUsedPercent:used.doubleValue
                                   windowMinutes:minutes.integerValue
                                       resetDate:TUMDateFromValue(resetValue)];
}

TUMProviderUsage *TUMParseCodexRateLimitJSON(NSData *data, NSError **error) {
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    NSDictionary *root = TUMDictionary(json);
    NSDictionary *result = TUMDictionary(root[@"result"]);
    id limitsValue = result[@"rateLimits"] != nil
        ? result[@"rateLimits"]
        : root[@"rate_limits"];
    NSDictionary *limits = TUMDictionary(limitsValue);
    if (limits == nil) {
        if (error != NULL && *error == nil) {
            *error = TUMParserError(@"Codex response contains no rate limits.");
        }
        return nil;
    }

    TUMProviderUsage *usage = [TUMProviderUsage usageForProviderID:@"codex"
                                                       displayName:@"Codex"];
    NSArray *windows = @[
        TUMCodexWindow(TUMDictionary(limits[@"primary"])),
        TUMCodexWindow(TUMDictionary(limits[@"secondary"]))
    ];
    for (TUMWindowUsage *window in windows) {
        if (!window.available) {
            continue;
        }
        if (window.windowMinutes <= 360) {
            usage.fiveHour = window;
        } else if (window.windowMinutes >= 24 * 60) {
            usage.sevenDay = window;
        }
    }
    if (!usage.fiveHour.available && !usage.sevenDay.available) {
        if (error != NULL) {
            *error = TUMParserError(@"Codex response has no recognized quota windows.");
        }
        return nil;
    }
    return usage;
}

NSString *TUMStripTerminalControlSequences(NSString *input) {
    NSMutableString *result = [input mutableCopy];
    NSArray<NSString *> *patterns = @[
        @"\\x1B\\[[0-?]*[ -/]*[@-~]",
        @"\\x1B\\][^\\x07]*(?:\\x07|\\x1B\\\\)",
        @"\\x1B[=>]",
        @"\\r"
    ];
    for (NSString *pattern in patterns) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                                options:0
                                                                                  error:nil];
        [regex replaceMatchesInString:result
                              options:0
                                range:NSMakeRange(0, result.length)
                         withTemplate:@""];
    }
    return result;
}

NSTimeInterval TUMParseCountdown(NSString *input) {
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"(?:(\\d+)d)?\\s*(?:(\\d+)h)?\\s*(?:(\\d+)m)?"
        options:NSRegularExpressionCaseInsensitive
        error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:input
                                                   options:0
                                                     range:NSMakeRange(0, input.length)];
    if (match == nil || match.range.length == 0) {
        return 0;
    }
    NSInteger (^component)(NSInteger) = ^NSInteger(NSInteger index) {
        NSRange range = [match rangeAtIndex:index];
        return range.location == NSNotFound
            ? 0
            : [[input substringWithRange:range] integerValue];
    };
    return (component(1) * 24 * 60 * 60) +
           (component(2) * 60 * 60) +
           (component(3) * 60);
}

static NSString *TUMSection(NSString *text,
                            NSString *startHeading,
                            NSString *_Nullable endHeading) {
    NSRange start = [text rangeOfString:startHeading options:NSCaseInsensitiveSearch];
    if (start.location == NSNotFound) {
        return nil;
    }
    NSUInteger location = NSMaxRange(start);
    NSUInteger length = text.length - location;
    if (endHeading != nil) {
        NSRange searchRange = NSMakeRange(location, length);
        NSRange end = [text rangeOfString:endHeading
                                  options:NSCaseInsensitiveSearch
                                    range:searchRange];
        if (end.location != NSNotFound) {
            length = end.location - location;
        }
    }
    return [text substringWithRange:NSMakeRange(location, length)];
}

static NSString *TUMSectionFromLastHeading(NSString *text,
                                           NSString *startHeading,
                                           NSString *_Nullable endHeading) {
    NSRange start = [text rangeOfString:startHeading
                                options:NSCaseInsensitiveSearch | NSBackwardsSearch];
    if (start.location == NSNotFound) {
        return nil;
    }
    NSUInteger location = NSMaxRange(start);
    NSUInteger length = text.length - location;
    if (endHeading != nil) {
        NSRange end = [text rangeOfString:endHeading
                                  options:NSCaseInsensitiveSearch
                                    range:NSMakeRange(location, length)];
        if (end.location != NSNotFound) {
            length = end.location - location;
        }
    }
    return [text substringWithRange:NSMakeRange(location, length)];
}

static TUMWindowUsage *TUMAntigravityWindow(NSString *group,
                                            NSString *heading,
                                            NSString *_Nullable nextHeading,
                                            NSInteger windowMinutes,
                                            NSDate *now) {
    // The weekly heading comes from the first frame. Scrolling can repaint the
    // five-hour heading, so use its final copy to keep percentage/reset paired.
    NSString *section = nextHeading == nil
        ? TUMSectionFromLastHeading(group, heading, nil)
        : TUMSection(group, heading, nextHeading);
    if (section == nil) {
        return [TUMWindowUsage unavailableWithNote:nil];
    }
    if ([section rangeOfString:@"Disabled:" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return [TUMWindowUsage unavailableWithNote:@"Disabled by weekly limit"];
    }
    if ([section rangeOfString:@"Quota available" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return [TUMWindowUsage windowWithUsedPercent:0
                                       windowMinutes:windowMinutes
                                           resetDate:nil];
    }

    NSRegularExpression *percentRegex = [NSRegularExpression
        regularExpressionWithPattern:@"(\\d+(?:\\.\\d+)?)%"
        options:0
        error:nil];
    NSTextCheckingResult *percentMatch = [percentRegex firstMatchInString:section
                                                                  options:0
                                                                    range:NSMakeRange(0, section.length)];
    if (percentMatch == nil) {
        return [TUMWindowUsage unavailableWithNote:nil];
    }
    double remaining = [[section substringWithRange:[percentMatch rangeAtIndex:1]] doubleValue];

    NSDate *resetDate = nil;
    NSRegularExpression *resetRegex = [NSRegularExpression
        regularExpressionWithPattern:@"Refreshes in\\s+([0-9dhm ]+)"
        options:NSRegularExpressionCaseInsensitive
        error:nil];
    NSTextCheckingResult *resetMatch = [resetRegex firstMatchInString:section
                                                              options:0
                                                                range:NSMakeRange(0, section.length)];
    if (resetMatch != nil) {
        NSTimeInterval countdown = TUMParseCountdown(
            [section substringWithRange:[resetMatch rangeAtIndex:1]]
        );
        if (countdown > 0) {
            resetDate = [now dateByAddingTimeInterval:countdown];
        }
    }
    return [TUMWindowUsage windowWithUsedPercent:(100.0 - remaining)
                                   windowMinutes:windowMinutes
                                       resetDate:resetDate];
}

TUMProviderUsage *TUMParseAntigravityOutput(NSString *output,
                                            NSDate *now,
                                            NSError **error) {
    NSString *text = TUMStripTerminalControlSequences(output);
    NSString *group = TUMSection(text, @"CLAUDE AND GPT MODELS", @"Within each group");
    if (group == nil ||
        [group rangeOfString:@"Weekly Limit" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        group = TUMSection(text, @"GEMINI MODELS", @"CLAUDE AND GPT MODELS");
    }
    if (group == nil) {
        if (error != NULL) {
            *error = TUMParserError(@"Antigravity output contains no quota group.");
        }
        return nil;
    }

    TUMProviderUsage *usage = [TUMProviderUsage usageForProviderID:@"antigravity"
                                                       displayName:@"Antigravity"];
    usage.sevenDay = TUMAntigravityWindow(group,
                                          @"Weekly Limit",
                                          @"Five Hour Limit",
                                          10080,
                                          now);
    usage.fiveHour = TUMAntigravityWindow(group,
                                          @"Five Hour Limit",
                                          nil,
                                          300,
                                          now);
    if (!usage.fiveHour.available && !usage.sevenDay.available) {
        if (error != NULL) {
            *error = TUMParserError(@"Antigravity quota group has no readable windows.");
        }
        return nil;
    }
    return usage;
}
