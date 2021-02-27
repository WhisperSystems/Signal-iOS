//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SwiftProtobuf

// MARK: - Contact Record

extension StorageServiceProtoContactRecord {

    // MARK: - Dependencies

    static var profileManager: OWSProfileManager {
        return .shared()
    }

    var profileManager: OWSProfileManager {
        return .shared()
    }

    static var blockingManager: OWSBlockingManager {
        return .shared()
    }

    var blockingManager: OWSBlockingManager {
        return .shared()
    }

    static var identityManager: OWSIdentityManager {
        return .shared()
    }

    var identityManager: OWSIdentityManager {
        return .shared()
    }

    // MARK: -

    static func build(
        for accountId: AccountId,
        unknownFields: SwiftProtobuf.UnknownStorage? = nil,
        transaction: SDSAnyReadTransaction
    ) throws -> StorageServiceProtoContactRecord {
        guard let address = OWSAccountIdFinder.address(forAccountId: accountId, transaction: transaction) else {
            throw StorageService.StorageError.accountMissing
        }

        var builder = StorageServiceProtoContactRecord.builder()

        if let phoneNumber = address.phoneNumber {
            builder.setServiceE164(phoneNumber)
        }

        if let uuidString = address.uuidString {
            builder.setServiceUuid(uuidString)
        }

        let isInWhitelist = profileManager.isUser(inProfileWhitelist: address, transaction: transaction)
        let profileKey = profileManager.profileKeyData(for: address, transaction: transaction)
        let profileGivenName = profileManager.unfilteredGivenName(for: address, transaction: transaction)
        let profileFamilyName = profileManager.unfilteredFamilyName(for: address, transaction: transaction)

        builder.setBlocked(blockingManager.isAddressBlocked(address))
        builder.setWhitelisted(isInWhitelist)

        // Identity

        if let identityKey = identityManager.identityKey(for: address, transaction: transaction) {
            builder.setIdentityKey(identityKey.prependKeyType())
        }

        let verificationState = identityManager.verificationState(for: address, transaction: transaction)
        builder.setIdentityState(.from(verificationState))

        // Profile

        if let profileKey = profileKey {
            builder.setProfileKey(profileKey)
        }

        if let profileGivenName = profileGivenName {
            builder.setGivenName(profileGivenName)
        }

        if let profileFamilyName = profileFamilyName {
            builder.setFamilyName(profileFamilyName)
        }

        if let thread = TSContactThread.getWithContactAddress(address, transaction: transaction) {
            builder.setArchived(thread.isArchived)
            builder.setMarkedUnread(thread.isMarkedUnread)
        }

        if let unknownFields = unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        return try builder.build()
    }

    enum MergeState {
        case resolved(AccountId)
        case needsUpdate(AccountId)
        case invalid
    }

