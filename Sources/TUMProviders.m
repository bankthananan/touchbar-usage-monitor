#import "TUMProviders.h"
#import "TUMModels.h"
#import "TUMParsers.h"

#import <Security/Security.h>
#import <fcntl.h>
#import <poll.h>
#import <signal.h>
#import <sys/types.h>
#import <sys/wait.h>
#import <util.h>
#import <unistd.h>

static NSString *const TUMProviderErrorDomain = @"TUMProviderErrorDomain";

static NSError *TUMProviderError(NSString *description) {
    return [NSError errorWithDomain:TUMProviderErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

NSString *TUMFindExecutable(NSArray<NSString *> *candidates) {
    NSFileManager *manager = NSFileManager.defaultManager;
    for (NSString *candidate in candidates) {
        NSString *path = [candidate stringByExpandingTildeInPath];
        if ([manager isExecutableFileAtPath:path]) {
            return path;
        }
    }
    return nil;
}

@implementation TUMClaudeProvider

- (NSString *)providerID { return @"claude"; }
- (NSTimeInterval)minimumRefreshInterval { return 60.0; }

- (void)refreshWithCompletion:(TUMProviderCompletion)completion {
    NSString *account = NSUserName();
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"Claude Code-credentials",
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || result == NULL) {
        completion(nil, TUMProviderError(
            @"Claude Code login was not found in Keychain. Run `claude` and sign in first."
        ));
        return;
    }

    NSData *credentialData = CFBridgingRelease(result);
    NSError *jsonError = nil;
    NSDictionary *credentials = [NSJSONSerialization JSONObjectWithData:credentialData
                                                                  options:0
                                                                    error:&jsonError];
    NSString *token = [credentials[@"claudeAiOauth"][@"accessToken"]
        isKindOfClass:NSString.class]
        ? credentials[@"claudeAiOauth"][@"accessToken"]
        : nil;
    if (token.length == 0) {
        completion(nil, jsonError != nil
            ? jsonError
            : TUMProviderError(@"Claude Keychain record has no OAuth token."));
        return;
    }

    NSURL *url = [NSURL URLWithString:@"https://api.anthropic.com/api/oauth/usage"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 8.0;
    [request setValue:[@"Bearer " stringByAppendingString:token]
    forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"oauth-2025-04-20" forHTTPHeaderField:@"anthropic-beta"];
    [request setValue:@"TouchBarUsageMonitor/0.2.1" forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [NSURLSession.sharedSession
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
            if (networkError != nil) {
                completion(nil, networkError);
                return;
            }
            NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
            if (statusCode != 200) {
                completion(nil, TUMProviderError([
                    NSString stringWithFormat:@"Claude usage endpoint returned HTTP %ld. Open Claude Code to refresh login.",
                                              (long)statusCode
                ]));
                return;
            }
            NSError *parseError = nil;
            TUMProviderUsage *usage = TUMParseClaudeUsageJSON(data, &parseError);
            completion(usage, parseError);
          }];
    [task resume];
}

@end

@implementation TUMCodexProvider

- (NSString *)providerID { return @"codex"; }
- (NSTimeInterval)minimumRefreshInterval { return 60.0; }

- (void)refreshWithCompletion:(TUMProviderCompletion)completion {
    NSString *codex = TUMFindExecutable(@[
        @"~/.local/bin/codex",
        @"/opt/homebrew/bin/codex",
        @"/usr/local/bin/codex"
    ]);
    if (codex == nil) {
        completion(nil, TUMProviderError(@"Codex CLI was not found."));
        return;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:codex];
    task.arguments = @[@"app-server", @"--stdio"];
    task.currentDirectoryURL = [NSURL fileURLWithPath:NSHomeDirectory()];

    NSPipe *inputPipe = [NSPipe pipe];
    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    task.standardInput = inputPipe;
    task.standardOutput = outputPipe;
    task.standardError = errorPipe;

    __block BOOL finished = NO;
    __block NSMutableData *pending = [NSMutableData data];
    __weak NSTask *weakTask = task;
    __weak NSFileHandle *weakOutput = outputPipe.fileHandleForReading;

    void (^finish)(TUMProviderUsage *, NSError *) = ^(TUMProviderUsage *usage,
                                                       NSError *error) {
        @synchronized (task) {
            if (finished) {
                return;
            }
            finished = YES;
        }
        weakOutput.readabilityHandler = nil;
        if (weakTask.isRunning) {
            [weakTask terminate];
        }
        completion(usage, error);
    };

    outputPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *chunk = handle.availableData;
        if (chunk.length == 0) {
            return;
        }
        [pending appendData:chunk];

        while (YES) {
            const void *bytes = pending.bytes;
            const void *newline = memchr(bytes, '\n', pending.length);
            if (newline == NULL) {
                break;
            }
            NSUInteger lineLength = (const uint8_t *)newline - (const uint8_t *)bytes;
            NSData *lineData = [pending subdataWithRange:NSMakeRange(0, lineLength)];
            [pending replaceBytesInRange:NSMakeRange(0, lineLength + 1)
                               withBytes:NULL
                                  length:0];
            NSDictionary *message = [NSJSONSerialization JSONObjectWithData:lineData
                                                                     options:0
                                                                       error:nil];
            if ([message[@"id"] integerValue] != 2 || message[@"result"] == nil) {
                continue;
            }
            NSError *parseError = nil;
            TUMProviderUsage *usage = TUMParseCodexRateLimitJSON(lineData, &parseError);
            finish(usage, parseError);
            break;
        }
    };

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        outputPipe.fileHandleForReading.readabilityHandler = nil;
        completion(nil, launchError);
        return;
    }

    NSArray<NSDictionary *> *messages = @[
        @{
            @"method": @"initialize",
            @"id": @1,
            @"params": @{
                @"clientInfo": @{
                    @"name": @"touchbar_usage_monitor",
                    @"title": @"Touch Bar Usage Monitor",
                    @"version": @"0.2.1"
                },
                @"capabilities": @{
                    @"optOutNotificationMethods": @[
                        @"thread/started",
                        @"item/agentMessage/delta"
                    ]
                }
            }
        },
        @{@"method": @"initialized"},
        @{@"method": @"account/rateLimits/read", @"id": @2}
    ];
    NSMutableData *requestData = [NSMutableData data];
    for (NSDictionary *message in messages) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
        [requestData appendData:json];
        [requestData appendBytes:"\n" length:1];
    }
    [inputPipe.fileHandleForWriting writeData:requestData];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        finish(nil, TUMProviderError(@"Codex rate-limit request timed out."));
    });
}

