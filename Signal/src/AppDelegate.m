//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "AppDelegate.h"
#import "ConversationListViewController.h"
#import "DebugLogger.h"
#import "MainAppContext.h"
#import "OWSDeviceProvisioningURLParser.h"
#import "OWSOrphanDataCleaner.h"
#import "OWSScreenLockUI.h"
#import "Pastelog.h"
#import "Signal-Swift.h"
#import "SignalApp.h"
#import "ViewControllerUtils.h"
#import <Intents/Intents.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/iOSVersions.h>
#import <SignalMessaging/AppSetup.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSNavigationController.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging.h>
#import <SignalMessaging/VersionMigrations.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/CallKitIdStore.h>
#import <SignalServiceKit/DarwinNotificationCenter.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/OWS2FAManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesJob.h>
#import <SignalServiceKit/OWSMath.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSReceiptManager.h>
#import <SignalServiceKit/SSKEnvironment.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/StickerInfo.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSPreKeyManager.h>
#import <SignalServiceKit/TSSocketManager.h>
#import <UserNotifications/UserNotifications.h>
#import <WebRTC/WebRTC.h>

NSString *const AppDelegateStoryboardMain = @"Main";

static NSString *const kInitialViewControllerIdentifier = @"UserInitialViewController";
NSString *const kURLSchemeSGNLKey = @"sgnl";
static NSString *const kURLHostVerifyPrefix             = @"verify";
static NSString *const kURLHostAddStickersPrefix = @"addstickers";
NSString *const kURLHostTransferPrefix = @"transfer";
NSString *const kURLHostLinkDevicePrefix = @"linkdevice";

static NSTimeInterval launchStartedAt;

typedef NS_ENUM(NSUInteger, LaunchFailure) {
    LaunchFailure_None,
    LaunchFailure_CouldNotLoadDatabase,
    LaunchFailure_UnknownDatabaseVersion,
    LaunchFailure_CouldNotRestoreTransferredData,
    LaunchFailure_DatabaseUnrecoverablyCorrupted
};

NSString *NSStringForLaunchFailure(LaunchFailure launchFailure);
NSString *NSStringForLaunchFailure(LaunchFailure launchFailure)
{
    switch (launchFailure) {
        case LaunchFailure_None:
            return @"LaunchFailure_None";
        case LaunchFailure_CouldNotLoadDatabase:
            return @"LaunchFailure_CouldNotLoadDatabase";
        case LaunchFailure_UnknownDatabaseVersion:
            return @"LaunchFailure_UnknownDatabaseVersion";
        case LaunchFailure_CouldNotRestoreTransferredData:
            return @"LaunchFailure_CouldNotRestoreTransferredData";
        case LaunchFailure_DatabaseUnrecoverablyCorrupted:
            return @"LaunchFailure_DatabaseUnrecoverablyCorrupted";
    }
}

#if TESTABLE_BUILD
void uncaughtExceptionHandler(NSException *exception);

void uncaughtExceptionHandler(NSException *exception)
{
    OWSLogError(@"exception: %@", exception);
    OWSLogError(@"name: %@", exception.name);
    OWSLogError(@"reason: %@", exception.reason);
    OWSLogError(@"userInfo: %@", exception.userInfo);
    OWSLogError(@"callStackSymbols: %@", exception.callStackSymbols);
    OWSLogFlush();
}
#endif

@interface AppDelegate () <UNUserNotificationCenterDelegate>

@property (nonatomic) BOOL areVersionMigrationsComplete;
@property (nonatomic) BOOL didAppLaunchFail;

@end

#pragma mark -

@implementation AppDelegate

@synthesize window = _window;

#pragma mark -

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    OWSLogInfo(@"applicationDidEnterBackground.");

    [DDLog flushLog];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    OWSLogInfo(@"applicationWillEnterForeground.");
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    OWSLogInfo(@"applicationDidReceiveMemoryWarning.");
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    OWSLogInfo(@"applicationWillTerminate.");

    [SignalApp.shared applicationWillTerminate];

    [DDLog flushLog];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

#if TESTABLE_BUILD
    NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
#endif
    // This should be the first thing we do.
    SetCurrentAppContext([MainAppContext new]);

    launchStartedAt = CACurrentMediaTime();

    BOOL isLoggingEnabled;
#ifdef DEBUG
    // Specified at Product -> Scheme -> Edit Scheme -> Test -> Arguments -> Environment to avoid things like
    // the phone directory being looked up during tests.
    isLoggingEnabled = TRUE;
    [DebugLogger.sharedLogger enableTTYLogging];
#elif RELEASE
    isLoggingEnabled = OWSPreferences.isLoggingEnabled;
#endif
    if (isLoggingEnabled) {
        [DebugLogger.sharedLogger enableFileLogging];
    }
    if (SSKDebugFlags.audibleErrorLogging) {
        [DebugLogger.sharedLogger enableErrorReporting];
    }
    [DebugLogger configureSwiftLogging];

#ifdef DEBUG
    [SSKFeatureFlags logFlags];
    [SSKDebugFlags logFlags];
