//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

class NotificationActionHandler: Dependencies {

    static let shared: NotificationActionHandler = NotificationActionHandler()

    func answerCall(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let localCallIdString = userInfo[AppNotificationUserInfoKey.localCallId] as? String else {
            throw OWSAssertionError("localCallIdString was unexpectedly nil")
        }

        guard let localCallId = UUID(uuidString: localCallIdString) else {
            throw OWSAssertionError("unable to build localCallId. localCallIdString: \(localCallIdString)")
        }

        individualCallUIAdapter.answerCall(localId: localCallId)
        return Promise.value(())
    }

    func callBack(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        let uuidString = userInfo[AppNotificationUserInfoKey.callBackUuid] as? String
        let phoneNumber = userInfo[AppNotificationUserInfoKey.callBackPhoneNumber] as? String
        let address = SignalServiceAddress(uuidString: uuidString, phoneNumber: phoneNumber)
        guard address.isValid else {
            throw OWSAssertionError("Missing or invalid address.")
        }

        individualCallUIAdapter.startAndShowOutgoingCall(address: address, hasLocalVideo: false)
        return Promise.value(())
    }

    func declineCall(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        guard let localCallIdString = userInfo[AppNotificationUserInfoKey.localCallId] as? String else {
            throw OWSAssertionError("localCallIdString was unexpectedly nil")
        }

        guard let localCallId = UUID(uuidString: localCallIdString) else {
            throw OWSAssertionError("unable to build localCallId. localCallIdString: \(localCallIdString)")
        }

        individualCallUIAdapter.localHangupCall(localId: localCallId)
        return Promise.value(())
    }

    func markAsRead(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        return firstly {
            self.notificationMessage(forUserInfo: userInfo)
        }.then(on: .global()) { (notificationMessage: NotificationMessage) in
            self.markMessageAsRead(notificationMessage: notificationMessage)
        }
    }

    func mute(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        return firstly {
            self.notificationMessage(forUserInfo: userInfo)
        }.then(on: .global()) { (notificationMessage: NotificationMessage) -> Promise<Void> in
            let thread = notificationMessage.thread

            guard let timeZone = TimeZone(identifier: "UTC") else {
                owsFailDebug("Invalid timezone.")
                return
            }

            var calendar = Calendar.current
            calendar.timeZone = timeZone

            let dateComponents = DateComponents()
            dateComponents.hour = 1

            guard let mutedUntilDate = calendar.date(byAdding: dateComponents, to: Date()) else {
                owsFailDebug("Couldn't modify date.")
                return
            }

            self.databaseStorage.write { transaction in
                thread.updateWithMuted(until: mutedUntilDate, transaction: transaction)
            }
        }
    }

    func reply(userInfo: [AnyHashable: Any], replyText: String) throws -> Promise<Void> {
        return firstly { () -> Promise<NotificationMessage> in
            self.notificationMessage(forUserInfo: userInfo)
        }.then(on: .global()) { (notificationMessage: NotificationMessage) -> Promise<Void> in
            let thread = notificationMessage.thread
            let interaction = notificationMessage.interaction
            guard nil != interaction as? TSIncomingMessage else {
                throw OWSAssertionError("Unexpected interaction type.")
            }

            return firstly(on: .global()) { () -> Promise<Void> in
                self.databaseStorage.write { transaction in
                    ThreadUtil.sendMessageNonDurablyPromise(body: MessageBody(text: replyText, ranges: .empty),
                                                            thread: thread,
                                                            transaction: transaction)
                }
            }.recover(on: .global()) { error -> Promise<Void> in
                Logger.warn("Failed to send reply message from notification with error: \(error)")
                self.notificationPresenter.notifyForFailedSend(inThread: thread)
                throw error
            }.then(on: .global()) { () -> Promise<Void> in
                self.markMessageAsRead(notificationMessage: notificationMessage)
            }
        }
    }

    func showThread(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        return firstly { () -> Promise<NotificationMessage> in
            self.notificationMessage(forUserInfo: userInfo)
        }.done(on: .main) { notificationMessage in
            self.showThread(notificationMessage: notificationMessage)
        }
    }

