//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

@class AnyPromise;
@class OWSAES256Key;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SignalServiceAddress;
@class TSThread;
@class UserProfileReadCache;

NS_ASSUME_NONNULL_BEGIN

@protocol ProfileManagerProtocol <NSObject>

- (OWSAES256Key *)localProfileKey;
// localUserProfileExists is true if there is _ANY_ local profile.
- (BOOL)localProfileExistsWithTransaction:(SDSAnyReadTransaction *)transaction;
// hasLocalProfile is true if there is a local profile with a name or avatar.
- (BOOL)hasLocalProfile;
- (nullable NSString *)localGivenName;
- (nullable NSString *)localFamilyName;
- (nullable NSString *)localFullName;
- (nullable NSString *)localUsername;
- (nullable UIImage *)localProfileAvatarImage;
- (nullable NSData *)localProfileAvatarData;

- (nullable NSString *)fullNameForAddress:(SignalServiceAddress *)address
                              transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSData *)profileKeyDataForAddress:(SignalServiceAddress *)address
                                  transaction:(SDSAnyReadTransaction *)transaction;
- (void)setProfileKeyData:(NSData *)profileKeyData
               forAddress:(SignalServiceAddress *)address
      wasLocallyInitiated:(BOOL)wasLocallyInitiated
              transaction:(SDSAnyWriteTransaction *)transaction;

- (void)fillInMissingProfileKeys:(NSDictionary<SignalServiceAddress *, NSData *> *)profileKeys
    NS_SWIFT_NAME(fillInMissingProfileKeys(_:));

- (void)setProfileGivenName:(nullable NSString *)firstName
                 familyName:(nullable NSString *)lastName
                 forAddress:(SignalServiceAddress *)address
        wasLocallyInitiated:(BOOL)wasLocallyInitiated
                transaction:(SDSAnyWriteTransaction *)transaction;

- (void)setProfileGivenName:(nullable NSString *)firstName
                 familyName:(nullable NSString *)lastName
              avatarUrlPath:(nullable NSString *)avatarUrlPath
                 forAddress:(SignalServiceAddress *)address
        wasLocallyInitiated:(BOOL)wasLocallyInitiated
                transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)isUserInProfileWhitelist:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction;

- (void)addThreadToProfileWhitelist:(TSThread *)thread;
- (void)addThreadToProfileWhitelist:(TSThread *)thread transaction:(SDSAnyWriteTransaction *)transaction;

- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address;
- (void)addUserToProfileWhitelist:(SignalServiceAddress *)address
              wasLocallyInitiated:(BOOL)wasLocallyInitiated
                      transaction:(SDSAnyWriteTransaction *)transaction;

- (void)addUsersToProfileWhitelist:(NSArray<SignalServiceAddress *> *)addresses;

- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address;
- (void)removeUserFromProfileWhitelist:(SignalServiceAddress *)address
                   wasLocallyInitiated:(BOOL)wasLocallyInitiated
                           transaction:(SDSAnyWriteTransaction *)transaction;

- (BOOL)isGroupIdInProfileWhitelist:(NSData *)groupId transaction:(SDSAnyReadTransaction *)transaction;
- (void)addGroupIdToProfileWhitelist:(NSData *)groupId;
- (void)addGroupIdToProfileWhitelist:(NSData *)groupId
                 wasLocallyInitiated:(BOOL)wasLocallyInitiated
                         transaction:(SDSAnyWriteTransaction *)transaction;
- (void)removeGroupIdFromProfileWhitelist:(NSData *)groupId;
- (void)removeGroupIdFromProfileWhitelist:(NSData *)groupId
                      wasLocallyInitiated:(BOOL)wasLocallyInitiated
                              transaction:(SDSAnyWriteTransaction *)transaction;

- (void)fetchAndUpdateLocalUsersProfile;

- (AnyPromise *)fetchLocalUsersProfilePromise;

- (void)updateProfileForAddress:(SignalServiceAddress *)address;

- (AnyPromise *)updateProfileForAddressPromise:(SignalServiceAddress *)address;
- (AnyPromise *)updateProfileForAddressPromise:(SignalServiceAddress *)address
                                   mainAppOnly:(BOOL)mainAppOnly
                              ignoreThrottling:(BOOL)ignoreThrottling;

- (void)updateProfileForAddress:(SignalServiceAddress *)address
           profileNameEncrypted:(nullable NSData *)profileNameEncrypted
                       username:(nullable NSString *)username
                  isUuidCapable:(BOOL)isUuidCapable
                  avatarUrlPath:(nullable NSString *)avatarUrlPath;

- (BOOL)recipientAddressIsUuidCapable:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction;

- (void)warmCaches;

@property (nonatomic, readonly) UserProfileReadCache *userProfileReadCache;
@property (nonatomic, readonly) BOOL hasProfileName;

@end

NS_ASSUME_NONNULL_END