#endif

    OWSLogWarn(@"application: didFinishLaunchingWithOptions.");
    [Cryptography seedRandom];

    // This *must* happen before we try and access or verify the database, since we
    // may be in a state where the database has been partially restored from transfer
    // (e.g. the key was replaced, but the database files haven't been moved into place)
    __block BOOL deviceTransferRestoreFailed = NO;
    [BenchManager benchWithTitle:@"Slow device transfer service launch"
                 logIfLongerThan:0.01
                 logInProduction:YES
                           block:^{
                               deviceTransferRestoreFailed = ![DeviceTransferService.shared launchCleanup];
                           }];

    // XXX - careful when moving this. It must happen before we load GRDB.
    [self verifyDBKeysAvailableBeforeBackgroundLaunch];

    // We need to do this _after_ we set up logging, when the keychain is unlocked,
    // but before we access the database, files on disk, or NSUserDefaults.
    NSError *_Nullable launchError = nil;
    LaunchFailure launchFailure = LaunchFailure_None;

    if (deviceTransferRestoreFailed) {
        launchFailure = LaunchFailure_CouldNotRestoreTransferredData;
    } else if (launchError != nil) {
        launchFailure = LaunchFailure_CouldNotLoadDatabase;
    } else if (StorageCoordinator.hasInvalidDatabaseVersion) {
        // Prevent:
        // * Users with an unknown GRDB schema revert to using an earlier GRDB schema.
        launchFailure = LaunchFailure_UnknownDatabaseVersion;
    } else if ([SSKPreferences hasGrdbDatabaseCorruption]) {
        launchFailure = LaunchFailure_DatabaseUnrecoverablyCorrupted;
    }
    if (launchFailure != LaunchFailure_None) {
        OWSLogInfo(@"application: didFinishLaunchingWithOptions failed.");
        [self showUIForLaunchFailure:launchFailure];

        return YES;
    }

    [AppVersion shared];

    [self setupNSEInteroperation];

    if (CurrentAppContext().isRunningTests) {
        return YES;
    }

    [AppSetup
        setupEnvironmentWithAppSpecificSingletonBlock:^{
            // Create AppEnvironment.
            [AppEnvironment.shared setup];
            [SignalApp.shared setup];
        }
        migrationCompletion:^(NSError *_Nullable error) {
            OWSAssertIsOnMainThread();

            if (error != nil) {
                OWSFailDebug(@"Error: %@", error);
                [self showUIForLaunchFailure:LaunchFailure_DatabaseUnrecoverablyCorrupted];
            } else {
                [self versionMigrationsDidComplete];
            }
        }];

    [UIUtil setupSignalAppearence];

    UIWindow *mainWindow = [OWSWindow new];
    self.window = mainWindow;
    CurrentAppContext().mainWindow = mainWindow;
    // Show LoadingViewController until the async database view registrations are complete.
    mainWindow.rootViewController = [LoadingViewController new];
    [mainWindow makeKeyAndVisible];

    // This must happen in appDidFinishLaunching or earlier to ensure we don't
    // miss notifications.
    // Setting the delegate also seems to prevent us from getting the legacy notification
    // notification callbacks upon launch e.g. 'didReceiveLocalNotification'
    UNUserNotificationCenter.currentNotificationCenter.delegate = self;

    // Accept push notification when app is not open
    NSDictionary *remoteNotification = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
    if (remoteNotification) {
        OWSLogInfo(@"Application was launched by tapping a push notification.");
        [self processRemoteNotification:remoteNotification completion:nil];
    }

    [OWSScreenLockUI.shared setupWithRootWindow:self.window];
    [[OWSWindowManager shared] setupWithRootWindow:self.window
                              screenBlockingWindow:OWSScreenLockUI.shared.screenBlockingWindow];
    [OWSScreenLockUI.shared startObserving];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storageIsReady)
                                                 name:StorageIsReadyNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStateDidChange)
                                                 name:NSNotificationNameRegistrationStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationLockDidChange:)
                                                 name:NSNotificationName_2FAStateDidChange
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(spamChallenge:)
                                                 name:SpamChallengeResolver.NeedsCaptchaNotification
                                               object:nil];

    OWSLogInfo(@"application: didFinishLaunchingWithOptions completed.");

    OWSLogInfo(@"launchOptions: %@.", launchOptions);

    [OWSAnalytics appLaunchDidBegin];

    return YES;
}

- (void)spamChallenge:(NSNotification *)notification
{
    UIViewController *fromVC = UIApplication.sharedApplication.frontmostViewController;
    [SpamCaptchaViewController presentActionSheetFrom:fromVC];
}

/**
 *  The user must unlock the device once after reboot before the database encryption key can be accessed.
 */
- (void)verifyDBKeysAvailableBeforeBackgroundLaunch
{
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
        return;
    }

    if (StorageCoordinator.hasGrdbFile && GRDBDatabaseStorageAdapter.isKeyAccessible) {
        return;
    }

    OWSLogInfo(@"exiting because we are in the background and the database password is not accessible.");

    UILocalNotification *notification = [UILocalNotification new];
    NSString *messageFormat = NSLocalizedString(@"NOTIFICATION_BODY_PHONE_LOCKED_FORMAT",
        @"Lock screen notification text presented after user powers on their device without unlocking. Embeds "
        @"{{device model}} (either 'iPad' or 'iPhone')");
    notification.alertBody = [NSString stringWithFormat:messageFormat, UIDevice.currentDevice.localizedModel];

    // Make sure we clear any existing notifications so that they don't start stacking up
    // if the user receives multiple pushes.
    [UIApplication.sharedApplication cancelAllLocalNotifications];
    [UIApplication.sharedApplication setApplicationIconBadgeNumber:0];

    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
    [UIApplication.sharedApplication setApplicationIconBadgeNumber:1];

    [DDLog flushLog];
    exit(0);
}

