//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSProfilesManager.h"
#import "NSData+hexString.h"
#import "OWSMessageSender.h"
#import "SecurityUtils.h"
#import "TSStorageManager.h"
#import "TSYapDatabaseObject.h"
#import "TextSecureKitEnv.h"

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface AvatarMetadata : TSYapDatabaseObject

// This filename is relative to OWSProfilesManager.profileAvatarsDirPath.
@property (nonatomic, readonly) NSString *fileName;
@property (nonatomic, readonly) NSString *avatarUrl;
@property (nonatomic, readonly) NSString *avatarDigest;

- (instancetype)init NS_UNAVAILABLE;

@end

#pragma mark -

@implementation AvatarMetadata

+ (NSString *)collection
{
    return @"AvatarMetadata";
}

- (instancetype)initWithFileName:(NSString *)fileName
                       avatarUrl:(NSString *)avatarUrl
                    avatarDigest:(NSString *)avatarDigest
{
    // TODO: Local filenames for avatars are guaranteed to be unique.
    self = [super initWithUniqueId:fileName];

    if (!self) {
        return self;
    }

    OWSAssert(fileName.length > 0);
    OWSAssert(avatarUrl.length > 0);
    OWSAssert(avatarDigest.length > 0);
    _fileName = fileName;
    _avatarUrl = avatarUrl;
    _avatarDigest = avatarDigest;

    return self;
}


#pragma mark - NSObject

- (BOOL)isEqual:(AvatarMetadata *)other
{
    return ([other isKindOfClass:[AvatarMetadata class]] && [self.fileName isEqualToString:other.fileName] &&
        [self.avatarUrl isEqualToString:other.avatarUrl] && [self.avatarDigest isEqualToString:other.avatarDigest]);
}

- (NSUInteger)hash
{
    return self.fileName.hash ^ self.avatarUrl.hash ^ self.avatarDigest.hash;
}

@end

#pragma mark -

NSString *const kNSNotificationName_LocalProfileDidChange = @"kNSNotificationName_LocalProfileDidChange";

NSString *const kOWSProfilesManager_Collection = @"kOWSProfilesManager_Collection";
// This key is used to persist the local user's profile key.
NSString *const kOWSProfilesManager_LocalProfileSecretKey = @"kOWSProfilesManager_LocalProfileSecretKey";
NSString *const kOWSProfilesManager_LocalProfileNameKey = @"kOWSProfilesManager_LocalProfileNameKey";
NSString *const kOWSProfilesManager_LocalProfileAvatarMetadataKey
    = @"kOWSProfilesManager_LocalProfileAvatarMetadataKey";

NSString *const kOWSProfilesManager_UserWhitelistCollection = @"kOWSProfilesManager_UserWhitelistCollection";
NSString *const kOWSProfilesManager_GroupWhitelistCollection = @"kOWSProfilesManager_GroupWhitelistCollection";

NSString *const kOWSProfilesManager_KnownProfileKeysCollection = @"kOWSProfilesManager_KnownProfileKeysCollection";

// TODO:
static const NSInteger kProfileKeyLength = 16;

@interface OWSProfilesManager ()

@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

// These properties should only be mutated on the main thread,
// but they may be accessed on other threads.
@property (atomic, nullable) NSString *localProfileName;
@property (atomic, nullable) UIImage *localProfileAvatarImage;
@property (atomic, nullable) AvatarMetadata *localProfileAvatarMetadata;

// These caches are lazy-populated.  The single point truth is the database.
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSNumber *> *userProfileWhitelistCache;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSNumber *> *groupProfileWhitelistCache;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSData *>*knownProfileKeyCache;

@end

#pragma mark -

@implementation OWSProfilesManager