    func mergeWithLocalContact(transaction: SDSAnyWriteTransaction) -> MergeState {
        guard let address = serviceAddress else {
            owsFailDebug("address unexpectedly missing for contact")
            return .invalid
        }

        // Our general merge philosophy is that the latest value on the service
        // is always right. There are some edge cases where this could cause
        // user changes to get blown away, such as if you're changing values
        // simultaneously on two devices or if you force quit the application,
        // your battery dies, etc. before it has had a chance to sync.
        //
        // In general, to try and mitigate these issues, we try and very proactively
        // push any changes up to the storage service as contact information
        // should not be changing very frequently.
        //
        // Should this prove unreliable, we may need to start maintaining time stamps
        // representing the remote and local last update time for every value we sync.
        // For now, we'd like to avoid that as it adds its own set of problems.

        // Mark the user as registered, only registered contacts should exist in the sync'd data.
        let recipient = SignalRecipient.mark(asRegisteredAndGet: address, trustLevel: .high, transaction: transaction)

        var mergeState: MergeState = .resolved(recipient.accountId)

        // Gather some local contact state to do comparisons against.
        let localProfileKey = profileManager.profileKey(for: address, transaction: transaction)
        let localGivenName = profileManager.unfilteredGivenName(for: address, transaction: transaction)
        let localFamilyName = profileManager.unfilteredFamilyName(for: address, transaction: transaction)
        let localIdentityKey = identityManager.identityKey(for: address, transaction: transaction)
        let localIdentityState = identityManager.verificationState(for: address, transaction: transaction)
        let localIsBlocked = blockingManager.isAddressBlocked(address)
        let localIsWhitelisted = profileManager.isUser(inProfileWhitelist: address, transaction: transaction)

        // If our local profile key record differs from what's on the service, use the service's value.
        if let profileKey = profileKey, localProfileKey?.keyData != profileKey {
            profileManager.setProfileKeyData(
                profileKey,
                for: address,
                wasLocallyInitiated: false,
                transaction: transaction
            )

        // If we have a local profile key for this user but the service doesn't mark it as needing update.
        } else if localProfileKey != nil && !hasProfileKey {
            mergeState = .needsUpdate(recipient.accountId)
        }

        if hasGivenName && localGivenName != givenName || hasFamilyName && localFamilyName != familyName {
            profileManager.setProfileGivenName(
                givenName,
                familyName: familyName,
                for: address,
                wasLocallyInitiated: false,
                transaction: transaction
            )
        } else if localGivenName != nil && !hasGivenName || localFamilyName != nil && !hasFamilyName {
            mergeState = .needsUpdate(recipient.accountId)
        }

        // If our local identity differs from the service, use the service's value.
        if let identityKeyWithType = identityKey, let identityState = identityState?.verificationState,
            let identityKey = try? identityKeyWithType.removeKeyType(),
            localIdentityKey != identityKey || localIdentityState != identityState {

            identityManager.setVerificationState(
                identityState,
                identityKey: identityKey,
                address: address,
                isUserInitiatedChange: false,
                transaction: transaction
            )

        // If we have a local identity for this user but the service doesn't mark it as needing update.
        } else if localIdentityKey != nil && !hasIdentityKey {
            mergeState = .needsUpdate(recipient.accountId)
        }

        // If our local blocked state differs from the service state, use the service's value.
        if blocked != localIsBlocked {
            if blocked {
                blockingManager.addBlockedAddress(address, blockMode: .remote, transaction: transaction)
            } else {
                blockingManager.removeBlockedAddress(address, wasLocallyInitiated: false, transaction: transaction)
            }
        }

        // If our local whitelisted state differs from the service state, use the service's value.
        if whitelisted != localIsWhitelisted {
            if whitelisted {
                profileManager.addUser(toProfileWhitelist: address, wasLocallyInitiated: false, transaction: transaction)
            } else {
                profileManager.removeUser(fromProfileWhitelist: address, wasLocallyInitiated: false, transaction: transaction)
            }
        }

        if let localThread = TSContactThread.getWithContactAddress(address, transaction: transaction) {
            if archived != localThread.isArchived {
                if archived {
                    localThread.archiveThread(updateStorageService: false, transaction: transaction)
                } else {
                    localThread.unarchiveThread(updateStorageService: false, transaction: transaction)
                }
            }

            if markedUnread != localThread.isMarkedUnread {
                if markedUnread {
                    localThread.markAsUnread(updateStorageService: false, transaction: transaction)
                } else {
                    localThread.clearMarkedAsUnread(updateStorageService: false, transaction: transaction)
                }
            }
        }

        return mergeState
    }
}

// MARK: -

extension StorageServiceProtoContactRecordIdentityState {
    static func from(_ state: OWSVerificationState) -> StorageServiceProtoContactRecordIdentityState {
        switch state {
        case .verified:
            return .verified
        case .default:
            return .default
        case .noLongerVerified:
            return .unverified
        }
    }

    var verificationState: OWSVerificationState {
        switch self {
        case .verified:
            return .verified
        case .default:
            return .default
        case .unverified:
            return .noLongerVerified
        case .UNRECOGNIZED:
            owsFailDebug("unrecognized verification state")
            return .default
        }
    }
}