- (void)showUIForLaunchFailure:(LaunchFailure)launchFailure
{
    OWSLogInfo(@"launchFailure: %@", NSStringForLaunchFailure(launchFailure));

    // Disable normal functioning of app.
    self.didAppLaunchFail = YES;

    // We perform a subset of the [application:didFinishLaunchingWithOptions:].
    [AppVersion shared];

    if (self.window == nil) {
        self.window = [OWSWindow new];
        CurrentAppContext().mainWindow = self.window;
    }

    // Show the launch screen
    UIViewController *viewController = [[UIStoryboard storyboardWithName:@"Launch Screen"
                                                                  bundle:nil] instantiateInitialViewController];
    self.window.rootViewController = viewController;

    [self.window makeKeyAndVisible];

    NSString *alertTitle;
    NSString *alertMessage
        = NSLocalizedString(@"APP_LAUNCH_FAILURE_ALERT_MESSAGE", @"Message for the 'app launch failed' alert.");
    switch (launchFailure) {
        case LaunchFailure_DatabaseUnrecoverablyCorrupted:
            // Fallthrough
        case LaunchFailure_CouldNotLoadDatabase:
            alertTitle = NSLocalizedString(@"APP_LAUNCH_FAILURE_COULD_NOT_LOAD_DATABASE",
                @"Error indicating that the app could not launch because the database could not be loaded.");
            break;
        case LaunchFailure_UnknownDatabaseVersion:
            alertTitle = NSLocalizedString(@"APP_LAUNCH_FAILURE_INVALID_DATABASE_VERSION_TITLE",
                @"Error indicating that the app could not launch without reverting unknown database migrations.");
            alertMessage = NSLocalizedString(@"APP_LAUNCH_FAILURE_INVALID_DATABASE_VERSION_MESSAGE",
                @"Error indicating that the app could not launch without reverting unknown database migrations.");
            break;
        case LaunchFailure_CouldNotRestoreTransferredData:
            alertTitle = NSLocalizedString(@"APP_LAUNCH_FAILURE_RESTORE_FAILED_TITLE",
                @"Error indicating that the app could not restore transferred data.");
            alertMessage = NSLocalizedString(@"APP_LAUNCH_FAILURE_RESTORE_FAILED_MESSAGE",
                @"Error indicating that the app could not restore transferred data.");
            break;
        default:
            OWSFailDebug(@"Unknown launch failure.");
            alertTitle
                = NSLocalizedString(@"APP_LAUNCH_FAILURE_ALERT_TITLE", @"Title for the 'app launch failed' alert.");
            break;
    }

    ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:alertTitle message:alertMessage];

    [actionSheet
        addAction:[[ActionSheetAction alloc] initWithTitle:NSLocalizedString(@"SETTINGS_ADVANCED_SUBMIT_DEBUGLOG", nil)
                                                     style:ActionSheetActionStyleDefault
                                                   handler:^(ActionSheetAction *_Nonnull action) {
                                                       [Pastelog submitLogsWithCompletion:^{
                                                           OWSFail(@"exiting after sharing debug logs.");
                                                       }];
                                                   }]];
    [viewController presentActionSheet:actionSheet];
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }

    OWSLogInfo(@"registered vanilla push token");
    [self.pushRegistrationManager didReceiveVanillaPushToken:deviceToken];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }

    OWSLogError(@"failed to register vanilla push token with error: %@", error);
#ifdef DEBUG
    OWSLogWarn(@"We're in debug mode. Faking success for remote registration with a fake push identifier");
    [self.pushRegistrationManager didReceiveVanillaPushToken:[[NSMutableData dataWithLength:32] copy]];
#else
    OWSProdError([OWSAnalyticsEvents appDelegateErrorFailedToRegisterForRemoteNotifications]);
    [self.pushRegistrationManager didFailToReceiveVanillaPushTokenWithError:error];
#endif
}

- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
{
    OWSAssertIsOnMainThread();

    return [self tryToOpenUrl:url];
}

- (BOOL)tryToOpenUrl:(NSURL *)url
{
    OWSAssertDebug(!self.didAppLaunchFail);

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return NO;
    }

    if ([StickerPackInfo isStickerPackShareUrl:url]) {
        StickerPackInfo *_Nullable stickerPackInfo = [StickerPackInfo parseStickerPackShareUrl:url];
        if (stickerPackInfo == nil) {
            OWSFailDebug(@"Could not parse sticker pack share URL: %@", url);
            return NO;
        }
        return [self tryToShowStickerPackView:stickerPackInfo];
    } else if ([GroupManager isPossibleGroupInviteLink:url]) {
        return [self tryToShowGroupInviteLinkUI:url];
    } else if ([url.scheme isEqualToString:kURLSchemeSGNLKey]) {
        if ([url.host hasPrefix:kURLHostVerifyPrefix] && ![self.tsAccountManager isRegistered]) {
            if (!AppReadiness.isAppReady) {
                OWSFailDebug(@"Ignoring URL; app is not ready.");
                return NO;
            }
            return [SignalApp.shared receivedVerificationCode:[url.path substringFromIndex:1]];
        } else if ([url.host hasPrefix:kURLHostAddStickersPrefix] && [self.tsAccountManager isRegistered]) {
            StickerPackInfo *_Nullable stickerPackInfo = [self parseAddStickersUrl:url];
            if (stickerPackInfo == nil) {
                OWSFailDebug(@"Invalid URL: %@", url);
                return NO;
            }
            return [self tryToShowStickerPackView:stickerPackInfo];
        } else if ([url.host hasPrefix:kURLHostLinkDevicePrefix] && [self.tsAccountManager isRegistered]) {
            OWSDeviceProvisioningURLParser *parser =
                [[OWSDeviceProvisioningURLParser alloc] initWithProvisioningURL:url.absoluteString];
            if (!parser.isValid) {
                OWSFailDebug(@"Invalid URL: %@", url);
                return NO;
            }
            return [self tryToShowLinkDeviceViewWithParser:parser];
        } else {
            OWSLogVerbose(@"Invalid URL: %@", url);
            OWSFailDebug(@"Unknown URL host: %@", url.host);
        }
    } else {
        OWSFailDebug(@"Unknown URL scheme: %@", url.scheme);
    }

    return NO;
}

