#import "TUMUsageCardView.h"
#import "TUMModels.h"

static NSColor *TUMProviderColor(NSString *providerID) {
    if ([providerID isEqualToString:@"claude"]) {
        return [NSColor colorWithRed:0.89 green:0.43 blue:0.25 alpha:1.0];
    }
    if ([providerID isEqualToString:@"antigravity"]) {
        return [NSColor colorWithRed:0.40 green:0.58 blue:1.0 alpha:1.0];
    }
    return [NSColor colorWithRed:0.30 green:0.77 blue:0.55 alpha:1.0];
}

static NSString *TUMCardName(TUMProviderUsage *usage) {
    if ([usage.providerID isEqualToString:@"antigravity"]) {
        return @"Antigrav";
    }
    return usage.displayName;
}

@interface TUMUsageCardView ()
@property (nonatomic, strong) NSClickGestureRecognizer *clickRecognizer;
@end
@implementation TUMUsageCardView

- (instancetype)initWithUsage:(TUMProviderUsage *)usage {
    self = [super initWithFrame:NSMakeRect(0, 0, 218, 30)];
    if (self) {
        _usage = usage;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 6.0;
        self.layer.masksToBounds = YES;
        _clickRecognizer = [[NSClickGestureRecognizer alloc] initWithTarget:self
                                                                    action:@selector(tapped:)];
        [self addGestureRecognizer:_clickRecognizer];
        [self.widthAnchor constraintEqualToConstant:218.0].active = YES;
        [self.heightAnchor constraintEqualToConstant:30.0].active = YES;
    }
    return self;
}

- (void)setUsage:(TUMProviderUsage *)usage {
    _usage = usage;
    [self setNeedsDisplay:YES];
}

- (void)tapped:(NSClickGestureRecognizer *)recognizer {
    (void)recognizer;
    if (self.tapHandler != nil) {
        self.tapHandler();
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = self.bounds;
    [[NSColor colorWithWhite:0.14 alpha:1.0] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:6 yRadius:6] fill];

    NSColor *accent = TUMProviderColor(self.usage.providerID);
    [accent setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, 4, NSHeight(bounds))
                                     xRadius:2
                                     yRadius:2] fill];

    NSDate *now = [NSDate date];
    NSString *title = TUMCardName(self.usage);
    NSString *detail = nil;
    if (!self.usage.fiveHour.available && !self.usage.sevenDay.available) {
        detail = self.usage.errorMessage.length > 0 ? @"Unavailable · tap to retry" : @"Loading…";
    } else {
        detail = [NSString stringWithFormat:@"5H %@   7D %@",
                  TUMCompactWindowText(self.usage.fiveHour, now),
                  TUMCompactWindowText(self.usage.sevenDay, now)];
    }

    NSDictionary *titleAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:9.5 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: accent
    };
    NSDictionary *detailAttributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:8.5
                                                             weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    [title drawInRect:NSMakeRect(10, 16, NSWidth(bounds) - 14, 12)
       withAttributes:titleAttributes];
    [detail drawInRect:NSMakeRect(10, 3, NSWidth(bounds) - 14, 12)
        withAttributes:detailAttributes];
}

@end