// MARK: - Group V1 Record

extension StorageServiceProtoGroupV1Record {

    // MARK: - Dependencies

    static var profileManager: OWSProfileManager {
        return .shared()
    }

    var profileManager: OWSProfileManager {
        return .shared()
    }

    static var blockingManager: OWSBlockingManager {
        return .shared()
    }

    var blockingManager: OWSBlockingManager {
        return .shared()
    }

    // MARK: -

    static func build(
        for groupId: Data,
        unknownFields: SwiftProtobuf.UnknownStorage? = nil,
        transaction: SDSAnyReadTransaction
    ) throws -> StorageServiceProtoGroupV1Record {

        var builder = StorageServiceProtoGroupV1Record.builder(id: groupId)

        builder.setWhitelisted(profileManager.isGroupId(inProfileWhitelist: groupId, transaction: transaction))
        builder.setBlocked(blockingManager.isGroupIdBlocked(groupId))

        if let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
            builder.setArchived(thread.isArchived)
            builder.setMarkedUnread(thread.isMarkedUnread)
        }

        if let unknownFields = unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        return try builder.build()
    }

    // Embeds the group id.
    enum MergeState {
        case resolved(Data)
        case needsUpdate(Data)
        case invalid
    }

    func mergeWithLocalGroup(transaction: SDSAnyWriteTransaction) -> MergeState {
        // We might be learning of a v1 group id for the first time that
        // corresponds to a v2 group without a v1-to-v2 group id mapping.
        TSGroupThread.ensureGroupIdMapping(forGroupId: id, transaction: transaction)

        // Our general merge philosophy is that the latest value on the service
        // is always right. There are some edge cases where this could cause
        // user changes to get blown away, such as if you're changing values
        // simultaneously on two devices or if you force quit the application,
        // your battery dies, etc. before it has had a chance to sync.
        //
        // In general, to try and mitigate these issues, we try and very proactively
        // push any changes up to the storage service as contact information
        // should not be changing very frequently.
        //
        // Should this prove unreliable, we may need to start maintaining time stamps
        // representing the remote and local last update time for every value we sync.
        // For now, we'd like to avoid that as it adds its own set of problems.

        // Gather some local contact state to do comparisons against.
        let localIsBlocked = blockingManager.isGroupIdBlocked(id)
        let localIsWhitelisted = profileManager.isGroupId(inProfileWhitelist: id, transaction: transaction)

        // If our local blocked state differs from the service state, use the service's value.
        if blocked != localIsBlocked {
            if blocked {
                blockingManager.addBlockedGroupId(id, blockMode: .remote, transaction: transaction)
            } else {
                blockingManager.removeBlockedGroupId(id, wasLocallyInitiated: false, transaction: transaction)
            }
        }

        // If our local whitelisted state differs from the service state, use the service's value.
        if whitelisted != localIsWhitelisted {
            if whitelisted {
                profileManager.addGroupId(toProfileWhitelist: id, wasLocallyInitiated: false, transaction: transaction)
            } else {
                profileManager.removeGroupId(fromProfileWhitelist: id, wasLocallyInitiated: false, transaction: transaction)
            }
        }

        if let localThread = TSGroupThread.fetch(groupId: id, transaction: transaction) {
            if archived != localThread.isArchived {
                if archived {
                    localThread.archiveThread(updateStorageService: false, transaction: transaction)
                } else {
                    localThread.unarchiveThread(updateStorageService: false, transaction: transaction)
                }
            }

            if markedUnread != localThread.isMarkedUnread {
                if markedUnread {
                    localThread.markAsUnread(updateStorageService: false, transaction: transaction)
                } else {
                    localThread.clearMarkedAsUnread(updateStorageService: false, transaction: transaction)
                }
            }
        }

        return .resolved(id)
    }
}

// MARK: - Group V2 Record

