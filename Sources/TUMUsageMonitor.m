#import "TUMUsageMonitor.h"
#import "TUMModels.h"
#import "TUMProviders.h"

@interface TUMUsageMonitor ()
@property (nonatomic, strong) NSArray<id<TUMUsageProvider>> *providers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, TUMProviderUsage *> *mutableUsage;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *lastAttempts;
@property (nonatomic, strong) NSMutableSet<NSString *> *refreshingProviders;
@property (nonatomic, strong, nullable) NSTimer *timer;
@end

@implementation TUMUsageMonitor

- (instancetype)init {
    self = [super init];
    if (self) {
        _providers = @[
            [[TUMClaudeProvider alloc] init],
            [[TUMAntigravityProvider alloc] init],
            [[TUMCodexProvider alloc] init],
            [[TUMCopilotProvider alloc] init]
        ];
        _mutableUsage = [NSMutableDictionary dictionary];
        _lastAttempts = [NSMutableDictionary dictionary];
        _refreshingProviders = [NSMutableSet set];

        NSDictionary *names = @{
            @"claude": @"Claude",
            @"antigravity": @"Antigravity",
            @"codex": @"Codex",
            @"copilot": @"Copilot"
        };
        for (id<TUMUsageProvider> provider in _providers) {
            TUMProviderUsage *placeholder = [TUMProviderUsage
                usageForProviderID:provider.providerID
                displayName:names[provider.providerID]];
            placeholder.errorMessage = @"Waiting for first refresh";
            _mutableUsage[provider.providerID] = placeholder;
        }
    }
    return self;
}

- (NSDictionary<NSString *,TUMProviderUsage *> *)usageByProvider {
    @synchronized (self) {
        return [self.mutableUsage copy];
    }
}

- (void)start {
    [self refreshAllIgnoringIntervals:YES];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:30.0
                                                  target:self
                                                selector:@selector(timerFired:)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)timerFired:(NSTimer *)timer {
    (void)timer;
    [self refreshAllIgnoringIntervals:NO];
}

- (void)refreshAllIgnoringIntervals:(BOOL)ignoreIntervals {
    NSDate *now = [NSDate date];
    for (id<TUMUsageProvider> provider in self.providers) {
        NSDate *lastAttempt = self.lastAttempts[provider.providerID];
        if (!ignoreIntervals && lastAttempt != nil &&
            [now timeIntervalSinceDate:lastAttempt] < provider.minimumRefreshInterval) {
            continue;
        }
        if ([self.refreshingProviders containsObject:provider.providerID]) {
            continue;
        }

        self.lastAttempts[provider.providerID] = now;
        [self.refreshingProviders addObject:provider.providerID];
        __weak TUMUsageMonitor *weakSelf = self;
        [provider refreshWithCompletion:^(TUMProviderUsage *usage, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                TUMUsageMonitor *strongSelf = weakSelf;
                if (strongSelf == nil) {
                    return;
                }
                [strongSelf.refreshingProviders removeObject:provider.providerID];
                if (usage != nil) {
                    usage.updatedAt = [NSDate date];
                    strongSelf.mutableUsage[provider.providerID] = usage;
                } else {
                    TUMProviderUsage *existing = [strongSelf.mutableUsage[provider.providerID] copy];
                    existing.errorMessage = error.localizedDescription != nil
                        ? error.localizedDescription
                        : @"Refresh failed";
                    strongSelf.mutableUsage[provider.providerID] = existing;
                }
                if (strongSelf.updateHandler != nil) {
                    strongSelf.updateHandler(strongSelf.usageByProvider);
                }
            });
        }];
    }
}

@end
