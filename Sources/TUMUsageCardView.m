#import "TUMUsageCardView.h"
#import "TUMModels.h"
#import <math.h>

static NSColor *TUMProviderColor(NSString *providerID) {
    if ([providerID isEqualToString:@"claude"]) {
        return [NSColor colorWithRed:0.94 green:0.35 blue:0.16 alpha:1.0];
    }
    if ([providerID isEqualToString:@"antigravity"]) {
        return [NSColor colorWithRed:0.38 green:0.52 blue:1.0 alpha:1.0];
    }
    if ([providerID isEqualToString:@"codex"]) {
        return [NSColor colorWithRed:0.57 green:0.36 blue:0.93 alpha:1.0];
    }
    return [NSColor colorWithRed:0.18 green:0.68 blue:0.62 alpha:1.0];
}

static NSString *TUMCardName(TUMProviderUsage *usage) {
    if ([usage.providerID isEqualToString:@"antigravity"]) {
        return @"Antigrav";
    }
    return usage.displayName;
}

static NSString *TUMProviderGlyph(NSString *providerID) {
    if ([providerID isEqualToString:@"claude"]) {
        return @"C";
    }
    if ([providerID isEqualToString:@"antigravity"]) {
        return @"A";
    }
    if ([providerID isEqualToString:@"codex"]) {
        return @"X";
    }
    return @"G";
}

static NSColor *TUMUsageColor(double usedPercent) {
    if (usedPercent >= 90.0) {
        return [NSColor colorWithRed:1.0 green:0.31 blue:0.31 alpha:1.0];
    }
    if (usedPercent >= 75.0) {
        return [NSColor colorWithRed:1.0 green:0.66 blue:0.22 alpha:1.0];
    }
    return [NSColor colorWithRed:0.36 green:0.88 blue:0.38 alpha:1.0];
}

static void TUMDrawQuotaRow(NSString *label,
                            TUMWindowUsage *window,
                            NSDate *now,
                            CGFloat y) {
    NSDictionary *labelAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:6.5 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.62 alpha:1.0]
    };
    NSDictionary *valueAttributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:7.2
                                                             weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    NSDictionary *resetAttributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:6.5
                                                             weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.72 alpha:1.0]
    };

    [label drawInRect:NSMakeRect(84, y, 14, 9) withAttributes:labelAttributes];

    NSRect trackRect = NSMakeRect(100, y + 3.0, 38, 3.5);
    [[NSColor colorWithWhite:0.23 alpha:1.0] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:trackRect xRadius:1.75 yRadius:1.75] fill];
    if (window.available) {
        CGFloat fillWidth = trackRect.size.width * (window.usedPercent / 100.0);
        if (fillWidth > 0.0) {
            if (fillWidth < 1.5) {
                fillWidth = 1.5;
            }
            [TUMUsageColor(window.usedPercent) setFill];
            NSRect fillRect = NSMakeRect(trackRect.origin.x,
                                         trackRect.origin.y,
                                         fillWidth,
                                         trackRect.size.height);
            [[NSBezierPath bezierPathWithRoundedRect:fillRect
                                             xRadius:1.75
                                             yRadius:1.75] fill];
        }
    }

    NSString *percent = window.available
        ? [NSString stringWithFormat:@"%.0f%%", window.usedPercent]
        : @"—";
    NSString *reset = window.available ? TUMResetCountdown(window.resetDate, now) : @"—";
    [percent drawInRect:NSMakeRect(143, y, 30, 9) withAttributes:valueAttributes];
    [reset drawInRect:NSMakeRect(176, y, 48, 9) withAttributes:resetAttributes];
}

@interface TUMUsageCardView () <NSGestureRecognizerDelegate>
@property (nonatomic, strong) NSClickGestureRecognizer *clickRecognizer;
@property (nonatomic, strong) NSPanGestureRecognizer *panRecognizer;
@end
@implementation TUMUsageCardView

- (instancetype)initWithUsage:(TUMProviderUsage *)usage {
    self = [super initWithFrame:NSMakeRect(0, 0, 230, 30)];
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
        [self.widthAnchor constraintEqualToConstant:230.0].active = YES;
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
    NSInteger positions = (NSInteger)(fabs(distance) / 180.0);
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
    NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:bounds
                                                               xRadius:5.0
                                                               yRadius:5.0];
    [[NSColor colorWithWhite:0.075 alpha:1.0] setFill];
    [background fill];
    [[NSColor colorWithWhite:1.0 alpha:0.08] setStroke];
    background.lineWidth = 0.5;
    [background stroke];

    NSColor *accent = TUMProviderColor(self.usage.providerID);
    [accent setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(7, 7, 16, 16)
                                     xRadius:4
                                     yRadius:4] fill];
    NSDictionary *glyphAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:8.0 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    NSMutableParagraphStyle *centered = [[NSMutableParagraphStyle alloc] init];
    centered.alignment = NSTextAlignmentCenter;
    NSMutableDictionary *centeredGlyphAttributes = [glyphAttributes mutableCopy];
    centeredGlyphAttributes[NSParagraphStyleAttributeName] = centered;
    [TUMProviderGlyph(self.usage.providerID)
        drawInRect:NSMakeRect(7, 10, 16, 10)
        withAttributes:centeredGlyphAttributes];

    [[NSColor colorWithWhite:1.0 alpha:0.10] setFill];
    NSRectFill(NSMakeRect(78, 5, 0.5, 20));

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
    NSString *groupName = group != nil ? group.displayName : @"Loading";
    if (groupCount > 1) {
        groupName = [NSString stringWithFormat:@"%@  %lu/%lu",
                     groupName,
                     (unsigned long)(groupIndex + 1),
                     (unsigned long)groupCount];
    } else if (group == nil && self.usage.errorMessage.length > 0) {
        groupName = @"Unavailable";
    }

    NSDictionary *titleAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:8.5 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    NSDictionary *groupAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:6.8 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.68 alpha:1.0]
    };
    [title drawInRect:NSMakeRect(29, 16, 46, 10)
       withAttributes:titleAttributes];
    [groupName drawInRect:NSMakeRect(29, 5, 46, 9)
           withAttributes:groupAttributes];

    TUMWindowUsage *fiveHour = group != nil
        ? group.fiveHour
        : [TUMWindowUsage unavailableWithNote:nil];
    TUMWindowUsage *sevenDay = group != nil
        ? group.sevenDay
        : [TUMWindowUsage unavailableWithNote:nil];
    NSString *fiveHourLabel = group != nil ? group.fiveHourLabel : @"5H";
    NSString *sevenDayLabel = group != nil ? group.sevenDayLabel : @"7D";
    if (sevenDayLabel.length == 0) {
        TUMDrawQuotaRow(fiveHourLabel, fiveHour, now, 10.5);
    } else {
        TUMDrawQuotaRow(fiveHourLabel, fiveHour, now, 16);
        TUMDrawQuotaRow(sevenDayLabel, sevenDay, now, 5);
    }
}

@end
