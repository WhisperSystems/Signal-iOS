//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseMigration.h"
#import <SignalServiceKit/OWSPrimaryStorage.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDatabaseMigration

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super initWithUniqueId:[self.class migrationId]];
    if (!self) {
        return self;
    }

    _primaryStorage = primaryStorage;

    return self;
}

+ (MTLPropertyStorage)storageBehaviorForPropertyWithKey:(NSString *)propertyKey
{
    if ([propertyKey isEqualToString:@"primaryStorage"]) {
        return MTLPropertyStorageNone;
    } else {
        return [super storageBehaviorForPropertyWithKey:propertyKey];
    }
}

+ (NSString *)migrationId
{
    OWSRaiseException(NSInternalInconsistencyException, @"Must override %@ in subclass", NSStringFromSelector(_cmd));
}

+ (NSString *)collection
{
    // We want all subclasses in the same collection
    return @"OWSDatabaseMigration";
}

- (void)runUpWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSRaiseException(NSInternalInconsistencyException, @"Must override %@ in subclass", NSStringFromSelector(_cmd));
}

- (void)runUpWithCompletion:(OWSDatabaseMigrationCompletion)completion
{
    OWSAssert(completion);

    [self.primaryStorage.newDatabaseConnection
        asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            [self runUpWithTransaction:transaction];
        }
        completionBlock:^{
            DDLogInfo(@"Completed migration %@", self.uniqueId);
            [self save];

            completion();
        }];
}

#pragma mark - Database Connections

#ifdef DEBUG
+ (YapDatabaseConnection *)dbReadConnection
{
    return self.dbReadWriteConnection;
}

// Database migrations need to occur _before_ storage is ready (by definition),
// so we need to use a connection with canWriteBeforeStorageReady set in
// debug builds.
+ (YapDatabaseConnection *)dbReadWriteConnection
{
    static dispatch_once_t onceToken;
    static YapDatabaseConnection *sharedDBConnection;
    dispatch_once(&onceToken, ^{
        sharedDBConnection = [OWSPrimaryStorage sharedManager].newDatabaseConnection;

        OWSAssert([sharedDBConnection isKindOfClass:[OWSDatabaseConnection class]]);
        ((OWSDatabaseConnection *)sharedDBConnection).canWriteBeforeStorageReady = YES;
    });

    return sharedDBConnection;
}

- (YapDatabaseConnection *)dbReadConnection
{
    return OWSDatabaseMigration.dbReadConnection;
}

- (YapDatabaseConnection *)dbReadWriteConnection
{
    return OWSDatabaseMigration.dbReadWriteConnection;
}
#endif

@end

NS_ASSUME_NONNULL_END
