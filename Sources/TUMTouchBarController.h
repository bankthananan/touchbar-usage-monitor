#import <AppKit/AppKit.h>

@class TUMProviderUsage;

NS_ASSUME_NONNULL_BEGIN

@interface TUMTouchBarController : NSObject <NSTouchBarDelegate>

@property (nonatomic, copy, nullable) void (^refreshHandler)(void);
@property (nonatomic, readonly) BOOL isPresented;
@property (nonatomic, readonly) BOOL systemModalAPIAvailable;

- (instancetype)initWithUsage:(NSDictionary<NSString *, TUMProviderUsage *> *)usage;
- (void)updateUsage:(NSDictionary<NSString *, TUMProviderUsage *> *)usage;
- (void)present;
- (void)dismiss;

@end
NS_ASSUME_NONNULL_END