+ (instancetype)sharedManager
{
    static OWSProfilesManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    OWSMessageSender *messageSender = [TextSecureKitEnv sharedEnv].messageSender;

    return [self initWithStorageManager:storageManager messageSender:messageSender];
}

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
                         messageSender:(OWSMessageSender *)messageSender
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert([NSThread isMainThread]);
    OWSAssert(storageManager);
    OWSAssert(messageSender);

    _messageSender = messageSender;
    _dbConnection = storageManager.newDatabaseConnection;
    _userProfileWhitelistCache = [NSMutableDictionary new];
    _groupProfileWhitelistCache = [NSMutableDictionary new];
    _knownProfileKeyCache = [NSMutableDictionary new];

    OWSSingletonAssert();

    // Register this manager with the message sender.
    // This is a circular dependency.
    [messageSender setProfilesManager:self];

    // Try to load.
    _localProfileKey = [self.dbConnection objectForKey:kOWSProfilesManager_LocalProfileSecretKey
                                            inCollection:kOWSProfilesManager_Collection];
    if (!_localProfileKey) {
        // Generate
        _localProfileKey = [OWSProfilesManager generateLocalProfileKey];
        // Persist
        [self.dbConnection setObject:_localProfileKey
                                forKey:kOWSProfilesManager_LocalProfileSecretKey
                          inCollection:kOWSProfilesManager_Collection];
    }
    OWSAssert(_localProfileKey.length == kProfileKeyLength);

    [self loadLocalProfileAsync];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)appLaunchDidBegin
{
    // Do nothing; we only want to make sure this singleton is created on startup.
}

#pragma mark - Local Profile Key

+ (NSData *)generateLocalProfileKey
{
    // TODO:
    DDLogVerbose(@"%@ Profile key generation is not yet implemented.", self.tag);
    return [SecurityUtils generateRandomBytes:kProfileKeyLength];
}

#pragma mark - Local Profile

// This method is use to update client "local profile" state.
- (void)updateLocalProfileName:(nullable NSString *)localProfileName
       localProfileAvatarImage:(nullable UIImage *)localProfileAvatarImage
    localProfileAvatarMetadata:(nullable AvatarMetadata *)localProfileAvatarMetadata
{
    OWSAssert([NSThread isMainThread]);

    // The avatar image and filename should both be set, or neither should be set.
    if (!localProfileAvatarMetadata && localProfileAvatarImage) {
        OWSFail(@"Missing avatar metadata.");
        localProfileAvatarImage = nil;
    }
    if (localProfileAvatarMetadata && !localProfileAvatarImage) {
        OWSFail(@"Missing avatar image.");
        localProfileAvatarMetadata = nil;
    }

    self.localProfileName = localProfileName;
    self.localProfileAvatarImage = localProfileAvatarImage;
    self.localProfileAvatarMetadata = localProfileAvatarMetadata;

    if (localProfileName) {
        [self.dbConnection setObject:localProfileName
                              forKey:kOWSProfilesManager_LocalProfileNameKey
                        inCollection:kOWSProfilesManager_Collection];
    } else {
        [self.dbConnection removeObjectForKey:kOWSProfilesManager_LocalProfileNameKey
                                 inCollection:kOWSProfilesManager_Collection];
    }
    if (localProfileAvatarMetadata) {
        [self.dbConnection setObject:localProfileAvatarMetadata
                              forKey:kOWSProfilesManager_LocalProfileAvatarMetadataKey
                        inCollection:kOWSProfilesManager_Collection];
    } else {
        [self.dbConnection removeObjectForKey:kOWSProfilesManager_LocalProfileAvatarMetadataKey
                                 inCollection:kOWSProfilesManager_Collection];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:kNSNotificationName_LocalProfileDidChange
                                                        object:nil
                                                      userInfo:nil];
}

- (void)updateLocalProfileName:(nullable NSString *)localProfileName
       localProfileAvatarImage:(nullable UIImage *)localProfileAvatarImage
                       success:(void (^)())successBlock
                       failure:(void (^)())failureBlockParameter
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(successBlock);
    OWSAssert(failureBlockParameter);

    // Ensure that the failure block is called on the main thread.
    void (^failureBlock)() = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            failureBlockParameter();
        });
    };

    // The final steps are to:
    //
    // * Try to update the service.
    // * Update client state on success.
    void (^tryToUpdateService)(AvatarMetadata *_Nullable) = ^(AvatarMetadata *_Nullable avatarMetadata) {
        [self updateProfileOnService:localProfileName
            avatarMetadata:avatarMetadata
            success:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self updateLocalProfileName:localProfileName
                           localProfileAvatarImage:localProfileAvatarImage
                        localProfileAvatarMetadata:avatarMetadata];
                    successBlock();
                });
            }
            failure:^{
                failureBlock();
            }];
    };

    // If we have a new avatar image, we must first:
    //
    // * Encode it to JPEG.
    // * Write it to disk.
    // * Upload it to service.
    if (localProfileAvatarImage) {
        if (self.localProfileAvatarMetadata && self.localProfileAvatarImage == localProfileAvatarImage) {
            DDLogVerbose(@"%@ Updating local profile on service with unchanged avatar.", self.tag);
            // If the avatar hasn't changed, reuse the existing metadata.
            tryToUpdateService(self.localProfileAvatarMetadata);
        } else {
            DDLogVerbose(@"%@ Updating local profile on service with new avatar.", self.tag);
            [self writeAvatarToDisk:localProfileAvatarImage
                success:^(NSData *data, NSString *fileName) {
                    [self uploadAvatarToService:data
                        fileName:fileName
                        success:^(AvatarMetadata *avatarMetadata) {
                            tryToUpdateService(avatarMetadata);
                        }
                        failure:^{
                            failureBlock();
                        }];
                }
                failure:^{
                    failureBlock();
                }];
        }
    } else {
        DDLogVerbose(@"%@ Updating local profile on service with no avatar.", self.tag);
        tryToUpdateService(nil);
    }
}

