#import "TUMAppDelegate.h"
#import "TUMModels.h"
#import "TUMTouchBarController.h"
#import "TUMUsageMonitor.h"

@interface TUMAppDelegate ()
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *statusMenu;
@property (nonatomic, strong) NSMenuItem *focusItem;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMenuItem *> *providerMenuItems;
@property (nonatomic, strong) TUMUsageMonitor *usageMonitor;
@property (nonatomic, strong) TUMTouchBarController *touchBarController;
@property (nonatomic) BOOL warpIsFrontmost;
@end

@implementation TUMAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.providerMenuItems = [NSMutableDictionary dictionary];
    self.usageMonitor = [[TUMUsageMonitor alloc] init];
    self.touchBarController = [[TUMTouchBarController alloc]
        initWithUsage:self.usageMonitor.usageByProvider];

    __weak TUMAppDelegate *weakSelf = self;
    self.usageMonitor.updateHandler = ^(NSDictionary<NSString *, TUMProviderUsage *> *usage) {
        [weakSelf.touchBarController updateUsage:usage];
        [weakSelf rebuildUsageMenu:usage];
    };
    self.touchBarController.refreshHandler = ^{
        [weakSelf.usageMonitor refreshAllIgnoringIntervals:YES];
    };

    [self buildStatusMenu];
    [self observeActiveApplication];
    [self.usageMonitor start];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self.usageMonitor stop];
    [self.touchBarController dismiss];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
}

- (void)buildStatusMenu {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.title = @"TB";
    self.statusItem.button.toolTip = @"Touch Bar Usage Monitor";

    self.statusMenu = [[NSMenu alloc] initWithTitle:@"Touch Bar Usage Monitor"];
    NSMenuItem *titleItem = [[NSMenuItem alloc] initWithTitle:@"Touch Bar Usage Monitor"
                                                      action:nil
                                               keyEquivalent:@""];
    titleItem.enabled = NO;
    [self.statusMenu addItem:titleItem];

    self.focusItem = [[NSMenuItem alloc] initWithTitle:@"Warp: checking…"
                                                action:nil
                                         keyEquivalent:@""];
    self.focusItem.enabled = NO;
    [self.statusMenu addItem:self.focusItem];
    [self.statusMenu addItem:NSMenuItem.separatorItem];

    for (NSString *providerID in @[@"claude", @"antigravity", @"codex"]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Loading…"
                                                     action:nil
                                              keyEquivalent:@""];
        item.enabled = NO;
        self.providerMenuItems[providerID] = item;
        [self.statusMenu addItem:item];
    }

    [self.statusMenu addItem:NSMenuItem.separatorItem];
    [self.statusMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Refresh now"
                                                       action:@selector(refreshNow:)
                                                keyEquivalent:@"r"]];
    NSMenuItem *apiItem = [[NSMenuItem alloc]
        initWithTitle:(self.touchBarController.systemModalAPIAvailable
            ? @"Touch Bar API: ready"
            : @"Touch Bar API: unavailable")
        action:nil
        keyEquivalent:@""];
    apiItem.enabled = NO;
    [self.statusMenu addItem:apiItem];
    [self.statusMenu addItem:NSMenuItem.separatorItem];
    [self.statusMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Quit"
                                                       action:@selector(quit:)
                                                keyEquivalent:@"q"]];
    self.statusItem.menu = self.statusMenu;
    [self rebuildUsageMenu:self.usageMonitor.usageByProvider];
}

- (void)rebuildUsageMenu:(NSDictionary<NSString *, TUMProviderUsage *> *)usage {
    NSDate *now = [NSDate date];
    for (NSString *providerID in @[@"claude", @"antigravity", @"codex"]) {
        TUMProviderUsage *providerUsage = usage[providerID];
        NSString *detail = nil;
        if (!providerUsage.fiveHour.available && !providerUsage.sevenDay.available) {
            detail = providerUsage.errorMessage != nil
                ? providerUsage.errorMessage
                : @"Unavailable";
        } else {
            detail = [NSString stringWithFormat:@"5H %@  ·  7D %@",
                      TUMCompactWindowText(providerUsage.fiveHour, now),
                      TUMCompactWindowText(providerUsage.sevenDay, now)];
        }
        self.providerMenuItems[providerID].title = [NSString
            stringWithFormat:@"%@: %@", providerUsage.displayName, detail];
    }
}

- (void)observeActiveApplication {
    [NSWorkspace.sharedWorkspace.notificationCenter
        addObserver:self
           selector:@selector(activeApplicationChanged:)
               name:NSWorkspaceDidActivateApplicationNotification
             object:nil];
    [self updateForApplication:NSWorkspace.sharedWorkspace.frontmostApplication];
}

- (void)activeApplicationChanged:(NSNotification *)notification {
    NSRunningApplication *application = notification.userInfo[NSWorkspaceApplicationKey];
    [self updateForApplication:application];
}

- (void)updateForApplication:(NSRunningApplication *)application {
    NSString *bundleID = application.bundleIdentifier != nil
        ? application.bundleIdentifier
        : @"";
    NSSet *warpBundleIDs = [NSSet setWithArray:@[
        @"dev.warp.Warp-Stable",
        @"dev.warp.Warp-Preview",
        @"dev.warp.Warp"
    ]];
    self.warpIsFrontmost = [warpBundleIDs containsObject:bundleID];
    self.focusItem.title = self.warpIsFrontmost
        ? @"Warp: focused — Touch Bar active"
        : [NSString stringWithFormat:@"Warp: inactive (%@)",
           application.localizedName != nil ? application.localizedName : @"unknown"];

    if (self.warpIsFrontmost) {
        [self.usageMonitor refreshAllIgnoringIntervals:NO];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(150 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            if (self.warpIsFrontmost) {
                [self.touchBarController present];
            }
        });
    } else {
        [self.touchBarController dismiss];
    }
}

- (void)refreshNow:(id)sender {
    (void)sender;
    [self.usageMonitor refreshAllIgnoringIntervals:YES];
}

- (void)quit:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
}

@end