- (nullable StickerPackInfo *)parseAddStickersUrl:(NSURL *)url
{
    NSString *_Nullable packIdHex;
    NSString *_Nullable packKeyHex;
    NSURLComponents *components = [NSURLComponents componentsWithString:url.absoluteString];
    for (NSURLQueryItem *queryItem in [components queryItems]) {
        if ([queryItem.name isEqualToString:@"pack_id"]) {
            OWSAssertDebug(packIdHex == nil);
            packIdHex = queryItem.value;
        } else if ([queryItem.name isEqualToString:@"pack_key"]) {
            OWSAssertDebug(packKeyHex == nil);
            packKeyHex = queryItem.value;
        } else {
            OWSLogWarn(@"Unknown query item: %@", queryItem.name);
        }
    }

    return [StickerPackInfo parsePackIdHex:packIdHex packKeyHex:packKeyHex];
}

- (BOOL)tryToShowStickerPackView:(StickerPackInfo *)stickerPackInfo
{
    OWSAssertDebug(!self.didAppLaunchFail);
    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        if (!self.tsAccountManager.isRegistered) {
            OWSFailDebug(@"Ignoring sticker pack URL; not registered.");
            return;
        }

        StickerPackViewController *packView =
            [[StickerPackViewController alloc] initWithStickerPackInfo:stickerPackInfo];
        UIViewController *rootViewController = self.window.rootViewController;
        if (rootViewController.presentedViewController) {
            [rootViewController
                dismissViewControllerAnimated:NO
                                   completion:^{ [packView presentFrom:rootViewController animated:NO]; }];
        } else {
            [packView presentFrom:rootViewController animated:NO];
        }
    });
    return YES;
}

- (BOOL)tryToShowLinkDeviceViewWithParser:(OWSDeviceProvisioningURLParser *)parser
{
    OWSAssertDebug(!self.didAppLaunchFail);
    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        if (!self.tsAccountManager.isRegistered) {
            OWSFailDebug(@"Ignoring linked device URL; not registered.");
            return;
        }

        UINavigationController *navController = [AppSettingsViewController inModalNavigationController];
        NSMutableArray<UIViewController *> *viewControllers = [navController.viewControllers mutableCopy];

        LinkedDevicesTableViewController *linkedDevicesVC = [LinkedDevicesTableViewController new];
        [viewControllers addObject:linkedDevicesVC];

        OWSLinkDeviceViewController *linkDeviceVC = [OWSLinkDeviceViewController new];
        [viewControllers addObject:linkDeviceVC];

        linkDeviceVC.delegate = linkedDevicesVC;

        [navController setViewControllers:viewControllers animated:NO];

        UIViewController *rootViewController = self.window.rootViewController;
        if (rootViewController.presentedViewController) {
            [rootViewController dismissViewControllerAnimated:NO
                                                   completion:^{
                                                       [rootViewController presentFormSheetViewController:navController
                                                                                                 animated:NO
                                                                                               completion:^ {}];
                                                   }];
        } else {
            [rootViewController presentFormSheetViewController:navController animated:NO completion:^ {}];
        }

        [linkDeviceVC provisionWithConfirmationWithParser:parser];
    });
    return YES;
}

- (BOOL)tryToShowGroupInviteLinkUI:(NSURL *)url
{
    OWSAssertDebug(!self.didAppLaunchFail);

    if (AppReadiness.isAppReady && !self.tsAccountManager.isRegistered) {
        OWSFailDebug(@"Ignoring URL; not registered.");
        return NO;
    }

    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        if (!self.tsAccountManager.isRegistered) {
            OWSFailDebug(@"Ignoring sticker pack URL; not registered.");
            return;
        }

        UIViewController *rootViewController = self.window.rootViewController;
        if (rootViewController.presentedViewController) {
            [rootViewController dismissViewControllerAnimated:NO
                                                   completion:^{
                                                       [GroupInviteLinksUI openGroupInviteLink:url
                                                                            fromViewController:rootViewController];
                                                   }];
        } else {
            [GroupInviteLinksUI openGroupInviteLink:url fromViewController:rootViewController];
        }
    });
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }

    OWSLogWarn(@"applicationDidBecomeActive.");
    if (CurrentAppContext().isRunningTests) {
        return;
    }

    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{ [self handleActivation]; });

    // Clear all notifications whenever we become active.
    // When opening the app from a notification,
    // AppDelegate.didReceiveLocalNotification will always
    // be called _before_ we become active.
    [self clearAllNotificationsAndRestoreBadgeCount];

    // On every activation, clear old temp directories.
    ClearOldTemporaryDirectories();

    // Ensure that all windows have the correct frame.
    [self.windowManager updateWindowFrames];

    OWSLogInfo(@"applicationDidBecomeActive completed.");
}

- (void)enableBackgroundRefreshIfNecessary
{
    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        if (OWS2FAManager.shared.isRegistrationLockEnabled && [self.tsAccountManager isRegisteredAndReady]) {
            // Ping server once a day to keep-alive reglock clients.
            const NSTimeInterval kBackgroundRefreshInterval = 24 * 60 * 60;
            [[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:kBackgroundRefreshInterval];
        } else {
            [[UIApplication sharedApplication]
                setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalNever];
        }
    });
}

