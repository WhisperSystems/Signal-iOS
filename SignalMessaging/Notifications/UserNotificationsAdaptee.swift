//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import UserNotifications
import PromiseKit

public class UserNotificationConfig {

    class var allNotificationCategories: Set<UNNotificationCategory> {
        let categories = AppNotificationCategory.allCases.map { notificationCategory($0) }
        return Set(categories)
    }

    class func notificationActions(for category: AppNotificationCategory) -> [UNNotificationAction] {
        return category.actions.compactMap { notificationAction($0) }
    }

    class func notificationCategory(_ category: AppNotificationCategory) -> UNNotificationCategory {
        return UNNotificationCategory(identifier: category.identifier,
                                      actions: notificationActions(for: category),
                                      intentIdentifiers: [],
                                      options: [])
    }

    class func notificationAction(_ action: AppNotificationAction) -> UNNotificationAction? {
        switch action {
        case .answerCall:
            return UNNotificationAction(identifier: action.identifier,
                                        title: CallStrings.answerCallButtonTitle,
                                        options: [.foreground])
        case .callBack:
            return UNNotificationAction(identifier: action.identifier,
                                        title: CallStrings.callBackButtonTitle,
                                        options: [.foreground])
        case .declineCall:
            return UNNotificationAction(identifier: action.identifier,
                                        title: CallStrings.declineCallButtonTitle,
                                        options: [])
        case .markAsRead:
            return UNNotificationAction(identifier: action.identifier,
                                        title: MessageStrings.markAsReadNotificationAction,
                                        options: [])
        case .mute:
            return UNNotificationAction(identifier: action.identifier,
                                        title: MessageStrings.muteNotificationAction,
                                        options: [])
        case .reply:
            return UNTextInputNotificationAction(identifier: action.identifier,
                                                 title: MessageStrings.replyNotificationAction,
                                                 options: [],
                                                 textInputButtonTitle: MessageStrings.sendButton,
                                                 textInputPlaceholder: "")
        case .showThread:
            return UNNotificationAction(identifier: action.identifier,
                                        title: CallStrings.showThreadButtonTitle,
                                        options: [.foreground])
        case .reactWithThumbsUp:
            return UNNotificationAction(identifier: action.identifier,
                                        title: MessageStrings.reactWithThumbsUpNotificationAction,
                                        options: [])

        case .showCallLobby:
            // Currently, .showCallLobby is only used as a default action.
            owsFailDebug("Show call lobby not supported as a UNNotificationAction")
            return nil
        }
    }

    public class func action(identifier: String) -> AppNotificationAction? {
        return AppNotificationAction.allCases.first { notificationAction($0)?.identifier == identifier }
    }

}

class UserNotificationPresenterAdaptee: NSObject {

    private let notificationCenter: UNUserNotificationCenter
    private var notifications: [String: UNNotificationRequest] = [:]

    override init() {
        self.notificationCenter = UNUserNotificationCenter.current()
        super.init()
        SwiftSingletons.register(self)
    }
}

extension UserNotificationPresenterAdaptee: NotificationPresenterAdaptee {

    func registerNotificationSettings() -> Promise<Void> {
        return Promise { resolver in
            notificationCenter.requestAuthorization(options: [.badge, .sound, .alert]) { (granted, error) in
                self.notificationCenter.setNotificationCategories(UserNotificationConfig.allNotificationCategories)

                if granted {
                    Logger.debug("succeeded.")
                } else if error != nil {
                    Logger.error("failed with error: \(error!)")
                } else {
                    Logger.info("failed without error. User denied notification permissions.")
                }

                // Note that the promise is fulfilled regardless of if notification permssions were
                // granted. This promise only indicates that the user has responded, so we can
                // proceed with requesting push tokens and complete registration.
                resolver.fulfill(())
            }
        }
    }

    func notify(category: AppNotificationCategory, title: String?, body: String, threadIdentifier: String?, userInfo: [AnyHashable: Any], sound: OWSSound?) {
        AssertIsOnMainThread()
        notify(category: category, title: title, body: body, threadIdentifier: threadIdentifier, userInfo: userInfo, sound: sound, replacingIdentifier: nil)
    }

    func notify(category: AppNotificationCategory, title: String?, body: String, threadIdentifier: String?, userInfo: [AnyHashable: Any], sound: OWSSound?, replacingIdentifier: String?) {
        AssertIsOnMainThread()

        guard tsAccountManager.isOnboarded() else {
            Logger.info("suppressing notification since user hasn't yet completed onboarding.")
            return
        }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = category.identifier
        content.userInfo = userInfo
        let isAppActive = CurrentAppContext().isMainAppAndActive
        if let sound = sound, sound != OWSStandardSound.none.rawValue {
            content.sound = sound.notificationSound(isQuiet: isAppActive)
        }

        var notificationIdentifier: String = UUID().uuidString
        if let replacingIdentifier = replacingIdentifier {
            notificationIdentifier = replacingIdentifier
            Logger.debug("replacing notification with identifier: \(notificationIdentifier)")
            cancelNotification(identifier: notificationIdentifier)
        }

        let trigger: UNNotificationTrigger?
        let checkForCancel = (category == .incomingMessageWithActions_CanReply ||
                                category == .incomingMessageWithActions_CannotReply ||
                                category == .incomingMessageWithoutActions ||
                                category == .incomingReactionWithActions_CanReply ||
                                category == .incomingReactionWithActions_CannotReply)
        if checkForCancel && hasReceivedSyncMessageRecently {
            assert(userInfo[AppNotificationUserInfoKey.threadId] != nil)
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: kNotificationDelayForRemoteRead, repeats: false)
        } else {
            trigger = nil
        }

