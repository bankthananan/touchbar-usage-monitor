#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TUMWindowUsage : NSObject <NSCopying>

@property (nonatomic) BOOL available;
@property (nonatomic) double usedPercent;
@property (nonatomic) NSInteger windowMinutes;
@property (nonatomic, nullable, copy) NSDate *resetDate;
@property (nonatomic, nullable, copy) NSString *note;

+ (instancetype)unavailableWithNote:(nullable NSString *)note;
+ (instancetype)windowWithUsedPercent:(double)usedPercent
                        windowMinutes:(NSInteger)windowMinutes
                            resetDate:(nullable NSDate *)resetDate;

@end

@interface TUMProviderUsage : NSObject <NSCopying>

@property (nonatomic, copy) NSString *providerID;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, strong) TUMWindowUsage *fiveHour;
@property (nonatomic, strong) TUMWindowUsage *sevenDay;
@property (nonatomic, copy) NSDate *updatedAt;
@property (nonatomic, nullable, copy) NSString *errorMessage;

+ (instancetype)usageForProviderID:(NSString *)providerID
                        displayName:(NSString *)displayName;

@end

FOUNDATION_EXPORT NSString *TUMResetCountdown(NSDate *_Nullable resetDate, NSDate *now);
FOUNDATION_EXPORT NSString *TUMCompactWindowText(TUMWindowUsage *window, NSDate *now);

NS_ASSUME_NONNULL_END