- (void)handleActivation
{
    OWSAssertIsOnMainThread();

    OWSLogWarn(@"handleActivation.");

    // Always check prekeys after app launches, and sometimes check on app activation.
    [TSPreKeyManager checkPreKeysIfNecessary];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        RTCInitializeSSL();

        if ([self.tsAccountManager isRegistered]) {
            // At this point, potentially lengthy DB locking migrations could be running.
            // Avoid blocking app launch by putting all further possible DB access in async block
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                OWSLogInfo(@"running post launch block for registered user: %@", [self.tsAccountManager localAddress]);

                // Clean up any messages that expired since last launch immediately
                // and continue cleaning in the background.
                [self.disappearingMessagesJob startIfNecessary];

                [self enableBackgroundRefreshIfNecessary];

            });
        } else {
            OWSLogInfo(@"running post launch block for unregistered user.");

            // Unregistered user should have no unread messages. e.g. if you delete your account.
            [AppEnvironment.shared.notificationPresenter clearAllNotifications];

            [self.socketManager requestSocketOpen];
        }
    }); // end dispatchOnce for first time we become active

    // Every time we become active...
    if ([self.tsAccountManager isRegistered]) {
        // At this point, potentially lengthy DB locking migrations could be running.
        // Avoid blocking app launch by putting all further possible DB access in async block
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.socketManager requestSocketOpen];
            [Environment.shared.contactsManagerImpl fetchSystemContactsOnceIfAlreadyAuthorized];
            [self.messageFetcherJob runObjc];

            if (![UIApplication sharedApplication].isRegisteredForRemoteNotifications) {
                OWSLogInfo(@"Retrying to register for remote notifications since user hasn't registered yet.");
                // Push tokens don't normally change while the app is launched, so checking once during launch is
                // usually sufficient, but e.g. on iOS11, users who have disabled "Allow Notifications" and disabled
                // "Background App Refresh" will not be able to obtain an APN token. Enabling those settings does not
                // restart the app, so we check every activation for users who haven't yet registered.
                [OWSSyncPushTokensJob run];
            }
        });
    }

    OWSLogInfo(@"handleActivation completed.");
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }

    OWSLogWarn(@"applicationWillResignActive.");

    [self clearAllNotificationsAndRestoreBadgeCount];

    [DDLog flushLog];
}

- (void)clearAllNotificationsAndRestoreBadgeCount
{
    OWSAssertIsOnMainThread();

    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        [AppEnvironment.shared.notificationPresenter clearAllNotifications];
        [OWSMessageUtils.shared updateApplicationBadgeCount];
    });
}

- (void)application:(UIApplication *)application
    performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem
               completionHandler:(void (^)(BOOL succeeded))completionHandler {
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        completionHandler(NO);
        return;
    }

    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        // We need a root view controller set up before we run the block that presents a view controller.
        // In most cases of launching the app, `ensureRootViewController` is called in `checkIfAppIsReady`
        // or in some other ways.
        // But in the case of the home screen quick action when the app is not running, in which case is
        // handled here, it doesn't have a chance to call `ensureRootViewController` because this block is
        // executed before `ensureRootViewController` in `setAppIsReady`.
        // The workaround is to place the execution of the block after the call to `checkIfAppIsReady`,
        // so the root view controller is set by then.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self.tsAccountManager isRegisteredAndReady]) {
                ActionSheetController *controller = [[ActionSheetController alloc]
                    initWithTitle:NSLocalizedString(@"REGISTER_CONTACTS_WELCOME", nil)
                          message:NSLocalizedString(@"REGISTRATION_RESTRICTED_MESSAGE", nil)];

                [controller addAction:[[ActionSheetAction alloc] initWithTitle:CommonStrings.okButton
                                                                         style:ActionSheetActionStyleDefault
                                                                       handler:^(ActionSheetAction *_Nonnull action) {

                                                                       }]];
                UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
                [fromViewController presentViewController:controller
                                                 animated:YES
                                               completion:^{
                                                   completionHandler(NO);
                                               }];
                return;
            }

            [SignalApp.shared showNewConversationView];

            completionHandler(YES);
        });
    });
}

/**
 * Among other things, this is used by "call back" callkit dialog and calling from native contacts app.
 *
 * We always return YES if we are going to try to handle the user activity since
 * we never want iOS to contact us again using a URL.
 *
 * From https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623072-application?language=objc:
 *
 * If you do not implement this method or if your implementation returns NO, iOS tries to
 * create a document for your app to open using a URL.
 */
