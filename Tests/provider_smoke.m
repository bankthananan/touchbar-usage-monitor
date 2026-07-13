#import <Foundation/Foundation.h>

#import "TUMModels.h"
#import "TUMProviders.h"

static NSString *WindowDescription(TUMWindowUsage *window) {
    if (!window.available) {
        return @"—";
    }
    return [NSString stringWithFormat:@"%.1f%% used, reset %@",
                                      window.usedPercent,
                                      TUMResetCountdown(window.resetDate, [NSDate date])];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray<id<TUMUsageProvider>> *allProviders = @[
            [[TUMClaudeProvider alloc] init],
            [[TUMCodexProvider alloc] init],
            [[TUMAntigravityProvider alloc] init]
        ];
        NSString *filter = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : nil;
        __block int failures = 0;

        for (id<TUMUsageProvider> provider in allProviders) {
            if (filter != nil && ![filter isEqualToString:provider.providerID]) {
                continue;
            }
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
            [provider refreshWithCompletion:^(TUMProviderUsage *usage, NSError *error) {
                if (usage == nil) {
                    failures += 1;
                    NSString *description = error.localizedDescription != nil
                        ? error.localizedDescription
                        : @"unknown error";
                    printf("%s ERROR: %s\n",
                           provider.providerID.UTF8String,
                           description.UTF8String);
                } else {
                    printf("%s  5H %s  7D %s\n",
                           usage.displayName.UTF8String,
                           WindowDescription(usage.fiveHour).UTF8String,
                           WindowDescription(usage.sevenDay).UTF8String);
                }
                dispatch_semaphore_signal(semaphore);
            }];
            if (dispatch_semaphore_wait(semaphore,
                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC))) != 0) {
                failures += 1;
                printf("%s ERROR: smoke-test timeout\n", provider.providerID.UTF8String);
            }
        }
        return failures == 0 ? 0 : 1;
    }
}