extension StorageServiceProtoGroupV2Record {

    // MARK: - Dependencies

    static var profileManager: OWSProfileManager {
        return .shared()
    }

    var profileManager: OWSProfileManager {
        return .shared()
    }

    static var blockingManager: OWSBlockingManager {
        return .shared()
    }

    var blockingManager: OWSBlockingManager {
        return .shared()
    }

    static var groupsV2: GroupsV2 {
        return SSKEnvironment.shared.groupsV2
    }

    var groupsV2: GroupsV2 {
        return SSKEnvironment.shared.groupsV2
    }

    // MARK: -

    static func build(
        for masterKeyData: Data,
        unknownFields: SwiftProtobuf.UnknownStorage? = nil,
        transaction: SDSAnyReadTransaction
    ) throws -> StorageServiceProtoGroupV2Record {

        guard groupsV2.isValidGroupV2MasterKey(masterKeyData) else {
            throw OWSAssertionError("Invalid master key.")
        }

        let groupContextInfo = try groupsV2.groupV2ContextInfo(forMasterKeyData: masterKeyData)
        let groupId = groupContextInfo.groupId

        var builder = StorageServiceProtoGroupV2Record.builder(masterKey: masterKeyData)

        builder.setWhitelisted(profileManager.isGroupId(inProfileWhitelist: groupId, transaction: transaction))
        builder.setBlocked(blockingManager.isGroupIdBlocked(groupId))

        if let thread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
            builder.setArchived(thread.isArchived)
            builder.setMarkedUnread(thread.isMarkedUnread)
        }

        if let unknownFields = unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        return try builder.build()
    }

    // Embeds the master key.
    enum MergeState: CustomStringConvertible {
        case resolved(Data)
        case needsUpdate(Data)
        case needsRefreshFromService(Data)
        case invalid

        // MARK: - CustomStringConvertible

        public var description: String {
            switch self {
            case .resolved:
                return "resolved"
            case .needsUpdate:
                return "needsUpdate"
            case .needsRefreshFromService:
                return "needsRefreshFromService"
            case .invalid:
                return "invalid"
            }
        }
    }

    func mergeWithLocalGroup(transaction: SDSAnyWriteTransaction) -> MergeState {
        // Our general merge philosophy is that the latest value on the service
        // is always right. There are some edge cases where this could cause
        // user changes to get blown away, such as if you're changing values
        // simultaneously on two devices or if you force quit the application,
        // your battery dies, etc. before it has had a chance to sync.
        //
        // In general, to try and mitigate these issues, we try and very proactively
        // push any changes up to the storage service as contact information
        // should not be changing very frequently.
        //
        // Should this prove unreliable, we may need to start maintaining time stamps
        // representing the remote and local last update time for every value we sync.
        // For now, we'd like to avoid that as it adds its own set of problems.

        guard groupsV2.isValidGroupV2MasterKey(masterKey) else {
            owsFailDebug("Invalid master key.")
            return .invalid
        }

        let groupContextInfo: GroupV2ContextInfo
        do {
            groupContextInfo = try groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
        } catch {
            owsFailDebug("Invalid master key.")
            return .invalid
        }
        let groupId = groupContextInfo.groupId

        // We might be learning of a v1 group id for the first time that
        // corresponds to a v2 group without a v1-to-v2 group id mapping.
        TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: transaction)

        var mergeState: MergeState = .resolved(masterKey)

        let isGroupInDatabase = TSGroupThread.fetch(groupId: groupId, transaction: transaction) != nil
        if !isGroupInDatabase {
            mergeState = .needsRefreshFromService(masterKey)
        }

        // Gather some local contact state to do comparisons against.
        let localIsBlocked = blockingManager.isGroupIdBlocked(groupId)
        let localIsWhitelisted = profileManager.isGroupId(inProfileWhitelist: groupId, transaction: transaction)

        // If our local blocked state differs from the service state, use the service's value.
        if blocked != localIsBlocked {
            if blocked {
                blockingManager.addBlockedGroupId(groupId, blockMode: .remote, transaction: transaction)
            } else {
                blockingManager.removeBlockedGroupId(groupId, wasLocallyInitiated: false, transaction: transaction)
            }
        }

        // If our local whitelisted state differs from the service state, use the service's value.
        if whitelisted != localIsWhitelisted {
            if whitelisted {
                profileManager.addGroupId(toProfileWhitelist: groupId, wasLocallyInitiated: false, transaction: transaction)
            } else {
                profileManager.removeGroupId(fromProfileWhitelist: groupId, wasLocallyInitiated: false, transaction: transaction)
            }
        }

        if let localThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
            if archived != localThread.isArchived {
                if archived {
                    localThread.archiveThread(updateStorageService: false, transaction: transaction)
                } else {
                    localThread.unarchiveThread(updateStorageService: false, transaction: transaction)
                }
            }

            if markedUnread != localThread.isMarkedUnread {
                if markedUnread {
                    localThread.markAsUnread(updateStorageService: false, transaction: transaction)
                } else {
                    localThread.clearMarkedAsUnread(updateStorageService: false, transaction: transaction)
                }
            }
        }

        return mergeState
    }
}