- (BOOL)application:(UIApplication *)application
    continueUserActivity:(nonnull NSUserActivity *)userActivity
      restorationHandler:(nonnull void (^)(NSArray *_Nullable))restorationHandler
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return NO;
    }

    if ([userActivity.activityType isEqualToString:@"INSendMessageIntent"]) {
        OWSLogInfo(@"got send message intent");

        INInteraction *interaction = [userActivity interaction];
        INIntent *intent = interaction.intent;

        if (![intent isKindOfClass:[INSendMessageIntent class]]) {
            OWSFailDebug(@"unexpected class for send message intent: %@", intent);
            return NO;
        }
        INSendMessageIntent *sendMessageIntent = (INSendMessageIntent *)intent;
        NSString *_Nullable threadUniqueId = sendMessageIntent.conversationIdentifier;
        if (!threadUniqueId) {
            OWSFailDebug(@"Missing thread id for INSendMessageIntent");
            return NO;
        }

        AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
            if (![self.tsAccountManager isRegisteredAndReady]) {
                OWSLogInfo(@"Ignoring user activity; app not ready.");
                return;
            }

            [SignalApp.shared presentConversationAndScrollToFirstUnreadMessageForThreadId:threadUniqueId animated:NO];
        });
        return YES;
    } else if ([userActivity.activityType isEqualToString:@"INStartVideoCallIntent"]) {
        OWSLogInfo(@"got start video call intent");

        INInteraction *interaction = [userActivity interaction];
        INIntent *intent = interaction.intent;

        if (![intent isKindOfClass:[INStartVideoCallIntent class]]) {
            OWSLogError(@"unexpected class for start call video: %@", intent);
            return NO;
        }
        INStartVideoCallIntent *startCallIntent = (INStartVideoCallIntent *)intent;
        NSString *_Nullable handle = startCallIntent.contacts.firstObject.personHandle.value;
        if (!handle) {
            OWSLogWarn(@"unable to find handle in startCallIntent: %@", startCallIntent);
            return NO;
        }

        AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
            if (![self.tsAccountManager isRegisteredAndReady]) {
                OWSLogInfo(@"Ignoring user activity; app not ready.");
                return;
            }

            SignalServiceAddress *_Nullable address = [self addressForIntentHandle:handle];
            if (!address.isValid) {
                OWSLogWarn(@"ignoring attempt to initiate video call to unknown user.");
                return;
            }

            // This intent can be received from more than one user interaction.
            //
            // * It can be received if the user taps the "video" button in the CallKit UI for an
            //   an ongoing call.  If so, the correct response is to try to activate the local
            //   video for that call.
            // * It can be received if the user taps the "video" button for a contact in the
            //   contacts app.  If so, the correct response is to try to initiate a new call
            //   to that user - unless there already is another call in progress.
            SignalCall *_Nullable currentCall = AppEnvironment.shared.callService.currentCall;
            if (currentCall != nil) {
                if (currentCall.isIndividualCall &&
                    [address isEqualToAddress:currentCall.individualCall.remoteAddress]) {
                    OWSLogWarn(@"trying to upgrade ongoing call to video.");
                    [AppEnvironment.shared.callService.individualCallService handleCallKitStartVideo];
                    return;
                } else {
                    OWSLogWarn(@"ignoring INStartVideoCallIntent due to ongoing WebRTC call with another party.");
                    return;
                }
            }

            OutboundIndividualCallInitiator *outboundIndividualCallInitiator
                = AppEnvironment.shared.outboundIndividualCallInitiator;
            OWSAssertDebug(outboundIndividualCallInitiator);
            [outboundIndividualCallInitiator initiateCallWithAddress:address];
        });
        return YES;
    } else if ([userActivity.activityType isEqualToString:@"INStartAudioCallIntent"]) {
        OWSLogInfo(@"got start audio call intent");

        INInteraction *interaction = [userActivity interaction];
        INIntent *intent = interaction.intent;

        if (![intent isKindOfClass:[INStartAudioCallIntent class]]) {
            OWSLogError(@"unexpected class for start call audio: %@", intent);
            return NO;
        }
        INStartAudioCallIntent *startCallIntent = (INStartAudioCallIntent *)intent;
        NSString *_Nullable handle = startCallIntent.contacts.firstObject.personHandle.value;
        if (!handle) {
            OWSLogWarn(@"unable to find handle in startCallIntent: %@", startCallIntent);
            return NO;
        }

        AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
            if (![self.tsAccountManager isRegisteredAndReady]) {
                OWSLogInfo(@"Ignoring user activity; app not ready.");
                return;
            }

            SignalServiceAddress *_Nullable address = [self addressForIntentHandle:handle];
            if (!address.isValid) {
                OWSLogWarn(@"ignoring attempt to initiate audio call to unknown user.");
                return;
            }

            if (AppEnvironment.shared.callService.currentCall != nil) {
                OWSLogWarn(@"ignoring INStartAudioCallIntent due to ongoing WebRTC call.");
                return;
            }

            OutboundIndividualCallInitiator *outboundIndividualCallInitiator
                = AppEnvironment.shared.outboundIndividualCallInitiator;
            OWSAssertDebug(outboundIndividualCallInitiator);
            [outboundIndividualCallInitiator initiateCallWithAddress:address];
        });
        return YES;

    // On iOS 13, all calls triggered from contacts use this intent
    } else if ([userActivity.activityType isEqualToString:@"INStartCallIntent"]) {
        if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(13, 0)) {
            OWSLogError(@"unexpectedly received INStartCallIntent pre iOS13");
            return NO;
        }

        OWSLogInfo(@"got start call intent");

        INInteraction *interaction = [userActivity interaction];
        INIntent *intent = interaction.intent;

        if (![intent isKindOfClass:NSClassFromString(@"INStartCallIntent")]) {
            OWSLogError(@"unexpected class for start call: %@", intent);
            return NO;
        }

        NSArray<INPerson *> *contacts = [intent performSelector:@selector(contacts)];
        NSString *_Nullable handle = contacts.firstObject.personHandle.value;
        if (!handle) {
            OWSLogWarn(@"unable to find handle in startCallIntent: %@", intent);
            return NO;
        }

        AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
            if (![self.tsAccountManager isRegisteredAndReady]) {
                OWSLogInfo(@"Ignoring user activity; app not ready.");
                return;
            }

            SignalServiceAddress *_Nullable address = [self addressForIntentHandle:handle];
            if (!address.isValid) {
                OWSLogWarn(@"ignoring attempt to initiate call to unknown user.");
                return;
            }

            if (AppEnvironment.shared.callService.currentCall != nil) {
                OWSLogWarn(@"ignoring INStartCallIntent due to ongoing WebRTC call.");
                return;
            }

            OutboundIndividualCallInitiator *outboundIndividualCallInitiator
                = AppEnvironment.shared.outboundIndividualCallInitiator;
            OWSAssertDebug(outboundIndividualCallInitiator);
            [outboundIndividualCallInitiator initiateCallWithAddress:address];
        });
        return YES;
    } else if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
        if (userActivity.webpageURL == nil) {
            OWSFailDebug(@"Missing webpageURL.");
            return NO;
        }
        return [self tryToOpenUrl:userActivity.webpageURL];
    } else {
        OWSLogWarn(@"userActivity: %@, but not yet supported.", userActivity.activityType);
    }

    // TODO Something like...
    // *phoneNumber = [[[[[[userActivity interaction] intent] contacts] firstObject] personHandle] value]
    // thread = blah
    // [callUIAdapter startCall:thread]
    //
    // Here's the Speakerbox Example for intent / NSUserActivity handling:
    //
    //    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]?) -> Void) -> Bool {
    //        guard let handle = userActivity.startCallHandle else {
    //            print("Could not determine start call handle from user activity: \(userActivity)")
    //            return false
    //        }
    //
    //        guard let video = userActivity.video else {
    //            print("Could not determine video from user activity: \(userActivity)")
    //            return false
    //        }
    //
    //        callManager.startCall(handle: handle, video: video)
    //        return true
    //    }

    return NO;
}

