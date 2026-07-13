#import <Foundation/Foundation.h>

@class TUMProviderUsage;

NS_ASSUME_NONNULL_BEGIN

typedef void (^TUMProviderCompletion)(TUMProviderUsage *_Nullable usage,
                                      NSError *_Nullable error);

@protocol TUMUsageProvider <NSObject>

@property (nonatomic, readonly, copy) NSString *providerID;
@property (nonatomic, readonly) NSTimeInterval minimumRefreshInterval;

- (void)refreshWithCompletion:(TUMProviderCompletion)completion;

@end

@interface TUMClaudeProvider : NSObject <TUMUsageProvider>
@end

@interface TUMCodexProvider : NSObject <TUMUsageProvider>
@end

@interface TUMAntigravityProvider : NSObject <TUMUsageProvider>
@end

FOUNDATION_EXPORT NSString *_Nullable TUMFindExecutable(NSArray<NSString *> *candidates);

NS_ASSUME_NONNULL_END
