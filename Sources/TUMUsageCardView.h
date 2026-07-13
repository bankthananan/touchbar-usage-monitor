#import <AppKit/AppKit.h>

@class TUMProviderUsage;

NS_ASSUME_NONNULL_BEGIN

@interface TUMUsageCardView : NSView

@property (nonatomic, strong) TUMProviderUsage *usage;
@property (nonatomic, copy, nullable) void (^tapHandler)(void);

- (instancetype)initWithUsage:(TUMProviderUsage *)usage;

@end
NS_ASSUME_NONNULL_END
