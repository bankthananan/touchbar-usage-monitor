#import "TUMTouchBarController.h"
#import "TUMModels.h"
#import "TUMUsageCardView.h"

#import <objc/message.h>
#import <objc/runtime.h>

static NSTouchBarItemIdentifier const TUMClaudeItem = @"com.local.touchbarusage.claude";
static NSTouchBarItemIdentifier const TUMAntigravityItem = @"com.local.touchbarusage.antigravity";
static NSTouchBarItemIdentifier const TUMCodexItem = @"com.local.touchbarusage.codex";
static NSTouchBarItemIdentifier const TUMCopilotItem = @"com.local.touchbarusage.copilot";
static NSTouchBarItemIdentifier const TUMRefreshItem = @"com.local.touchbarusage.refresh";
static NSString *const TUMProviderOrderDefaultsKey = @"TUMProviderOrder";
static NSString *const TUMSelectedGroupsDefaultsKey = @"TUMSelectedQuotaGroups";
static NSString *const TUMVisibleProvidersDefaultsKey = @"TUMVisibleProviders";

typedef void (*TUMPresentFunction)(id, SEL, NSTouchBar *, NSInteger, id);
typedef void (*TUMDismissFunction)(id, SEL, NSTouchBar *);

@interface TUMTouchBarController ()
@property (nonatomic, strong) NSTouchBar *touchBar;
@property (nonatomic, copy) NSDictionary<NSString *, TUMProviderUsage *> *usage;
@property (nonatomic, strong) NSMutableDictionary<NSString *, TUMUsageCardView *> *cards;
@property (nonatomic, copy) NSArray<NSString *> *providerOrder;
@property (nonatomic, strong) NSMutableSet<NSString *> *visibleProviderSet;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *selectedGroupIDs;
@property (nonatomic, readwrite) BOOL isPresented;
@end

static NSArray<NSString *> *TUMDefaultProviderOrder(void) {
    return @[@"claude", @"antigravity", @"codex", @"copilot"];
}

static NSTouchBarItemIdentifier TUMItemIdentifierForProvider(NSString *providerID) {
    if ([providerID isEqualToString:@"claude"]) {
        return TUMClaudeItem;
    }
    if ([providerID isEqualToString:@"antigravity"]) {
        return TUMAntigravityItem;
    }
    if ([providerID isEqualToString:@"codex"]) {
        return TUMCodexItem;
    }
    return TUMCopilotItem;
}

@implementation TUMTouchBarController

- (instancetype)initWithUsage:(NSDictionary<NSString *,TUMProviderUsage *> *)usage {
    self = [super init];
    if (self) {
        _usage = [usage copy];
        _cards = [NSMutableDictionary dictionary];
        NSArray<NSString *> *savedOrder = [NSUserDefaults.standardUserDefaults
            stringArrayForKey:TUMProviderOrderDefaultsKey];
        NSMutableArray<NSString *> *normalizedOrder = [NSMutableArray array];
        for (NSString *providerID in savedOrder) {
            if ([TUMDefaultProviderOrder() containsObject:providerID] &&
                ![normalizedOrder containsObject:providerID]) {
                [normalizedOrder addObject:providerID];
            }
        }
        for (NSString *providerID in TUMDefaultProviderOrder()) {
            if (![normalizedOrder containsObject:providerID]) {
                [normalizedOrder addObject:providerID];
            }
        }
        _providerOrder = normalizedOrder;
        id savedVisibilityValue = [NSUserDefaults.standardUserDefaults
            objectForKey:TUMVisibleProvidersDefaultsKey];
        NSArray<NSString *> *savedVisibility = [savedVisibilityValue isKindOfClass:NSArray.class]
            ? savedVisibilityValue
            : TUMDefaultProviderOrder();
        _visibleProviderSet = [NSMutableSet set];
        for (NSString *providerID in savedVisibility) {
            if ([TUMDefaultProviderOrder() containsObject:providerID]) {
                [_visibleProviderSet addObject:providerID];
            }
        }
        NSDictionary<NSString *, NSString *> *savedGroups = [NSUserDefaults.standardUserDefaults
            dictionaryForKey:TUMSelectedGroupsDefaultsKey];
        _selectedGroupIDs = savedGroups != nil
            ? [savedGroups mutableCopy]
            : [NSMutableDictionary dictionary];
        _touchBar = [[NSTouchBar alloc] init];
        _touchBar.delegate = self;
        NSMutableArray<NSTouchBarItemIdentifier> *identifiers = [NSMutableArray array];
        for (NSString *providerID in self.visibleProviderIDs) {
            [identifiers addObject:TUMItemIdentifierForProvider(providerID)];
        }
        [identifiers addObject:TUMRefreshItem];
        _touchBar.defaultItemIdentifiers = identifiers;
    }
    return self;
}