@end

@implementation TUMAntigravityProvider

- (NSString *)providerID { return @"antigravity"; }
- (NSTimeInterval)minimumRefreshInterval { return 300.0; }

- (void)refreshWithCompletion:(TUMProviderCompletion)completion {
    NSString *agy = TUMFindExecutable(@[
        @"~/.local/bin/agy",
        @"/opt/homebrew/bin/agy",
        @"/usr/local/bin/agy"
    ]);
    if (agy == nil) {
        completion(nil, TUMProviderError(@"Antigravity CLI (`agy`) was not found."));
        return;
    }

    NSString *configuredWorkspace = NSProcessInfo.processInfo.environment[
        @"TUM_ANTIGRAVITY_WORKSPACE"
    ];
    NSString *workspace = configuredWorkspace.length > 0
        ? [configuredWorkspace stringByExpandingTildeInPath]
        : NSFileManager.defaultManager.currentDirectoryPath;
    BOOL isDirectory = NO;
    if (workspace.length == 0 ||
        ![NSFileManager.defaultManager fileExistsAtPath:workspace
                                            isDirectory:&isDirectory] ||
        !isDirectory) {
        workspace = NSHomeDirectory();
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int masterFD = -1;
        struct winsize windowSize = {
            .ws_row = 30,
            .ws_col = 100,
            .ws_xpixel = 0,
            .ws_ypixel = 0
        };
        pid_t child = forkpty(&masterFD, NULL, NULL, &windowSize);
        if (child < 0) {
            completion(nil, TUMProviderError(@"Could not start an Antigravity pseudo-terminal."));
            return;
        }
        if (child == 0) {
            chdir(workspace.fileSystemRepresentation);
            setenv("TERM", "xterm-256color", 1);
            setenv("NO_COLOR", "1", 1);
            execl(agy.fileSystemRepresentation, agy.lastPathComponent.UTF8String, NULL);
            _exit(127);
        }

        fcntl(masterFD, F_SETFL, fcntl(masterFD, F_GETFL) | O_NONBLOCK);
        NSMutableData *captured = [NSMutableData data];
        NSDate *startedAt = [NSDate date];
        NSDate *quotaOpenedAt = nil;
        BOOL sentUsage = NO;
        BOOL sentBottom = NO;
        TUMProviderUsage *parsedUsage = nil;
        NSError *parseError = nil;

        while ([[NSDate date] timeIntervalSinceDate:startedAt] < 16.0) {
            struct pollfd pollDescriptor = {.fd = masterFD, .events = POLLIN, .revents = 0};
            int pollResult = poll(&pollDescriptor, 1, 250);
            if (pollResult > 0 && (pollDescriptor.revents & POLLIN)) {
                uint8_t buffer[8192];
                ssize_t count = read(masterFD, buffer, sizeof(buffer));
                if (count > 0) {
                    [captured appendBytes:buffer length:(NSUInteger)count];
                    if (captured.length > 1024 * 1024) {
                        [captured replaceBytesInRange:NSMakeRange(0, captured.length - 1024 * 1024)
                                           withBytes:NULL
                                              length:0];
                    }
                }
            }

            NSString *decoded = [[NSString alloc] initWithData:captured
                                                       encoding:NSUTF8StringEncoding];
            NSString *raw = decoded != nil ? decoded : @"";
            NSString *clean = TUMStripTerminalControlSequences(raw);
            NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startedAt];

            if ([clean rangeOfString:@"Do you trust the contents"
                              options:NSCaseInsensitiveSearch].location != NSNotFound) {
                parseError = TUMProviderError([
                    NSString stringWithFormat:
                        @"Antigravity needs workspace trust. Run `cd \"%@\" && agy` once.",
                        workspace
                ]);
                break;
            }

            if (!sentUsage && (elapsed >= 3.5 ||
                [clean rangeOfString:@"for shortcuts" options:NSCaseInsensitiveSearch].location != NSNotFound)) {
                const char *command = "/usage\r";
                write(masterFD, command, strlen(command));
                sentUsage = YES;
            }
            if (quotaOpenedAt == nil &&
                [clean rangeOfString:@"Models & Quota" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                quotaOpenedAt = [NSDate date];
            }
            if (sentUsage && !sentBottom && quotaOpenedAt != nil &&
                [[NSDate date] timeIntervalSinceDate:quotaOpenedAt] >= 0.8) {
                const char *controlEnd = "\x1b[1;5F";
                write(masterFD, controlEnd, strlen(controlEnd));
                sentBottom = YES;
            }
            if (sentBottom &&
                [clean rangeOfString:@"Within each group" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                parsedUsage = TUMParseAntigravityOutput(raw, [NSDate date], &parseError);
                if (parsedUsage != nil) {
                    break;
                }
            }
        }

        kill(child, SIGTERM);
        close(masterFD);
        waitpid(child, NULL, 0);

        if (parsedUsage == nil && parseError == nil) {
            NSString *raw = [[NSString alloc] initWithData:captured
                                                   encoding:NSUTF8StringEncoding];
            NSString *clean = raw == nil ? @"" : TUMStripTerminalControlSequences(raw);
            NSString *stage = [clean rangeOfString:@"Models & Quota"
                                           options:NSCaseInsensitiveSearch].location != NSNotFound
                ? @"quota view opened but did not render completely"
                : (sentUsage ? @"command sent but quota view did not open" : @"prompt never became ready");
            parseError = TUMProviderError([
                NSString stringWithFormat:@"Antigravity `/usage` timed out (%@).", stage
            ]);
            if ([NSProcessInfo.processInfo.environment[@"TUM_DEBUG"] boolValue]) {
                NSString *tail = clean.length > 4000
                    ? [clean substringFromIndex:clean.length - 4000]
                    : clean;
                fprintf(stderr, "--- sanitized Antigravity tail ---\n%s\n--- end tail ---\n",
                        tail.UTF8String);
            }
        }
        completion(parsedUsage, parseError);
    });
}

@end
