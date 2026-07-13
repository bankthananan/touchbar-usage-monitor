#import "TUMModels.h"

@implementation TUMWindowUsage

+ (instancetype)unavailableWithNote:(NSString *)note {
    TUMWindowUsage *usage = [[self alloc] init];
    usage.available = NO;
    usage.note = note;
    return usage;
}

+ (instancetype)windowWithUsedPercent:(double)usedPercent
                        windowMinutes:(NSInteger)windowMinutes
                            resetDate:(NSDate *)resetDate {
    TUMWindowUsage *usage = [[self alloc] init];
    usage.available = YES;
    usage.usedPercent = usedPercent < 0.0 ? 0.0 : (usedPercent > 100.0 ? 100.0 : usedPercent);
    usage.windowMinutes = windowMinutes;
    usage.resetDate = resetDate;
    return usage;
}

- (id)copyWithZone:(NSZone *)zone {
    TUMWindowUsage *copy = [[[self class] allocWithZone:zone] init];
    copy.available = self.available;
    copy.usedPercent = self.usedPercent;
    copy.windowMinutes = self.windowMinutes;
    copy.resetDate = self.resetDate;
    copy.note = self.note;
    return copy;
}

@end

@implementation TUMProviderUsage

+ (instancetype)usageForProviderID:(NSString *)providerID
                        displayName:(NSString *)displayName {
    TUMProviderUsage *usage = [[self alloc] init];
    usage.providerID = providerID;
    usage.displayName = displayName;
    usage.fiveHour = [TUMWindowUsage unavailableWithNote:nil];
    usage.sevenDay = [TUMWindowUsage unavailableWithNote:nil];
    usage.updatedAt = [NSDate date];
    return usage;
}

- (id)copyWithZone:(NSZone *)zone {
    TUMProviderUsage *copy = [[[self class] allocWithZone:zone] init];
    copy.providerID = self.providerID;
    copy.displayName = self.displayName;
    copy.fiveHour = [self.fiveHour copy];
    copy.sevenDay = [self.sevenDay copy];
    copy.updatedAt = self.updatedAt;
    copy.errorMessage = self.errorMessage;
    return copy;
}

@end

NSString *TUMResetCountdown(NSDate *resetDate, NSDate *now) {
    if (resetDate == nil) {
        return @"—";
    }

    NSTimeInterval remaining = [resetDate timeIntervalSinceDate:now];
    if (remaining <= 0) {
        return @"now";
    }

    NSInteger totalMinutes = (NSInteger)ceil(remaining / 60.0);
    NSInteger days = totalMinutes / (24 * 60);
    NSInteger hours = (totalMinutes % (24 * 60)) / 60;
    NSInteger minutes = totalMinutes % 60;

    if (days > 0) {
        return hours > 0
            ? [NSString stringWithFormat:@"%ldd%ldh", (long)days, (long)hours]
            : [NSString stringWithFormat:@"%ldd", (long)days];
    }
    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld", (long)hours, (long)minutes];
    }
    return [NSString stringWithFormat:@"%ldm", (long)minutes];
}

NSString *TUMCompactWindowText(TUMWindowUsage *window, NSDate *now) {
    if (!window.available) {
        return @"—";
    }
    return [NSString stringWithFormat:@"%.0f%%↻%@",
                                      window.usedPercent,
                                      TUMResetCountdown(window.resetDate, now)];
}
