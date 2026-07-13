#import <Foundation/Foundation.h>

@class TUMProviderUsage;

NS_ASSUME_NONNULL_BEGIN

@interface TUMUsageMonitor : NSObject

@property (nonatomic, copy, nullable) void (^updateHandler)(NSDictionary<NSString *, TUMProviderUsage *> *usage);
@property (nonatomic, readonly, copy) NSDictionary<NSString *, TUMProviderUsage *> *usageByProvider;

- (void)start;
- (void)stop;
- (void)refreshAllIgnoringIntervals:(BOOL)ignoreIntervals;

@end

NS_ASSUME_NONNULL_END