- (nullable SignalServiceAddress *)addressForIntentHandle:(NSString *)handle
{
    OWSAssertDebug(handle.length > 0);

    if ([handle hasPrefix:CallKitCallManager.kAnonymousCallHandlePrefix]) {
        SignalServiceAddress *_Nullable address = [CallKitIdStore addressForCallKitId:handle];
        if (!address.isValid) {
            OWSLogWarn(@"ignoring attempt to initiate audio call to unknown anonymous signal user.");
            return nil;
        }
        return address;
    }

    for (PhoneNumber *phoneNumber in
        [PhoneNumber tryParsePhoneNumbersFromUserSpecifiedText:handle
                                              clientPhoneNumber:[TSAccountManager localNumber]]) {
        return [[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber.toE164];
    }
    return nil;
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)application:(UIApplication *)application
    supportedInterfaceOrientationsForWindow:(nullable UIWindow *)window
{
    if (CurrentAppContext().isRunningTests) {
        return UIInterfaceOrientationMaskPortrait;
    }

    if (self.didAppLaunchFail) {
        return UIInterfaceOrientationMaskPortrait;
    }

    if (self.hasCall) {
        OWSLogInfo(@"has call");
        // The call-banner window is only suitable for portrait display on iPhone
        if (!UIDevice.currentDevice.isIPad) {
            return UIInterfaceOrientationMaskPortrait;
        }
    }

    UIViewController *_Nullable rootViewController = self.window.rootViewController;
    if (!rootViewController) {
        return UIDevice.currentDevice.defaultSupportedOrienations;
    }
    return rootViewController.supportedInterfaceOrientations;
}

- (BOOL)hasCall
{
    return self.windowManager.hasCall;
}

#pragma mark Push Notifications Delegate Methods

- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    OWSAssertIsOnMainThread();

    if (SSKDebugFlags.verboseNotificationLogging) {
        OWSLogInfo(@"didReceiveRemoteNotification w. completion.");
    }

    [self processRemoteNotification:userInfo
                         completion:^{
                             dispatch_after(
                                 dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                     completionHandler(UIBackgroundFetchResultNewData);
                                 });
                         }];
}

- (void)processRemoteNotification:(NSDictionary *)userInfo completion:(nullable void (^)(void))completion
{
    OWSAssertIsOnMainThread();

    if (self.didAppLaunchFail) {
        OWSFailDebug(@"app launch failed");
        return;
    }
    if (!(AppReadiness.isAppReady && [self.tsAccountManager isRegisteredAndReady])) {
        OWSLogInfo(@"Ignoring remote notification; app not ready.");
        return;
    }

    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        BOOL isSilentPush = [self handleSilentPushContent:userInfo];
        if (!isSilentPush) {
            [self.messageFetcherJob runObjc];
        }
        if (completion != nil) {
            completion();
        }
    });
}

- (void)application:(UIApplication *)application
    performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler
{
    OWSLogInfo(@"performing background fetch");
    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        [self.messageFetcherJob runObjc].then(^{
            // HACK: Call completion handler after n seconds.
            //
            // We don't currently have a convenient API to know when message fetching is *done* when
            // working with the websocket.
            //
            // We *could* substantially rewrite the TSSocketManager to take advantage of the `empty` message
            // But once our REST endpoint is fixed to properly de-enqueue fallback notifications, we can easily
            // use the rest endpoint here rather than the websocket and circumvent making changes to critical code.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                completionHandler(UIBackgroundFetchResultNewData);
            });
        });
    });
}

- (void)versionMigrationsDidComplete
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"versionMigrationsDidComplete");

    self.areVersionMigrationsComplete = YES;

    [self checkIfAppIsReady];
}

- (void)storageIsReady
{
    OWSAssertIsOnMainThread();
    OWSLogInfo(@"storageIsReady");

    [self checkIfAppIsReady];
}