- (BOOL)systemModalAPIAvailable {
    return class_getClassMethod(NSTouchBar.class,
        NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")) != NULL;
}

- (void)updateUsage:(NSDictionary<NSString *,TUMProviderUsage *> *)usage {
    self.usage = [usage copy];
    for (NSString *providerID in TUMDefaultProviderOrder()) {
        TUMUsageCardView *card = self.cards[providerID];
        if (card != nil && usage[providerID] != nil) {
            card.usage = usage[providerID];
            card.displayedGroupIndex = [self selectedGroupIndexForUsage:usage[providerID]];
        }
    }
}

- (NSArray<NSString *> *)visibleProviderIDs {
    NSMutableArray<NSString *> *visible = [NSMutableArray array];
    for (NSString *providerID in self.providerOrder) {
        if ([self.visibleProviderSet containsObject:providerID]) {
            [visible addObject:providerID];
        }
    }
    return visible;
}

- (NSArray<NSTouchBarItemIdentifier> *)currentTouchBarItemIdentifiers {
    NSMutableArray<NSTouchBarItemIdentifier> *identifiers = [NSMutableArray array];
    for (NSString *providerID in self.visibleProviderIDs) {
        [identifiers addObject:TUMItemIdentifierForProvider(providerID)];
    }
    [identifiers addObject:TUMRefreshItem];
    return identifiers;
}

- (void)applyCurrentTouchBarItems {
    BOOL shouldRestore = self.isPresented;
    if (shouldRestore) {
        [self dismiss];
    }
    self.touchBar.defaultItemIdentifiers = self.currentTouchBarItemIdentifiers;
    if (shouldRestore) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(80 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            [self present];
        });
    }
}

- (void)setProviderID:(NSString *)providerID visible:(BOOL)visible {
    if (![TUMDefaultProviderOrder() containsObject:providerID]) {
        return;
    }
    BOOL currentlyVisible = [self.visibleProviderSet containsObject:providerID];
    if (currentlyVisible == visible) {
        return;
    }
    if (visible) {
        [self.visibleProviderSet addObject:providerID];
    } else {
        [self.visibleProviderSet removeObject:providerID];
    }
    [NSUserDefaults.standardUserDefaults setObject:self.visibleProviderIDs
                                            forKey:TUMVisibleProvidersDefaultsKey];
    [self applyCurrentTouchBarItems];
}

- (NSUInteger)selectedGroupIndexForUsage:(TUMProviderUsage *)usage {
    NSString *selectedID = self.selectedGroupIDs[usage.providerID];
    if (selectedID != nil) {
        NSUInteger index = [usage.quotaGroups indexOfObjectPassingTest:^BOOL(
            TUMQuotaGroup *group,
            NSUInteger index,
            BOOL *stop
        ) {
            (void)index;
            (void)stop;
            return [group.groupID isEqualToString:selectedID];
        }];
        if (index != NSNotFound) {
            return index;
        }
    }
    return 0;
}

- (void)cycleQuotaGroupForProviderID:(NSString *)providerID {
    TUMProviderUsage *providerUsage = self.usage[providerID];
    if (providerUsage.quotaGroups.count <= 1) {
        if (self.refreshHandler != nil) {
            self.refreshHandler();
        }
        return;
    }
    NSUInteger current = [self selectedGroupIndexForUsage:providerUsage];
    NSUInteger next = (current + 1) % providerUsage.quotaGroups.count;
    self.selectedGroupIDs[providerID] = providerUsage.quotaGroups[next].groupID;
    [NSUserDefaults.standardUserDefaults setObject:self.selectedGroupIDs
                                            forKey:TUMSelectedGroupsDefaultsKey];
    self.cards[providerID].displayedGroupIndex = next;
}