    private func showThread(notificationMessage: NotificationMessage) {
        // If this happens when the the app is not, visible we skip the animation so the thread
        // can be visible to the user immediately upon opening the app, rather than having to watch
        // it animate in from the homescreen.
        signalApp.presentConversationAndScrollToFirstUnreadMessage(
            forThreadId: notificationMessage.thread.uniqueId,
            animated: UIApplication.shared.applicationState == .active
        )
    }

    func reactWithThumbsUp(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        return firstly { () -> Promise<NotificationMessage> in
            self.notificationMessage(forUserInfo: userInfo)
        }.then(on: .global()) { (notificationMessage: NotificationMessage) -> Promise<Void> in
            let thread = notificationMessage.thread
            let interaction = notificationMessage.interaction
            guard let incomingMessage = interaction as? TSIncomingMessage else {
                throw OWSAssertionError("Unexpected interaction type.")
            }

            return firstly(on: .global()) { () -> Promise<Void> in
                self.databaseStorage.write { transaction in
                    ReactionManager.localUserReactedWithNonDurableSend(to: incomingMessage, emoji: "👍", isRemoving: false, transaction: transaction)
                }
            }.recover(on: .global()) { error -> Promise<Void> in
                Logger.warn("Failed to send reply message from notification with error: \(error)")
                self.notificationPresenter.notifyForFailedSend(inThread: thread)
                throw error
            }.then(on: .global()) { () -> Promise<Void> in
                self.markMessageAsRead(notificationMessage: notificationMessage)
            }
        }
    }

    func showCallLobby(userInfo: [AnyHashable: Any]) throws -> Promise<Void> {
        return firstly { () -> Promise<NotificationMessage> in
            self.notificationMessage(forUserInfo: userInfo)
        }.done(on: .main) { notificationMessage in
            let thread = notificationMessage.thread
            let currentCall = Self.callService.currentCall

            if currentCall?.thread.uniqueId == thread.uniqueId {
                OWSWindowManager.shared.returnToCallView()
            } else if let thread = thread as? TSGroupThread, currentCall == nil {
                GroupCallViewController.presentLobby(thread: thread)
            } else {
                // If currentCall is non-nil, we can't join a call anyway, fallback to showing the thread.
                // Individual calls don't have a lobby, just show the thread.
                return self.showThread(notificationMessage: notificationMessage)
            }
        }
    }

    private struct NotificationMessage {
        let thread: TSThread
        let interaction: TSInteraction?
        let hasPendingMessageRequest: Bool
    }

    private func notificationMessage(forUserInfo userInfo: [AnyHashable: Any]) -> Promise<NotificationMessage> {
        firstly(on: .global()) { () throws -> NotificationMessage in
            guard let threadId = userInfo[AppNotificationUserInfoKey.threadId] as? String else {
                throw OWSAssertionError("threadId was unexpectedly nil")
            }
            let messageId = userInfo[AppNotificationUserInfoKey.messageId] as? String

            return try self.databaseStorage.read { (transaction) throws -> NotificationMessage in
                guard let thread = TSThread.anyFetch(uniqueId: threadId, transaction: transaction) else {
                    throw OWSAssertionError("unable to find thread with id: \(threadId)")
                }

                let interaction: TSInteraction?
                if let messageId = messageId {
                    interaction = TSInteraction.anyFetch(uniqueId: messageId, transaction: transaction)
                } else {
                    interaction = nil
                }

                let hasPendingMessageRequest = thread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead)

                return NotificationMessage(
                    thread: thread,
                    interaction: interaction,
                    hasPendingMessageRequest: hasPendingMessageRequest
                )
            }
        }
    }

    private func markMessageAsRead(notificationMessage: NotificationMessage) -> Promise<Void> {
        guard let interaction = notificationMessage.interaction else {
            return Promise(error: OWSAssertionError("missing interaction"))
        }
        let (promise, resolver) = Promise<Void>.pending()
        self.receiptManager.markAsReadLocally(beforeSortId: interaction.sortId,
                                                  thread: notificationMessage.thread,
                                                  hasPendingMessageRequest: notificationMessage.hasPendingMessageRequest) {
                                                    resolver.fulfill(())
        }
        return promise
    }
}
