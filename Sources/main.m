#import <AppKit/AppKit.h>
#import "TUMAppDelegate.h"

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        TUMAppDelegate *delegate = [[TUMAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