// MARK: - Account Record

extension StorageServiceProtoAccountRecord {

    // MARK: - Dependencies

    static var readReceiptManager: OWSReadReceiptManager {
        return .shared()
    }

    var readReceiptManager: OWSReadReceiptManager {
        return .shared()
    }

    static var preferences: OWSPreferences {
        return Environment.shared.preferences
    }

    var preferences: OWSPreferences {
        return Environment.shared.preferences
    }

    static var typingIndicatorsManager: TypingIndicators {
        return SSKEnvironment.shared.typingIndicators
    }

    var typingIndicatorsManager: TypingIndicators {
        return SSKEnvironment.shared.typingIndicators
    }

    static var profileManager: OWSProfileManager {
        return .shared()
    }

    var profileManager: OWSProfileManager {
        return .shared()
    }

    static var tsAccountManager: TSAccountManager {
        return .shared()
    }

    var tsAccountManager: TSAccountManager {
        return .shared()
    }

    static var udManager: OWSUDManager {
        return SSKEnvironment.shared.udManager
    }

    var udManager: OWSUDManager {
        return SSKEnvironment.shared.udManager
    }

    // MARK: -

    static func build(
        unknownFields: SwiftProtobuf.UnknownStorage? = nil,
        transaction: SDSAnyReadTransaction
    ) throws -> StorageServiceProtoAccountRecord {
        guard let localAddress = TSAccountManager.localAddress else {
            throw OWSAssertionError("Missing local address")
        }

        var builder = StorageServiceProtoAccountRecord.builder()

        if let profileKey = profileManager.profileKeyData(for: localAddress, transaction: transaction) {
            builder.setProfileKey(profileKey)
        }

        if let profileGivenName = profileManager.unfilteredGivenName(for: localAddress, transaction: transaction) {
            builder.setGivenName(profileGivenName)
        }
        if let profileFamilyName = profileManager.unfilteredFamilyName(for: localAddress, transaction: transaction) {
            builder.setFamilyName(profileFamilyName)
        }

        if let profileAvatarUrlPath = profileManager.profileAvatarURLPath(for: localAddress, transaction: transaction) {
            builder.setAvatarURL(profileAvatarUrlPath)
        }

        if let thread = TSContactThread.getWithContactAddress(localAddress, transaction: transaction) {
            builder.setNoteToSelfArchived(thread.isArchived)
            builder.setNoteToSelfMarkedUnread(thread.isMarkedUnread)
        }

        let readReceiptsEnabled = readReceiptManager.areReadReceiptsEnabled()
        builder.setReadReceipts(readReceiptsEnabled)

        let sealedSenderIndicatorsEnabled = preferences.shouldShowUnidentifiedDeliveryIndicators(transaction: transaction)
        builder.setSealedSenderIndicators(sealedSenderIndicatorsEnabled)

        let typingIndicatorsEnabled = typingIndicatorsManager.areTypingIndicatorsEnabled()
        builder.setTypingIndicators(typingIndicatorsEnabled)

        let proxiedLinkPreviewsEnabled = SSKPreferences.areLegacyLinkPreviewsEnabled(transaction: transaction)
        builder.setProxiedLinkPreviews(proxiedLinkPreviewsEnabled)

        let linkPreviewsEnabled = SSKPreferences.areLinkPreviewsEnabled(transaction: transaction)
        builder.setLinkPreviews(linkPreviewsEnabled)

        let phoneNumberSharingMode = udManager.phoneNumberSharingMode
        builder.setPhoneNumberSharingMode(phoneNumberSharingMode.asProtoMode)

        let notDiscoverableByPhoneNumber = !tsAccountManager.isDiscoverableByPhoneNumber()
        builder.setNotDiscoverableByPhoneNumber(notDiscoverableByPhoneNumber)

        let pinnedConversationProtos = try PinnedThreadManager.pinnedConversationProtos(transaction: transaction)
        builder.setPinnedConversations(pinnedConversationProtos)

        let preferContactAvatars = SSKPreferences.preferContactAvatars(transaction: transaction)
        builder.setPreferContactAvatars(preferContactAvatars)
        
        let hideGroupChatAvatars = SSKPreferences.hideGroupChatAvatars(transaction: transaction)
        builder.setHideGroupChatAvatars(preferContactAvatars)
        
        if let unknownFields = unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        return try builder.build()
    }