        if shouldPresentNotification(category: category, userInfo: userInfo) {
            if let displayableTitle = title?.filterForDisplay {
                content.title = displayableTitle
            }
            if let displayableBody = body.filterForDisplay {
                content.body = displayableBody
            }
        } else {
            // Play sound and vibrate, but without a `body` no banner will show.
            Logger.debug("supressing notification body")
        }

        if let threadIdentifier = threadIdentifier {
            content.threadIdentifier = threadIdentifier
        }

        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)

        Logger.debug("presenting notification with identifier: \(notificationIdentifier)")
        notificationCenter.add(request) { (error: Error?) in
            if let error = error {
                owsFailDebug("Error: \(error)")
                return
            }

            guard notificationIdentifier != UserNotificationPresenterAdaptee.kMigrationNotificationId else {
                return
            }
            DispatchQueue.main.async {
                // If we show any other notification, we can clear the "GRDB migration" notification.
                self.clearNotificationForGRDBMigration()
            }
        }
        notifications[notificationIdentifier] = request
    }

    func cancelNotification(identifier: String) {
        AssertIsOnMainThread()
        notifications.removeValue(forKey: identifier)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelNotification(_ notification: UNNotificationRequest) {
        AssertIsOnMainThread()

        cancelNotification(identifier: notification.identifier)
    }

    func cancelNotifications(threadId: String) {
        AssertIsOnMainThread()
        for notification in notifications.values {
            guard let notificationThreadId = notification.content.userInfo[AppNotificationUserInfoKey.threadId] as? String else {
                continue
            }

            guard notificationThreadId == threadId else {
                continue
            }

            cancelNotification(notification)
        }
    }

    func cancelNotifications(messageId: String) {
        AssertIsOnMainThread()
        for notification in notifications.values {
            guard let notificationMessageId = notification.content.userInfo[AppNotificationUserInfoKey.messageId] as? String else {
                continue
            }

            guard notificationMessageId == messageId else {
                continue
            }

            cancelNotification(notification)
        }
    }

    func cancelNotifications(reactionId: String) {
        AssertIsOnMainThread()
        for notification in notifications.values {
            guard let notificationReactionId = notification.content.userInfo[AppNotificationUserInfoKey.reactionId] as? String else {
                continue
            }

            guard notificationReactionId == reactionId else {
                continue
            }

            cancelNotification(notification)
        }
    }

    func clearAllNotifications() {
        AssertIsOnMainThread()

        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
    }

    private static let kMigrationNotificationId = "kMigrationNotificationId"

    func notifyUserForGRDBMigration() {
        AssertIsOnMainThread()

        let title = NSLocalizedString("GRDB_MIGRATION_NOTIFICATION_TITLE",
                                      comment: "Title of notification shown during GRDB migration indicating that user may need to open app to view their content.")
        let body = NSLocalizedString("GRDB_MIGRATION_NOTIFICATION_BODY",
                                      comment: "Body message of notification shown during GRDB migration indicating that user may need to open app to view their content.")
        // By re-using the same identifier, we ensure that we never
        // show this notification more than once at a time.
        let identifier = UserNotificationPresenterAdaptee.kMigrationNotificationId
        notify(category: .grdbMigration, title: title, body: body, threadIdentifier: nil, userInfo: [:], sound: nil, replacingIdentifier: identifier)
    }

    private func clearNotificationForGRDBMigration() {
        AssertIsOnMainThread()

        let identifier = UserNotificationPresenterAdaptee.kMigrationNotificationId
        cancelNotification(identifier: identifier)
    }

    func shouldPresentNotification(category: AppNotificationCategory, userInfo: [AnyHashable: Any]) -> Bool {
        AssertIsOnMainThread()
        guard CurrentAppContext().isMainAppAndActive else {
            return true
        }

        switch category {
        case .incomingMessageWithActions_CanReply,
             .incomingMessageWithActions_CannotReply,
             .incomingMessageWithoutActions,
             .incomingReactionWithActions_CanReply,
             .incomingReactionWithActions_CannotReply,
             .infoOrErrorMessage:
            // If the app is in the foreground, show these notifications
            // unless the corresponding conversation is already open.
            break
        case .incomingMessageFromNoLongerVerifiedIdentity,
             .threadlessErrorMessage,
             .incomingCall,
             .missedCallWithActions,
             .missedCallWithoutActions,
             .missedCallFromNoLongerVerifiedIdentity:
            // Always show these notifications whenever the app is in the foreground.
            return true
        case .grdbMigration:
            // Never show these notifications if the app is in the foreground.
            return false
        }

        guard let notificationThreadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
            owsFailDebug("threadId was unexpectedly nil")
            return true
        }

        guard let conversationSplitVC = CurrentAppContext().frontmostViewController() as? ConversationSplit else {
            return true
        }

        // Show notifications for any *other* thread than the currently selected thread
        return conversationSplitVC.visibleThread?.uniqueId != notificationThreadId
    }
}

public protocol ConversationSplit {
    var visibleThread: TSThread? { get }
}

extension OWSSound {
    func notificationSound(isQuiet: Bool) -> UNNotificationSound {
        guard let filename = OWSSounds.filename(forSound: self, quiet: isQuiet) else {
            owsFailDebug("filename was unexpectedly nil")
            return UNNotificationSound.default
        }
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: filename))
    }
}
