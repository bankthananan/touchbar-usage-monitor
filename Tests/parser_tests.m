#import <Foundation/Foundation.h>

#import "TUMModels.h"
#import "TUMParsers.h"

static int failures = 0;

static void Assert(BOOL condition, NSString *message) {
    if (!condition) {
        failures += 1;
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    }
}

static NSData *JSONData(NSString *json) {
    return [json dataUsingEncoding:NSUTF8StringEncoding];
}

static void TestClaudeParser(void) {
    NSString *json = @"{\"five_hour\":{\"utilization\":0.42,\"resets_at\":\"2026-07-13T12:00:00Z\"},"
                     "\"seven_day\":{\"utilization\":0.61,\"resets_at\":\"2026-07-18T12:00:00Z\"},"
                     "\"seven_day_sonnet\":{\"utilization\":0.22,\"resets_at\":\"2026-07-17T12:00:00Z\"},"
                     "\"seven_day_opus\":{\"utilization\":0.73,\"resets_at\":\"2026-07-16T12:00:00Z\"},"
                     "\"seven_day_fable_5\":{\"utilization\":0.15,\"resets_at\":\"2026-07-15T12:00:00Z\"}}";
    NSError *error = nil;
    TUMProviderUsage *usage = TUMParseClaudeUsageJSON(JSONData(json), &error);
    Assert(usage != nil && error == nil, @"Claude parser returns usage");
    Assert(fabs(usage.fiveHour.usedPercent - 42.0) < 0.01, @"Claude 5H utilization normalized");
    Assert(fabs(usage.sevenDay.usedPercent - 61.0) < 0.01, @"Claude 7D utilization normalized");
    Assert(usage.fiveHour.resetDate != nil, @"Claude reset date parsed");
    Assert(usage.quotaGroups.count == 4, @"Claude optional model quota groups parsed");
    Assert([usage.quotaGroups[1].displayName isEqualToString:@"Sonnet"],
           @"Claude Sonnet group named");
    Assert([usage.quotaGroups[2].displayName isEqualToString:@"Opus"],
           @"Claude Opus group named");
    Assert([usage.quotaGroups[3].displayName isEqualToString:@"Fable 5"],
           @"Unknown Claude model group humanized");
    Assert(fabs(usage.quotaGroups[2].fiveHour.usedPercent - 42.0) < 0.01,
           @"Claude shared 5H session copied into model group");
}

static void TestCodexParser(void) {
    NSString *json = @"{\"id\":2,\"result\":{\"rateLimits\":{"
                     "\"primary\":{\"usedPercent\":18,\"windowDurationMins\":300,\"resetsAt\":1784000000},"
                     "\"secondary\":{\"usedPercent\":27,\"windowDurationMins\":10080,\"resetsAt\":1784500000}}}}";
    NSError *error = nil;
    TUMProviderUsage *usage = TUMParseCodexRateLimitJSON(JSONData(json), &error);
    Assert(usage != nil && error == nil, @"Codex parser returns usage");
    Assert(fabs(usage.fiveHour.usedPercent - 18.0) < 0.01, @"Codex 5H classified");
    Assert(fabs(usage.sevenDay.usedPercent - 27.0) < 0.01, @"Codex 7D classified");
}

static void TestCodexWeeklyOnly(void) {
    NSString *json = @"{\"id\":2,\"result\":{\"rateLimits\":{"
                     "\"primary\":{\"usedPercent\":22,\"windowDurationMins\":10080,\"resetsAt\":1784513282},"
                     "\"secondary\":null}}}";
    NSError *error = nil;
    TUMProviderUsage *usage = TUMParseCodexRateLimitJSON(JSONData(json), &error);
    Assert(usage != nil, @"Codex weekly-only response accepted");
    Assert(!usage.fiveHour.available, @"Missing Codex 5H stays unavailable");
    Assert(usage.sevenDay.available, @"Codex weekly primary classified as 7D");
}