    enum MergeState: String {
        case resolved
        case needsUpdate
    }

    func mergeWithLocalAccount(transaction: SDSAnyWriteTransaction) -> MergeState {
        var mergeState: MergeState = .resolved

        guard let localAddress = TSAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return .needsUpdate
        }

        // Gather some local contact state to do comparisons against.
        let localProfileKey = profileManager.profileKey(for: localAddress, transaction: transaction)
        let localGivenName = profileManager.unfilteredGivenName(for: localAddress, transaction: transaction)
        let localFamilyName = profileManager.unfilteredFamilyName(for: localAddress, transaction: transaction)
        let localAvatarUrl = profileManager.profileAvatarURLPath(for: localAddress, transaction: transaction)

        // If our local profile key record differs from what's on the service, use the service's value.
        if let profileKey = profileKey, localProfileKey?.keyData != profileKey {
            profileManager.setProfileKeyData(
                profileKey,
                for: localAddress,
                wasLocallyInitiated: false,
                transaction: transaction
            )

            // If we have a local profile key for this user but the service doesn't mark it as needing update.
        } else if localProfileKey != nil && !hasProfileKey {
            mergeState = .needsUpdate
        }

        if localGivenName != givenName || localFamilyName != familyName || localAvatarUrl != avatarURL {
            profileManager.setProfileGivenName(
                givenName,
                familyName: familyName,
                avatarUrlPath: avatarURL,
                for: localAddress,
                wasLocallyInitiated: false,
                transaction: transaction
            )
        } else if localGivenName != nil && !hasGivenName || localFamilyName != nil && !hasFamilyName || localAvatarUrl != nil && !hasAvatarURL {
            mergeState = .needsUpdate
        }

        if let localThread = TSContactThread.getWithContactAddress(localAddress, transaction: transaction) {
            if noteToSelfArchived != localThread.isArchived {
                if noteToSelfArchived {
                    localThread.archiveThread(updateStorageService: false, transaction: transaction)
                } else {
                    localThread.unarchiveThread(updateStorageService: false, transaction: transaction)
                }
            }

            if noteToSelfMarkedUnread != localThread.isMarkedUnread {
                if noteToSelfMarkedUnread {
                    localThread.markAsUnread(updateStorageService: false, transaction: transaction)
                } else {
                    localThread.clearMarkedAsUnread(updateStorageService: false, transaction: transaction)
                }
            }
        }

