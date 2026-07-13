#import <AppKit/AppKit.h>
#import <objc/message.h>

#import "TUMModels.h"
#import "TUMTouchBarController.h"
#import "TUMUsageCardView.h"

static int failures = 0;

static void Assert(BOOL condition, NSString *message) {
    if (!condition) {
        failures += 1;
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    }
}

static NSDictionary<NSString *, TUMProviderUsage *> *TestUsage(void) {
    TUMProviderUsage *claude = [TUMProviderUsage usageForProviderID:@"claude"
                                                        displayName:@"Claude"];
    TUMQuotaGroup *overall = [TUMQuotaGroup groupWithID:@"overall" displayName:@"Overall"];
    TUMQuotaGroup *opus = [TUMQuotaGroup groupWithID:@"seven_day_opus" displayName:@"Opus"];
    claude.quotaGroups = @[overall, opus];

    return @{
        @"claude": claude,
        @"antigravity": [TUMProviderUsage usageForProviderID:@"antigravity"
                                                      displayName:@"Antigravity"],
        @"codex": [TUMProviderUsage usageForProviderID:@"codex" displayName:@"Codex"],
        @"copilot": [TUMProviderUsage usageForProviderID:@"copilot" displayName:@"Copilot"]
    };
}

static void TestSavedOrderNormalizationAndReorder(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:@[@"codex", @"claude", @"codex", @"unknown"]
                  forKey:@"TUMProviderOrder"];

    TUMTouchBarController *controller = [[TUMTouchBarController alloc]
        initWithUsage:TestUsage()];
    NSArray<NSString *> *order = [controller valueForKey:@"providerOrder"];
    Assert([order isEqualToArray:@[@"codex", @"claude", @"antigravity", @"copilot"]],
           @"Saved provider order is normalized");

    SEL selector = NSSelectorFromString(@"reorderProviderID:byPositions:");
    typedef void (*ReorderFunction)(id, SEL, NSString *, NSInteger);
    ((ReorderFunction)objc_msgSend)(controller, selector, @"codex", 2);
    order = [controller valueForKey:@"providerOrder"];
    Assert([order isEqualToArray:@[@"claude", @"antigravity", @"codex", @"copilot"]],
           @"Horizontal drag offset reorders provider cards");
}

static void TestVisibleProviderSelection(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:@[@"claude", @"copilot"] forKey:@"TUMVisibleProviders"];
    TUMTouchBarController *controller = [[TUMTouchBarController alloc]
        initWithUsage:TestUsage()];
    Assert([controller.visibleProviderIDs isEqualToArray:@[@"claude", @"copilot"]],
           @"Saved Touch Bar band selection is restored");

    [controller setProviderID:@"copilot" visible:NO];
    [controller setProviderID:@"antigravity" visible:YES];
    Assert([controller.visibleProviderIDs isEqualToArray:@[@"claude", @"antigravity"]],
           @"Provider bands can be hidden and shown immediately");
    Assert([[defaults stringArrayForKey:@"TUMVisibleProviders"]
            isEqualToArray:@[@"claude", @"antigravity"]],
           @"Provider band selection persists");
}

static void TestQuotaGroupCycling(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:@"TUMSelectedQuotaGroups"];
    TUMTouchBarController *controller = [[TUMTouchBarController alloc]
        initWithUsage:TestUsage()];

    SEL selector = NSSelectorFromString(@"cycleQuotaGroupForProviderID:");
    typedef void (*CycleFunction)(id, SEL, NSString *);
    ((CycleFunction)objc_msgSend)(controller, selector, @"claude");
    NSDictionary<NSString *, NSString *> *selected = [controller valueForKey:@"selectedGroupIDs"];
    Assert([selected[@"claude"] isEqualToString:@"seven_day_opus"],
           @"Tap advances to the next quota group");

    ((CycleFunction)objc_msgSend)(controller, selector, @"claude");
    selected = [controller valueForKey:@"selectedGroupIDs"];
    Assert([selected[@"claude"] isEqualToString:@"overall"],
           @"Quota group selection wraps around");
}

static void TestCardAcceptsDirectTouch(void) {
    TUMProviderUsage *usage = TestUsage()[@"claude"];
    TUMUsageCardView *card = [[TUMUsageCardView alloc] initWithUsage:usage];
    Assert(fabs(card.frame.size.width - 230.0) < 0.01,
           @"Compact progress layout uses the expected card width");
    Assert(card.gestureRecognizers.count == 2, @"Card installs tap and drag recognizers");
    for (NSGestureRecognizer *recognizer in card.gestureRecognizers) {
        Assert((recognizer.allowedTouchTypes & NSTouchTypeMaskDirect) != 0,
               @"Card recognizer accepts physical Touch Bar direct touches");
    }
}

int main(void) {
    @autoreleasepool {
        TestSavedOrderNormalizationAndReorder();
        TestQuotaGroupCycling();
        TestVisibleProviderSelection();
        TestCardAcceptsDirectTouch();
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"TUMProviderOrder"];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"TUMSelectedQuotaGroups"];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"TUMVisibleProviders"];
        if (failures == 0) {
            printf("All controller tests passed.\n");
        }
    }
    return failures == 0 ? 0 : 1;
}
