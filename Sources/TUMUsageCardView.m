#import "TUMUsageCardView.h"
#import "TUMModels.h"
#import <math.h>

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

@interface TUMUsageCardView () <NSGestureRecognizerDelegate>
@property (nonatomic, strong) NSClickGestureRecognizer *clickRecognizer;
@property (nonatomic, strong) NSPanGestureRecognizer *panRecognizer;
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
        _panRecognizer = [[NSPanGestureRecognizer alloc] initWithTarget:self
                                                                 action:@selector(dragged:)];
        // Touch Bar input is NSTouchTypeDirect. Gesture recognizers default to
        // no allowed touch types, so they otherwise ignore physical bar taps.
        _clickRecognizer.allowedTouchTypes = NSTouchTypeMaskDirect;
        _panRecognizer.allowedTouchTypes = NSTouchTypeMaskDirect;
        _clickRecognizer.delegate = self;
        _panRecognizer.delegate = self;
        [self addGestureRecognizer:_clickRecognizer];
        [self addGestureRecognizer:_panRecognizer];
        [self.widthAnchor constraintEqualToConstant:218.0].active = YES;
        [self.heightAnchor constraintEqualToConstant:30.0].active = YES;
    }
    return self;
}

- (void)setUsage:(TUMProviderUsage *)usage {
    _usage = usage;
    [self setNeedsDisplay:YES];
}

- (void)setDisplayedGroupIndex:(NSUInteger)displayedGroupIndex {
    _displayedGroupIndex = displayedGroupIndex;
    [self setNeedsDisplay:YES];
}

- (void)tapped:(NSClickGestureRecognizer *)recognizer {
    (void)recognizer;
    if (self.tapHandler != nil) {
        self.tapHandler();
    }
}

- (void)dragged:(NSPanGestureRecognizer *)recognizer {
    if (recognizer.state != NSGestureRecognizerStateEnded || self.reorderHandler == nil) {
        return;
    }
    CGFloat distance = [recognizer translationInView:self].x;
    if (fabs(distance) < 45.0) {
        return;
    }
    NSInteger positions = (NSInteger)(fabs(distance) / 150.0);
    if (positions < 1) {
        positions = 1;
    }
    self.reorderHandler(distance < 0 ? -positions : positions);
}

- (BOOL)gestureRecognizer:(NSGestureRecognizer *)gestureRecognizer
    shouldRequireFailureOfGestureRecognizer:(NSGestureRecognizer *)otherGestureRecognizer {
    return gestureRecognizer == self.clickRecognizer &&
           otherGestureRecognizer == self.panRecognizer;
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
    NSUInteger groupCount = self.usage.quotaGroups.count;
    NSUInteger groupIndex = self.displayedGroupIndex;
    if (groupCount == 0) {
        groupIndex = 0;
    } else if (groupIndex >= groupCount) {
        groupIndex = groupCount - 1;
    }
    TUMQuotaGroup *group = groupCount == 0
        ? nil
        : self.usage.quotaGroups[groupIndex];
    NSString *title = TUMCardName(self.usage);
    if (groupCount > 1) {
        title = [NSString stringWithFormat:@"%@ · %@  %lu/%lu",
                  title,
                  group.displayName,
                  (unsigned long)(groupIndex + 1),
                  (unsigned long)groupCount];
    }
    NSString *detail = nil;
    if (group == nil || (!group.fiveHour.available && !group.sevenDay.available)) {
        detail = self.usage.errorMessage.length > 0 ? @"Unavailable · tap to retry" : @"Loading…";
    } else {
        detail = [NSString stringWithFormat:@"5H %@   7D %@",
                  TUMCompactWindowText(group.fiveHour, now),
                  TUMCompactWindowText(group.sevenDay, now)];
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