        let localReadReceiptsEnabled = readReceiptManager.areReadReceiptsEnabled()
        if readReceipts != localReadReceiptsEnabled {
            readReceiptManager.setAreReadReceiptsEnabled(readReceipts, transaction: transaction)
        }

        let sealedSenderIndicatorsEnabled = preferences.shouldShowUnidentifiedDeliveryIndicators(transaction: transaction)
        if sealedSenderIndicators != sealedSenderIndicatorsEnabled {
            preferences.setShouldShowUnidentifiedDeliveryIndicators(sealedSenderIndicators, transaction: transaction)
        }

        let typingIndicatorsEnabled = typingIndicatorsManager.areTypingIndicatorsEnabled()
        if typingIndicators != typingIndicatorsEnabled {
            typingIndicatorsManager.setTypingIndicatorsEnabled(value: typingIndicators, transaction: transaction)
        }

        let linkPreviewsEnabled = SSKPreferences.areLinkPreviewsEnabled(transaction: transaction)
        if linkPreviews != linkPreviewsEnabled {
            SSKPreferences.setAreLinkPreviewsEnabled(linkPreviews, transaction: transaction)
        }

        let proxiedLinkPreviewsEnabled = SSKPreferences.areLegacyLinkPreviewsEnabled(transaction: transaction)
        if proxiedLinkPreviews != proxiedLinkPreviewsEnabled {
            SSKPreferences.setAreLegacyLinkPreviewsEnabled(proxiedLinkPreviews, transaction: transaction)
        }

        let localPhoneNumberSharingMode = udManager.phoneNumberSharingMode
        if phoneNumberSharingMode != localPhoneNumberSharingMode.asProtoMode {
            if let localMode = phoneNumberSharingMode?.asLocalMode {
                udManager.setPhoneNumberSharingMode(
                    localMode,
                    updateStorageService: false,
                    transaction: transaction.unwrapGrdbWrite
                )
            } else {
                Logger.error("Unknown phone number sharing mode \(String(describing: phoneNumberSharingMode))")
            }
        }

        let localNotDiscoverableByPhoneNumber = !tsAccountManager.isDiscoverableByPhoneNumber()
        if notDiscoverableByPhoneNumber != localNotDiscoverableByPhoneNumber
            || !tsAccountManager.hasDefinedIsDiscoverableByPhoneNumber() {
            tsAccountManager.setIsDiscoverableByPhoneNumber(
                !notDiscoverableByPhoneNumber,
                updateStorageService: false,
                transaction: transaction
            )
        }

        do {
            try PinnedThreadManager.processPinnedConversationsProto(pinnedConversations, transaction: transaction)
        } catch {
            owsFailDebug("Failed to process pinned conversations \(error)")
            mergeState = .needsUpdate
        }

        let localPrefersContactAvatars = SSKPreferences.preferContactAvatars(transaction: transaction)
        if preferContactAvatars != localPrefersContactAvatars {
            SSKPreferences.setPreferContactAvatars(
                preferContactAvatars,
                updateStorageService: false,
                transaction: transaction)
        }
        
        let localHideGroupChatAvatars = SSKPreferences.hideGroupChatAvatars(transaction: transaction)
        if hideGroupChatAvatars != localHideGroupChatAvatars {
            SSKPreferences.setHideGroupChatAvatars(
                hideGroupChatAvatars,
                updateStorageService: false,
                transaction: transaction)
        }

        
        
        return mergeState
    }
}

// MARK: -

extension PhoneNumberSharingMode {
    var asProtoMode: StorageServiceProtoAccountRecordPhoneNumberSharingMode {
        switch self {
        case .everybody: return .everybody
        case .contactsOnly: return .contactsOnly
        case .nobody: return .nobody
        }
    }
}

