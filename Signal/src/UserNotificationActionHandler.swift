//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(OWSUserNotificationActionHandler)
public class UserNotificationActionHandler: NSObject {

    var actionHandler: NotificationActionHandler {
        return NotificationActionHandler.shared
    }

    @objc
    func handleNotificationResponse( _ response: UNNotificationResponse, completionHandler: @escaping () -> Void) {
        AssertIsOnMainThread()
        firstly {
            try handleNotificationResponse(response)
        }.done {
            completionHandler()
        }.catch { error in
            owsFailDebug("error: \(error)")
            completionHandler()
        }
    }

    func handleNotificationResponse( _ response: UNNotificationResponse) throws -> Promise<Void> {
        AssertIsOnMainThread()
        assert(AppReadiness.isAppReady)

        let userInfo = response.notification.request.content.userInfo

        let action: AppNotificationAction

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            Logger.debug("default action")
            let defaultActionString = userInfo[AppNotificationUserInfoKey.defaultAction] as? String
            let defaultAction = defaultActionString.flatMap { AppNotificationAction(rawValue: $0) }
            action = defaultAction ?? .showThread
        case UNNotificationDismissActionIdentifier:
            // TODO - mark as read?
            Logger.debug("dismissed notification")
            return Promise.value(())
        default:
            if let responseAction = UserNotificationConfig.action(identifier: response.actionIdentifier) {
                action = responseAction
            } else {
                throw OWSAssertionError("unable to find action for actionIdentifier: \(response.actionIdentifier)")
            }
        }

        switch action {
        case .answerCall:
            return try actionHandler.answerCall(userInfo: userInfo)
        case .callBack:
            return try actionHandler.callBack(userInfo: userInfo)
        case .declineCall:
            return try actionHandler.declineCall(userInfo: userInfo)
        case .markAsRead:
            return try actionHandler.markAsRead(userInfo: userInfo)
        case .mute:
            return try actionHandler.mute(userInfo: userInfo)
        case .reply:
            guard let textInputResponse = response as? UNTextInputNotificationResponse else {
                throw OWSAssertionError("response had unexpected type: \(response)")
            }

            return try actionHandler.reply(userInfo: userInfo, replyText: textInputResponse.userText)
        case .showThread:
            return try actionHandler.showThread(userInfo: userInfo)
        case .reactWithThumbsUp:
            return try actionHandler.reactWithThumbsUp(userInfo: userInfo)
        case .showCallLobby:
            return try actionHandler.showCallLobby(userInfo: userInfo)
        }
    }
}
