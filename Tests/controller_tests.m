#import <AppKit/AppKit.h>
#import <objc/message.h>

#import "TUMModels.h"
#import "TUMTouchBarController.h"

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
        @"codex": [TUMProviderUsage usageForProviderID:@"codex" displayName:@"Codex"]
    };
}

static void TestSavedOrderNormalizationAndReorder(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:@[@"codex", @"claude", @"codex", @"unknown"]
                  forKey:@"TUMProviderOrder"];

    TUMTouchBarController *controller = [[TUMTouchBarController alloc]
        initWithUsage:TestUsage()];
    NSArray<NSString *> *order = [controller valueForKey:@"providerOrder"];
    Assert([order isEqualToArray:@[@"codex", @"claude", @"antigravity"]],
           @"Saved provider order is normalized");

    SEL selector = NSSelectorFromString(@"reorderProviderID:byPositions:");
    typedef void (*ReorderFunction)(id, SEL, NSString *, NSInteger);
    ((ReorderFunction)objc_msgSend)(controller, selector, @"codex", 2);
    order = [controller valueForKey:@"providerOrder"];
    Assert([order isEqualToArray:@[@"claude", @"antigravity", @"codex"]],
           @"Horizontal drag offset reorders provider cards");
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

int main(void) {
    @autoreleasepool {
        TestSavedOrderNormalizationAndReorder();
        TestQuotaGroupCycling();
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"TUMProviderOrder"];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"TUMSelectedQuotaGroups"];
        if (failures == 0) {
            printf("All controller tests passed.\n");
        }
    }
    return failures == 0 ? 0 : 1;
}