- (void)writeAvatarToDisk:(UIImage *)avatar
                  success:(void (^)(NSData *data, NSString *fileName))successBlock
                  failure:(void (^)())failureBlock
{
    OWSAssert(avatar);
    OWSAssert(successBlock);
    OWSAssert(failureBlock);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (avatar) {
            NSData *_Nullable data = UIImageJPEGRepresentation(avatar, 1.f);
            OWSAssert(data);
            if (data) {
                NSString *fileName = [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"jpg"];
                NSString *filePath = [self.profileAvatarsDirPath stringByAppendingPathComponent:fileName];
                BOOL success = [data writeToFile:filePath atomically:YES];
                OWSAssert(success);
                if (success) {
                    successBlock(data, fileName);
                    return;
                }
            }
        }
        failureBlock();
    });
}

// TODO: The exact API & encryption scheme for avatars is not yet settled.
- (void)uploadAvatarToService:(NSData *)data
                     fileName:(NSString *)fileName
                      success:(void (^)(AvatarMetadata *avatarMetadata))successBlock
                      failure:(void (^)())failureBlock
{
    OWSAssert(data.length > 0);
    OWSAssert(fileName.length > 0);
    OWSAssert(successBlock);
    OWSAssert(failureBlock);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // TODO:
        NSString *avatarUrl = @"avatarUrl";
        NSString *avatarDigest = @"digest";
        AvatarMetadata *avatarMetadata =
            [[AvatarMetadata alloc] initWithFileName:fileName avatarUrl:avatarUrl avatarDigest:avatarDigest];
        if (YES) {
            successBlock(avatarMetadata);
            return;
        }
        failureBlock();
    });
}

// TODO: The exact API & encryption scheme for profiles is not yet settled.
- (void)updateProfileOnService:(nullable NSString *)localProfileName
                avatarMetadata:(nullable AvatarMetadata *)avatarMetadata
                       success:(void (^)())successBlock
                       failure:(void (^)())failureBlock
{
    OWSAssert(successBlock);
    OWSAssert(failureBlock);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // TODO:
        if (YES) {
            successBlock();
            return;
        }
        failureBlock();
    });
}

- (void)loadLocalProfileAsync
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *_Nullable localProfileName = [self.dbConnection objectForKey:kOWSProfilesManager_LocalProfileNameKey
                                                                  inCollection:kOWSProfilesManager_Collection];
        AvatarMetadata *_Nullable localProfileAvatarMetadata =
            [self.dbConnection objectForKey:kOWSProfilesManager_LocalProfileAvatarMetadataKey
                               inCollection:kOWSProfilesManager_Collection];
        UIImage *_Nullable localProfileAvatarImage = nil;
        if (localProfileAvatarMetadata) {
            localProfileAvatarImage = [self loadProfileAvatarWithFilename:localProfileAvatarMetadata.fileName];
            if (!localProfileAvatarImage) {
                localProfileAvatarMetadata = nil;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.localProfileName = localProfileName;
            self.localProfileAvatarImage = localProfileAvatarImage;
            self.localProfileAvatarMetadata = localProfileAvatarMetadata;

            [[NSNotificationCenter defaultCenter] postNotificationName:kNSNotificationName_LocalProfileDidChange
                                                                object:nil
                                                              userInfo:nil];
        });
    });
}

#pragma mark - Profile Whitelist

- (void)addUserToProfileWhitelist:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    [self.dbConnection setObject:@(1) forKey:recipientId inCollection:kOWSProfilesManager_UserWhitelistCollection];
    self.userProfileWhitelistCache[recipientId] = @(YES);
}

