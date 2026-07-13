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
                     "\"seven_day\":{\"utilization\":0.61,\"resets_at\":\"2026-07-18T12:00:00Z\"}}";
    NSError *error = nil;
    TUMProviderUsage *usage = TUMParseClaudeUsageJSON(JSONData(json), &error);
    Assert(usage != nil && error == nil, @"Claude parser returns usage");
    Assert(fabs(usage.fiveHour.usedPercent - 42.0) < 0.01, @"Claude 5H utilization normalized");
    Assert(fabs(usage.sevenDay.usedPercent - 61.0) < 0.01, @"Claude 7D utilization normalized");
    Assert(usage.fiveHour.resetDate != nil, @"Claude reset date parsed");
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
    Assert(fabs(usage.fiveHour.usedPercent - 3.53) < 0.01, @"Antigravity 5H remaining converted to used");
    Assert(fabs(usage.sevenDay.usedPercent - 75.70) < 0.01, @"Antigravity weekly remaining converted to used");
    Assert((NSInteger)[usage.fiveHour.resetDate timeIntervalSinceDate:now] == (4 * 3600 + 53 * 60),
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
        TestCountdownFormatting();
        if (failures == 0) {
            printf("All parser tests passed.\n");
        }
    }
    return failures == 0 ? 0 : 1;
}
