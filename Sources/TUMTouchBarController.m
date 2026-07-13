#import "TUMTouchBarController.h"
#import "TUMModels.h"
#import "TUMUsageCardView.h"

#import <objc/message.h>
#import <objc/runtime.h>

static NSTouchBarItemIdentifier const TUMClaudeItem = @"com.local.touchbarusage.claude";
static NSTouchBarItemIdentifier const TUMAntigravityItem = @"com.local.touchbarusage.antigravity";
static NSTouchBarItemIdentifier const TUMCodexItem = @"com.local.touchbarusage.codex";
static NSTouchBarItemIdentifier const TUMRefreshItem = @"com.local.touchbarusage.refresh";

typedef void (*TUMPresentFunction)(id, SEL, NSTouchBar *, NSInteger, id);
typedef void (*TUMDismissFunction)(id, SEL, NSTouchBar *);

@interface TUMTouchBarController ()
@property (nonatomic, strong) NSTouchBar *touchBar;
@property (nonatomic, copy) NSDictionary<NSString *, TUMProviderUsage *> *usage;
@property (nonatomic, strong) NSMutableDictionary<NSString *, TUMUsageCardView *> *cards;
@property (nonatomic, readwrite) BOOL isPresented;
@end

@implementation TUMTouchBarController

- (instancetype)initWithUsage:(NSDictionary<NSString *,TUMProviderUsage *> *)usage {
    self = [super init];
    if (self) {
        _usage = [usage copy];
        _cards = [NSMutableDictionary dictionary];
        _touchBar = [[NSTouchBar alloc] init];
        _touchBar.delegate = self;
        _touchBar.defaultItemIdentifiers = @[
            TUMClaudeItem,
            TUMAntigravityItem,
            TUMCodexItem,
            TUMRefreshItem
        ];
        _touchBar.principalItemIdentifier = TUMAntigravityItem;
    }
    return self;
}

- (BOOL)systemModalAPIAvailable {
    return class_getClassMethod(NSTouchBar.class,
        NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")) != NULL;
}

- (void)updateUsage:(NSDictionary<NSString *,TUMProviderUsage *> *)usage {
    self.usage = [usage copy];
    for (NSString *providerID in @[@"claude", @"antigravity", @"codex"]) {
        TUMUsageCardView *card = self.cards[providerID];
        if (card != nil && usage[providerID] != nil) {
            card.usage = usage[providerID];
        }
    }
}

- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar
       makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    (void)touchBar;
    NSDictionary *providerByIdentifier = @{
        TUMClaudeItem: @"claude",
        TUMAntigravityItem: @"antigravity",
        TUMCodexItem: @"codex"
    };
    NSString *providerID = providerByIdentifier[identifier];
    if (providerID != nil) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        TUMProviderUsage *providerUsage = self.usage[providerID];
        TUMUsageCardView *card = [[TUMUsageCardView alloc] initWithUsage:providerUsage];
        __weak TUMTouchBarController *weakSelf = self;
        card.tapHandler = ^{
            if (weakSelf.refreshHandler != nil) {
                weakSelf.refreshHandler();
            }
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