- (BOOL)isUserInProfileWhitelist:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    NSNumber *_Nullable value = self.userProfileWhitelistCache[recipientId];
    if (value) {
        return [value boolValue];
    }

    value =
        @(nil != [self.dbConnection objectForKey:recipientId inCollection:kOWSProfilesManager_UserWhitelistCollection]);
    self.userProfileWhitelistCache[recipientId] = value;
    return [value boolValue];
}

- (void)addGroupIdToProfileWhitelist:(NSData *)groupId
{
    OWSAssert(groupId.length > 0);

    NSString *groupIdKey = [groupId hexadecimalString];
    [self.dbConnection setObject:@(1) forKey:groupIdKey inCollection:kOWSProfilesManager_GroupWhitelistCollection];
    self.groupProfileWhitelistCache[groupIdKey] = @(YES);
}

- (BOOL)isGroupIdInProfileWhitelist:(NSData *)groupId
{
    OWSAssert(groupId.length > 0);

    NSString *groupIdKey = [groupId hexadecimalString];
    NSNumber *_Nullable value = self.groupProfileWhitelistCache[groupIdKey];
    if (value) {
        return [value boolValue];
    }

    value =
        @(nil != [self.dbConnection objectForKey:groupIdKey inCollection:kOWSProfilesManager_GroupWhitelistCollection]);
    self.groupProfileWhitelistCache[groupIdKey] = value;
    return [value boolValue];
}

- (void)setContactRecipientIds:(NSArray<NSString *> *)contactRecipientIds
{
    OWSAssert(contactRecipientIds);
    
    // TODO: The persisted whitelist could either be:
    //
    // * Just users manually added to the whitelist.
    // * Also include users auto-added by, for example, being in the user's
    //   contacts or when the user initiates a 1:1 conversation with them, etc.
    for (NSString *recipientId in contactRecipientIds) {
        [self addUserToProfileWhitelist:recipientId];
    }
}

#pragma mark - Known Profile Keys

- (void)setProfileKey:(NSData *)profileKey forRecipientId:(NSString *)recipientId
{
    OWSAssert(profileKey.length == kProfileKeyLength);
    OWSAssert(recipientId.length > 0);
    if (profileKey.length != kProfileKeyLength) {
        return;
    }

    NSData *_Nullable existingProfileKey = [self profileKeyForRecipientId:recipientId];
    if (existingProfileKey &&
        [existingProfileKey isEqual:profileKey]) {
        // Ignore redundant update.
        return;
    }
    
    [self.dbConnection setObject:profileKey
                          forKey:recipientId
                    inCollection:kOWSProfilesManager_KnownProfileKeysCollection];
    self.knownProfileKeyCache[recipientId] = profileKey;
}

- (nullable NSData *)profileKeyForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    NSData *_Nullable profileKey = self.knownProfileKeyCache[recipientId];
    if (profileKey.length > 0) {
        return profileKey;
    }

    profileKey =
    [self.dbConnection objectForKey:recipientId inCollection:kOWSProfilesManager_KnownProfileKeysCollection];
    if (profileKey) {
        OWSAssert(profileKey.length == kProfileKeyLength);
        self.knownProfileKeyCache[recipientId] = profileKey;
    }
    return profileKey;
}

#pragma mark - Avatar Disk Cache

- (nullable UIImage *)loadProfileAvatarWithFilename:(NSString *)fileName
{
    OWSAssert(fileName.length > 0);

    NSString *filePath = [self.profileAvatarsDirPath stringByAppendingPathComponent:fileName];
    UIImage *_Nullable image = [UIImage imageWithContentsOfFile:filePath];
    return image;
}

- (NSString *)profileAvatarsDirPath
{
    static NSString *profileAvatarsDirPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *documentsPath =
            [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        profileAvatarsDirPath = [documentsPath stringByAppendingPathComponent:@"ProfileAvatars"];

        BOOL isDirectory;
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:profileAvatarsDirPath isDirectory:&isDirectory];
        if (exists) {
            OWSAssert(isDirectory);

            DDLogInfo(@"Profile avatars directory already exists");
        } else {
            NSError *error = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:profileAvatarsDirPath
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error];
            if (error) {
                DDLogError(@"Failed to create profile avatars directory: %@", error);
            }
        }
    });
    return profileAvatarsDirPath;
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssert([NSThread isMainThread]);

    @synchronized(self)
    {
        // TODO: Sync if necessary.
    }
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