extension StorageServiceProtoAccountRecordPhoneNumberSharingMode {
    var asLocalMode: PhoneNumberSharingMode? {
        switch self {
        case .everybody: return .everybody
        case .contactsOnly: return .contactsOnly
        case .nobody: return .nobody
        default:
            owsFailDebug("unexpected case \(self)")
            return nil
        }
    }
}

// MARK: -

extension Data {
    func prependKeyType() -> Data {
        return (self as NSData).prependKeyType() as Data
    }

    func removeKeyType() throws -> Data {
        return try (self as NSData).removeKeyType() as Data
    }
}

// MARK: -

extension PinnedThreadManager {
    static var groupsV2: GroupsV2 {
        SSKEnvironment.shared.groupsV2
    }

    public class func processPinnedConversationsProto(
        _ pinnedConversations: [StorageServiceProtoAccountRecordPinnedConversation],
        transaction: SDSAnyWriteTransaction
    ) throws {
        if pinnedConversations.count > maxPinnedThreads {
            Logger.warn("Received unexpected number of pinned threads (\(pinnedConversations.count))")
        }

        var pinnedThreadIds = [String]()
        for pinnedConversation in pinnedConversations {
            switch pinnedConversation.identifier {
            case .contact(let contact)?:
                let address = SignalServiceAddress(uuidString: contact.uuid, phoneNumber: contact.e164)
                guard address.isValid else {
                    owsFailDebug("Dropping pinned thread with invalid address \(address)")
                    continue
                }
                let thread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: transaction)
                pinnedThreadIds.append(thread.uniqueId)
            case .groupMasterKey(let masterKey)?:
                let contextInfo = try groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
                let threadUniqueId = TSGroupThread.threadId(forGroupId: contextInfo.groupId,
                                                            transaction: transaction)
                pinnedThreadIds.append(threadUniqueId)
            case .legacyGroupID(let groupId)?:
                let threadUniqueId = TSGroupThread.threadId(forGroupId: groupId,
                                                            transaction: transaction)
                pinnedThreadIds.append(threadUniqueId)
            default:
                break
            }
        }

        updatePinnedThreadIds(pinnedThreadIds, transaction: transaction)
    }

    public class func pinnedConversationProtos(
        transaction: SDSAnyReadTransaction
    ) throws -> [StorageServiceProtoAccountRecordPinnedConversation] {
        let pinnedThreads = PinnedThreadManager.pinnedThreads(transaction: transaction)

        var pinnedConversationProtos = [StorageServiceProtoAccountRecordPinnedConversation]()
        for pinnedThread in pinnedThreads {
            var pinnedConversationBuilder = StorageServiceProtoAccountRecordPinnedConversation.builder()

            if let groupThread = pinnedThread as? TSGroupThread {
                if let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 {
                    let masterKeyData: Data
                    do {
                        masterKeyData = try groupsV2.masterKeyData(forGroupModel: groupModelV2)
                    } catch {
                        owsFailDebug("Missing master key: \(error)")
                        continue
                    }
                    guard groupsV2.isValidGroupV2MasterKey(masterKeyData) else {
                        owsFailDebug("Invalid master key.")
                        continue
                    }

                    pinnedConversationBuilder.setIdentifier(.groupMasterKey(masterKeyData))
                } else {
                    pinnedConversationBuilder.setIdentifier(.legacyGroupID(groupThread.groupModel.groupId))
                }

            } else if let contactThread = pinnedThread as? TSContactThread {
                var contactBuilder = StorageServiceProtoAccountRecordPinnedConversationContact.builder()
                if let uuidString = contactThread.contactAddress.uuidString {
                    contactBuilder.setUuid(uuidString)
                } else if let e164 = contactThread.contactAddress.phoneNumber {
                    contactBuilder.setE164(e164)
                } else {
                    owsFailDebug("Missing uuid and phone number for thread")
                }
                pinnedConversationBuilder.setIdentifier(.contact(try contactBuilder.build()))
            }

            pinnedConversationProtos.append(try pinnedConversationBuilder.build())
        }

        return pinnedConversationProtos
    }
}