- (void)checkIfAppIsReady
{
    OWSAssertIsOnMainThread();

    // If launch failed, the app will never be ready.
    if (self.didAppLaunchFail) {
        return;
    }

    // App isn't ready until storage is ready AND all version migrations are complete.
    if (!self.areVersionMigrationsComplete) {
        return;
    }
    if (![self.storageCoordinator isStorageReady]) {
        return;
    }
    if ([AppReadiness isAppReady]) {
        // Only mark the app as ready once.
        return;
    }
    BOOL launchJobsAreComplete = [self.launchJobs ensureLaunchJobsWithCompletion:^{
        // If launch jobs need to run, return and
        // call checkIfAppIsReady again when they're complete.
        [self checkIfAppIsReady];
    }];
    if (!launchJobsAreComplete) {
        // Wait for launch jobs to complete.
        return;
    }

    OWSLogInfo(@"checkIfAppIsReady");

    // Note that this does much more than set a flag;
    // it will also run all deferred blocks.
    [AppReadiness setAppIsReady];

    if (CurrentAppContext().isRunningTests) {
        OWSLogVerbose(@"Skipping post-launch logic in tests.");
        return;
    }

    // If user is missing profile name, redirect to onboarding flow.
    if (!SSKEnvironment.shared.profileManager.hasProfileName) {
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [self.tsAccountManager setIsOnboarded:NO transaction:transaction];
        });
    }

    if ([self.tsAccountManager isRegistered]) {
        OWSLogInfo(@"localAddress: %@", TSAccountManager.localAddress);

        // This should happen at any launch, background or foreground.
        [OWSSyncPushTokensJob run];
    }

    [AppVersion.shared mainAppLaunchDidComplete];

    if (!Environment.shared.preferences.hasGeneratedThumbnails) {
        [self.databaseStorage
            asyncReadWithBlock:^(SDSAnyReadTransaction *transaction) {
                [TSAttachment anyEnumerateWithTransaction:transaction
                                                  batched:YES
                                                    block:^(TSAttachment *attachment, BOOL *stop) {
                                                        // no-op. It's sufficient to initWithCoder: each object.
                                                    }];
            }
            completion:^{
                [Environment.shared.preferences setHasGeneratedThumbnails:YES];
            }];
    }

    [SignalApp.shared ensureRootViewController:launchStartedAt];
}

- (void)registrationStateDidChange
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"registrationStateDidChange");

    [self enableBackgroundRefreshIfNecessary];

    if ([self.tsAccountManager isRegisteredAndReady]) {
        AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
            OWSLogInfo(@"localAddress: %@", [self.tsAccountManager localAddress]);

            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                [ExperienceUpgradeFinder markAllCompleteForNewUserWithTransaction:transaction.unwrapGrdbWrite];
            });

            // Start running the disappearing messages job in case the newly registered user
            // enables this feature
            [self.disappearingMessagesJob startIfNecessary];
        });
    }
}

- (void)registrationLockDidChange:(NSNotification *)notification
{
    [self enableBackgroundRefreshIfNecessary];
}

#pragma mark - status bar touches

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    CGPoint location = [[[event allTouches] anyObject] locationInView:[self window]];
    CGRect statusBarFrame = [UIApplication sharedApplication].statusBarFrame;
    if (CGRectContainsPoint(statusBarFrame, location)) {
        OWSLogDebug(@"touched status bar");
        [[NSNotificationCenter defaultCenter] postNotificationName:TappedStatusBarNotification object:nil];
    }
}

#pragma mark - UNUserNotificationsDelegate

- (BOOL)handleSilentPushContent:(NSDictionary *)userInfo
{
    NSString *_Nullable spamChallengeToken = userInfo[@"rateLimitChallenge"];
    NSString *_Nullable preAuthChallengeToken = userInfo[@"challenge"];

    if (spamChallengeToken) {
        SpamChallengeResolver *spamResolver = self.spamChallengeResolver;
        [spamResolver handleIncomingPushChallengeToken:spamChallengeToken];
        return YES;
    } else if (preAuthChallengeToken) {
        [self.pushRegistrationManager didReceiveVanillaPreAuthChallengeToken:preAuthChallengeToken];
        return YES;
    }
    return NO;
}

// The method will be called on the delegate only if the application is in the foreground. If the method is not
// implemented or the handler is not called in a timely manner then the notification will not be presented. The
// application can choose to have the notification presented as a sound, badge, alert and/or in the notification list.
// This decision should be based on whether the information in the notification is otherwise visible to the user.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler
{
    OWSLogInfo(@"");
    // Capture just userInfo; we don't want to retain notification.
    NSDictionary *userInfo = notification.request.content.userInfo;
    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        UNNotificationPresentationOptions options = 0;
        BOOL isSilent = [self handleSilentPushContent:userInfo];

        if (!isSilent) {
            // We need to respect the in-app notification sound preference. This method, which is called
            // for modern UNUserNotification users, could be a place to do that, but since we'd still
            // need to handle this behavior for legacy UINotification users anyway, we "allow" all
            // notification options here, and rely on the shared logic in NotificationPresenter to
            // honor notification sound preferences for both modern and legacy users.
            options |= UNNotificationPresentationOptionAlert;
            options |= UNNotificationPresentationOptionBadge;
            options |= UNNotificationPresentationOptionSound;
        }
        completionHandler(options);
    });
}

// The method will be called on the delegate when the user responded to the notification by opening the application,
// dismissing the notification or choosing a UNNotificationAction. The delegate must be set before the application
// returns from application:didFinishLaunchingWithOptions:.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler
{
    OWSLogInfo(@"");
    AppReadinessRunNowOrWhenAppDidBecomeReadySync(
        ^{ [NotificationActionHandler handleNotificationResponse:response completionHandler:completionHandler]; });
}

- (void)setupNSEInteroperation
{
    // We immediately post a notification letting the NSE know the main app has launched.
    // If it's running it should take this as a sign to terminate so we don't unintentionally
    // try and fetch messages from two processes at once.
    [DarwinNotificationCenter postNotificationName:DarwinNotificationName.mainAppLaunched];

    // We listen to this notification for the lifetime of the application, so we don't
    // record the returned observer token.
    [DarwinNotificationCenter
        addObserverForName:DarwinNotificationName.nseDidReceiveNotification
                     queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)
                usingBlock:^(int token) {
                    OWSLogDebug(@"Handling NSE received notification");

                    // Immediately let the NSE know we will handle this notification so that it
                    // does not attempt to process messages while we are active.
                    [DarwinNotificationCenter postNotificationName:DarwinNotificationName.mainAppHandledNotification];

                    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{ [self.messageFetcherJob runObjc]; });
                }];
}

@end