- (void)reorderProviderID:(NSString *)providerID byPositions:(NSInteger)positions {
    NSArray<NSString *> *visibleOrder = self.visibleProviderIDs;
    NSUInteger fromIndex = [visibleOrder indexOfObject:providerID];
    if (fromIndex == NSNotFound || positions == 0) {
        return;
    }
    NSInteger from = (NSInteger)fromIndex;
    NSInteger to = from + positions;
    if (to < 0) {
        to = 0;
    } else if (to >= (NSInteger)visibleOrder.count) {
        to = (NSInteger)visibleOrder.count - 1;
    }
    if (to == from) {
        return;
    }
    NSMutableArray<NSString *> *order = [self.providerOrder mutableCopy];
    NSString *targetProviderID = visibleOrder[(NSUInteger)to];
    [order removeObject:providerID];
    NSUInteger targetIndex = [order indexOfObject:targetProviderID];
    NSUInteger insertionIndex = to > from ? targetIndex + 1 : targetIndex;
    [order insertObject:providerID atIndex:insertionIndex];
    self.providerOrder = order;
    [NSUserDefaults.standardUserDefaults setObject:order forKey:TUMProviderOrderDefaultsKey];

    [self applyCurrentTouchBarItems];
}

- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar
       makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    (void)touchBar;
    NSDictionary *providerByIdentifier = @{
        TUMClaudeItem: @"claude",
        TUMAntigravityItem: @"antigravity",
        TUMCodexItem: @"codex",
        TUMCopilotItem: @"copilot"
    };
    NSString *providerID = providerByIdentifier[identifier];
    if (providerID != nil) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        TUMProviderUsage *providerUsage = self.usage[providerID];
        TUMUsageCardView *card = [[TUMUsageCardView alloc] initWithUsage:providerUsage];
        card.displayedGroupIndex = [self selectedGroupIndexForUsage:providerUsage];
        __weak TUMTouchBarController *weakSelf = self;
        card.tapHandler = ^{
            [weakSelf cycleQuotaGroupForProviderID:providerID];
        };
        card.reorderHandler = ^(NSInteger positions) {
            [weakSelf reorderProviderID:providerID byPositions:positions];
        };
        item.view = card;
        item.customizationLabel = providerUsage.displayName;
        self.cards[providerID] = card;
        return item;
    }

    if ([identifier isEqualToString:TUMRefreshItem]) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        NSButton *button = [NSButton buttonWithTitle:@"↻"
                                              target:self
                                              action:@selector(refreshPressed:)];
        button.bezelColor = [NSColor colorWithWhite:0.28 alpha:1.0];
        button.toolTip = @"Refresh all usage limits";
        [button.widthAnchor constraintEqualToConstant:40.0].active = YES;
        item.view = button;
        item.customizationLabel = @"Refresh usage";
        return item;
    }
    return nil;
}

- (void)refreshPressed:(id)sender {
    (void)sender;
    if (self.refreshHandler != nil) {
        self.refreshHandler();
    }
}

- (void)present {
    if (self.isPresented || !self.systemModalAPIAvailable) {
        return;
    }
    SEL selector = NSSelectorFromString(
        @"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"
    );
    Method method = class_getClassMethod(NSTouchBar.class, selector);
    TUMPresentFunction presentFunction = (TUMPresentFunction)method_getImplementation(method);
    presentFunction(NSTouchBar.class, selector, self.touchBar, 1, nil);
    self.isPresented = YES;
}

- (void)dismiss {
    if (!self.isPresented) {
        return;
    }
    SEL selector = NSSelectorFromString(@"dismissSystemModalTouchBar:");
    Method method = class_getClassMethod(NSTouchBar.class, selector);
    if (method != NULL) {
        TUMDismissFunction dismissFunction = (TUMDismissFunction)method_getImplementation(method);
        dismissFunction(NSTouchBar.class, selector, self.touchBar);
    }
    self.isPresented = NO;
}

@end
