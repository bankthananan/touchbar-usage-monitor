#import <Foundation/Foundation.h>

@class TUMProviderUsage;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT TUMProviderUsage *_Nullable TUMParseClaudeUsageJSON(
    NSData *data,
    NSError **error
);

FOUNDATION_EXPORT TUMProviderUsage *_Nullable TUMParseCodexRateLimitJSON(
    NSData *data,
    NSError **error
);

FOUNDATION_EXPORT TUMProviderUsage *_Nullable TUMParseAntigravityOutput(
    NSString *output,
    NSDate *now,
    NSError **error
);

FOUNDATION_EXPORT NSString *TUMStripTerminalControlSequences(NSString *input);
FOUNDATION_EXPORT NSTimeInterval TUMParseCountdown(NSString *input);

NS_ASSUME_NONNULL_END