static void TestAntigravityParser(void) {
    NSString *output = @"\x1b[2J Models & Quota\n"
                       "GEMINI MODELS\n"
                       "Weekly Limit\n"
                       "[██░░░░] 82.00%\n"
                       "82% remaining · Refreshes in 6d 2h\n"
                       "Five Hour Limit\n"
                       "[████░░] 70.00%\n"
                       "70% remaining · Refreshes in 3h 10m\n"
                       "CLAUDE AND GPT MODELS\n"
                       "Weekly Limit\n"
                       "[████░░] 24.30%\n"
                       "24% remaining · Refreshes in 51h 24m\n"
                       "Five Hour Limit\n"
                       "[█████░] 96.47%\n"
                       "96% remaining · Refreshes in 4h 53m\n"
                       "Within each group, models share a weekly limit and a 5-hour limit.\n";
    NSDate *now = [NSDate dateWithTimeIntervalSince1970:1000000];
    NSError *error = nil;
    TUMProviderUsage *usage = TUMParseAntigravityOutput(output, now, &error);
    Assert(usage != nil && error == nil, @"Antigravity parser returns usage");
    Assert(usage.quotaGroups.count == 2, @"Both Antigravity model groups parsed");
    Assert([usage.quotaGroups[0].displayName isEqualToString:@"Gemini"],
           @"Antigravity Gemini group named");
    Assert([usage.quotaGroups[1].displayName isEqualToString:@"Other"],
           @"Antigravity other-model group named");
    TUMQuotaGroup *other = usage.quotaGroups[1];
    Assert(fabs(other.fiveHour.usedPercent - 3.53) < 0.01, @"Antigravity 5H remaining converted to used");
    Assert(fabs(other.sevenDay.usedPercent - 75.70) < 0.01, @"Antigravity weekly remaining converted to used");
    Assert((NSInteger)[other.fiveHour.resetDate timeIntervalSinceDate:now] == (4 * 3600 + 53 * 60),
           @"Antigravity 5H countdown parsed");
}

static void TestAntigravityDisabled(void) {
    NSString *output = @"GEMINI MODELS\nWeekly Limit\n0.00%\nRefreshes in 38h 56m\n"
                       "Five Hour Limit\nDisabled: You have hit your weekly limit\n"
                       "CLAUDE AND GPT MODELS\n";
    NSError *error = nil;
    TUMProviderUsage *usage = TUMParseAntigravityOutput(output, [NSDate date], &error);
    if (usage == nil) {
        fprintf(stderr, "Antigravity fallback parse error: %s\n",
                error.localizedDescription.UTF8String);
    }
    Assert(usage != nil, @"Antigravity Gemini fallback accepted");
    Assert(usage.sevenDay.usedPercent == 100.0, @"Zero remaining becomes fully used");
    Assert(!usage.fiveHour.available, @"Disabled 5H remains unavailable");
}

static void TestCopilotAICredits(void) {
    NSString *output = @"AI Credits 70 (24s)\nPlan 35% used\n70 / 200 AIC\n";
    NSDate *now = [NSDate dateWithTimeIntervalSince1970:1783951200];
    NSError *error = nil;
    TUMProviderUsage *usage = TUMParseCopilotOutput(output, now, &error);
    Assert(usage != nil && error == nil, @"Copilot AI Credits output parsed");
    Assert([usage.quotaGroups.firstObject.displayName isEqualToString:@"AI Credits"],
           @"Copilot AI Credits group named");
    Assert([usage.quotaGroups.firstObject.fiveHourLabel isEqualToString:@"MO"],
           @"Copilot monthly row labeled");
    Assert(usage.quotaGroups.firstObject.sevenDayLabel.length == 0,
           @"Copilot hides unused second row");
    Assert(fabs(usage.fiveHour.usedPercent - 35.0) < 0.01,
           @"Copilot used credits normalized");

    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDateComponents *reset = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth |
                                                     NSCalendarUnitDay | NSCalendarUnitHour)
                                           fromDate:usage.fiveHour.resetDate];
    Assert(reset.year == 2026 && reset.month == 8 && reset.day == 1 && reset.hour == 0,
           @"Copilot monthly reset uses first day at midnight UTC");
}

static void TestCopilotLegacyPremiumRequests(void) {
    NSString *output = @"Premium requests\n12 / 300 premium requests\n4% used\n";
    NSError *error = nil;
    TUMProviderUsage *usage = TUMParseCopilotOutput(output, [NSDate date], &error);
    Assert(usage != nil && error == nil, @"Copilot legacy premium requests parsed");
    Assert([usage.quotaGroups.firstObject.displayName isEqualToString:@"Premium"],
           @"Copilot legacy quota group named");
    Assert(fabs(usage.fiveHour.usedPercent - 4.0) < 0.01,
           @"Copilot legacy usage normalized");
}

static void TestCountdownFormatting(void) {
    NSDate *now = [NSDate dateWithTimeIntervalSince1970:1000];
    Assert([TUMResetCountdown([now dateByAddingTimeInterval:4 * 3600 + 3 * 60], now)
            isEqualToString:@"4:03"], @"Hour countdown is compact");
    Assert([TUMResetCountdown([now dateByAddingTimeInterval:2 * 86400 + 3600], now)
            isEqualToString:@"2d1h"], @"Day countdown is compact");
}

int main(void) {
    @autoreleasepool {
        TestClaudeParser();
        TestCodexParser();
        TestCodexWeeklyOnly();
        TestAntigravityParser();
        TestAntigravityDisabled();
        TestCopilotAICredits();
        TestCopilotLegacyPremiumRequests();
        TestCountdownFormatting();
        if (failures == 0) {
            printf("All parser tests passed.\n");
        }
    }
    return failures == 0 ? 0 : 1;
}
