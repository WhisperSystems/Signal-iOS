//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AppSetup.h"
#import "Environment.h"
#import "VersionMigrations.h"
#import <AxolotlKit/SessionCipher.h>
#import <SignalMessaging/OWSDatabaseMigration.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/OWSStorage.h>

NS_ASSUME_NONNULL_BEGIN

@implementation AppSetup

+ (void)setupEnvironmentWithAppSpecificSingletonBlock:(dispatch_block_t)appSpecificSingletonBlock
                                  migrationCompletion:(dispatch_block_t)migrationCompletion
{
    OWSAssert(appSpecificSingletonBlock);
    OWSAssert(migrationCompletion);

    __block OWSBackgroundTask *_Nullable backgroundTask =
        [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Order matters here.
        //
        // All of these "singletons" should have any dependencies used in their
        // initializers injected.
        [[OWSBackgroundTaskManager sharedManager] observeNotifications];

        OWSPrimaryStorage *primaryStorage = [[OWSPrimaryStorage alloc] initStorage];
        [OWSPrimaryStorage protectFiles];

        OWSPreferences *preferences = [OWSPreferences new];

        TSNetworkManager *networkManager = [[TSNetworkManager alloc] initDefault];
        OWSContactsManager *contactsManager = [[OWSContactsManager alloc] initWithPrimaryStorage:primaryStorage];
        ContactsUpdater *contactsUpdater = [ContactsUpdater new];
        OWSMessageSender *messageSender = [[OWSMessageSender alloc] initWithNetworkManager:networkManager
                                                                            primaryStorage:primaryStorage
                                                                           contactsManager:contactsManager];

        OWSProfileManager *profileManager = [[OWSProfileManager alloc] initWithPrimaryStorage:primaryStorage
                                                                                messageSender:messageSender
                                                                               networkManager:networkManager];

        [Environment setShared:[[Environment alloc] initWithPreferences:preferences]];

        [SSKEnvironment setShared:[[SSKEnvironment alloc] initWithContactsManager:contactsManager
                                                                    messageSender:messageSender
                                                                   profileManager:profileManager
                                                                   primaryStorage:primaryStorage
                                                                  contactsUpdater:contactsUpdater
                                                                   networkManager:networkManager]];

        appSpecificSingletonBlock();

        OWSAssert(SSKEnvironment.shared.isComplete);

        // Register renamed classes.
        [NSKeyedUnarchiver setClass:[OWSUserProfile class] forClassName:[OWSUserProfile collection]];
        [NSKeyedUnarchiver setClass:[OWSDatabaseMigration class] forClassName:[OWSDatabaseMigration collection]];

        [OWSStorage registerExtensionsWithMigrationBlock:^() {
            // Don't start database migrations until storage is ready.
            [VersionMigrations performUpdateCheckWithCompletion:^() {
                OWSAssertIsOnMainThread();

                migrationCompletion();

                OWSAssert(backgroundTask);
                backgroundTask = nil;
            }];
        }];
    });
}

@end

NS_ASSUME_NONNULL_END
