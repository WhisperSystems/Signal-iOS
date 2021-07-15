//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import QuickLook
import PromiseKit
import PassKit

extension ConversationViewController: CVComponentDelegate {

    public var componentDelegate: CVComponentDelegate { self }

    public var isConversationPreview: Bool { false }

    public var wallpaperBlurProvider: WallpaperBlurProvider? { backgroundContainer }

    // MARK: - Body Text Items

    public func cvc_didTapBodyTextItem(_ item: CVBodyTextLabel.ItemObject) {
        AssertIsOnMainThread()

        didTapBodyTextItem(item)
    }

    public func cvc_didLongPressBodyTextItem(_ item: CVBodyTextLabel.ItemObject) {
        didLongPressBodyTextItem(item)
    }

    // MARK: - Long Press

    public func cvc_didLongPressTextViewItem(_ cell: CVCell,
                                             itemViewModel: CVItemViewModelImpl,
                                             shouldAllowReply: Bool) {
        AssertIsOnMainThread()

        let messageActions = MessageActions.textActions(itemViewModel: itemViewModel,
                                                        shouldAllowReply: shouldAllowReply,
                                                        delegate: self)
        self.presentMessageActions(messageActions, withFocusedCell: cell, itemViewModel: itemViewModel)
    }

    public func cvc_didLongPressMediaViewItem(_ cell: CVCell,
                                              itemViewModel: CVItemViewModelImpl,
                                              shouldAllowReply: Bool) {
        AssertIsOnMainThread()

        let messageActions = MessageActions.mediaActions(itemViewModel: itemViewModel,
                                                         shouldAllowReply: shouldAllowReply,
                                                         delegate: self)
        self.presentMessageActions(messageActions, withFocusedCell: cell, itemViewModel: itemViewModel)
    }

    public func cvc_didLongPressQuote(_ cell: CVCell,
                                      itemViewModel: CVItemViewModelImpl,
                                      shouldAllowReply: Bool) {
        AssertIsOnMainThread()

        let messageActions = MessageActions.quotedMessageActions(itemViewModel: itemViewModel,
                                                                 shouldAllowReply: shouldAllowReply,
                                                                 delegate: self)
        self.presentMessageActions(messageActions, withFocusedCell: cell, itemViewModel: itemViewModel)
    }

    public func cvc_didLongPressSystemMessage(_ cell: CVCell,
                                              itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        let messageActions = MessageActions.infoMessageActions(itemViewModel: itemViewModel,
                                                               delegate: self)
        self.presentMessageActions(messageActions, withFocusedCell: cell, itemViewModel: itemViewModel)
    }

    public func cvc_didLongPressSticker(_ cell: CVCell,
                                        itemViewModel: CVItemViewModelImpl,
                                        shouldAllowReply: Bool) {
        AssertIsOnMainThread()

        let messageActions = MessageActions.mediaActions(itemViewModel: itemViewModel,
                                                         shouldAllowReply: shouldAllowReply,
                                                         delegate: self)
        self.presentMessageActions(messageActions, withFocusedCell: cell, itemViewModel: itemViewModel)
    }

    public func cvc_didChangeLongpress(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        guard let messageActionsViewController = messageActionsViewController else {
            return
        }
        if messageActionsViewController.focusedInteraction.uniqueId !=
            itemViewModel.interaction.uniqueId {
            owsFailDebug("Received longpress update for unexpected cell")
            return
        }
        messageActionsViewController.didChangeLongpress()
    }

    public func cvc_didEndLongpress(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        guard let messageActionsViewController = messageActionsViewController else {
            return
        }
        if messageActionsViewController.focusedInteraction.uniqueId !=
            itemViewModel.interaction.uniqueId {
            owsFailDebug("Received longpress update for unexpected cell")
            return
        }
        messageActionsViewController.didEndLongpress()
    }

    public func cvc_didCancelLongpress(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        guard let messageActionsViewController = messageActionsViewController else {
            return
        }
        if messageActionsViewController.focusedInteraction.uniqueId !=
            itemViewModel.interaction.uniqueId {
            owsFailDebug("Received longpress update for unexpected cell")
            return
        }
        // TODO: Port.
        //        messageActionsViewController.didCancelLongpress()
    }

    // MARK: -

    public func cvc_didTapReplyToItem(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        populateReplyForMessage(itemViewModel)
    }

    public func cvc_didTapSenderAvatar(_ interaction: TSInteraction) {
        AssertIsOnMainThread()

        guard let incomingMessage = interaction as? TSIncomingMessage else {
            owsFailDebug("not an incoming message.")
            return
        }
        let groupViewHelper = GroupViewHelper(threadViewModel: threadViewModel)
        groupViewHelper.delegate = self
        let actionSheet = MemberActionSheet(address: incomingMessage.authorAddress,
                                            groupViewHelper: groupViewHelper)
        actionSheet.present(from: self)
    }

    public func cvc_shouldAllowReplyForItem(_ itemViewModel: CVItemViewModelImpl) -> Bool {
        AssertIsOnMainThread()

        if thread.isGroupThread && !thread.isLocalUserFullMemberOfThread {
            return false
        }
        if self.threadViewModel.hasPendingMessageRequest {
            return false
        }
        if let message = itemViewModel.interaction as? TSMessage,
           message.wasRemotelyDeleted {
            return false
        }

        if let outgoingMessage = itemViewModel.interaction as? TSOutgoingMessage {
            if outgoingMessage.messageState == .failed {
                // Don't allow "delete" or "reply" on "failed" outgoing messages.
                return false
            } else if outgoingMessage.messageState == .sending {
                // Don't allow "delete" or "reply" on "sending" outgoing messages.
                return false
            } else if outgoingMessage.messageState == .pending {
                // Don't allow "delete" or "reply" on "sending" outgoing messages.
                return false
            }
        }

        return true
    }

    public func cvc_didTapReactions(reactionState: InteractionReactionState,
                                    message: TSMessage) {
        AssertIsOnMainThread()

        if !reactionState.hasReactions {
            owsFailDebug("missing reaction state")
            return
        }

        let detailSheet = ReactionsDetailSheet(reactionState: reactionState, message: message)
        self.present(detailSheet, animated: true, completion: nil)
        self.reactionsDetailSheet = detailSheet
    }

    public var cvc_hasPendingMessageRequest: Bool {
        AssertIsOnMainThread()

        return self.threadViewModel.hasPendingMessageRequest
    }

    public func cvc_didTapTruncatedTextMessage(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        expandTruncatedTextOrPresentLongTextView(itemViewModel)
    }

    public func cvc_didTapFailedOrPendingDownloads(_ message: TSMessage) {
        AssertIsOnMainThread()

        attachmentDownloads.enqueueDownloadOfAttachments(forMessageId: message.uniqueId,
                                                         attachmentGroup: .allAttachmentsIncoming,
                                                         downloadBehavior: .bypassAll,
                                                         touchMessageImmediately: true,
                                                         success: { _ in
                                                            Logger.info("Successfully re-downloaded attachment.")
                                                         }, failure: { error in
                                                            Logger.warn("Failed to redownload message with error: \(error)")
                                                         })
    }

    // MARK: - Messages

    public func cvc_didTapBodyMedia(itemViewModel: CVItemViewModelImpl,
                                    attachmentStream: TSAttachmentStream,
                                    imageView: UIView) {
        AssertIsOnMainThread()

        dismissKeyBoard()

        let pageVC = MediaPageViewController(initialMediaAttachment: attachmentStream,
                                             thread: self.thread)
        self.present(pageVC, animated: true, completion: nil)
    }

    public func cvc_didTapGenericAttachment(_ attachment: CVComponentGenericAttachment) -> CVAttachmentTapAction {
        AssertIsOnMainThread()

        if attachment.canQuickLook {
            let previewController = QLPreviewController()
            previewController.dataSource = attachment
            self.present(previewController, animated: true, completion: nil)
            return .handledByDelegate
        } else if PKAddPassesViewController.canAddPasses(),
                  let pkPass = attachment.representedPKPass(),
                  let addPassesVC = PKAddPassesViewController(pass: pkPass) {
            self.present(addPassesVC, animated: true, completion: nil)
            return .handledByDelegate
        } else {
            return .default
        }
    }

    public func cvc_didTapQuotedReply(_ quotedReply: OWSQuotedReplyModel) {
        AssertIsOnMainThread()
        owsAssertDebug(quotedReply.timestamp > 0)
        owsAssertDebug(quotedReply.authorAddress.isValid)

        scrollToQuotedMessage(quotedReply, isAnimated: true)
    }

    public func cvc_didTapLinkPreview(_ linkPreview: OWSLinkPreview) {
        AssertIsOnMainThread()

        guard let urlString = linkPreview.urlString,
              let url = URL(string: urlString) else {
            owsFailDebug("Invalid link preview URL.")
            return
        }

        if StickerPackInfo.isStickerPackShare(url) {
            if let stickerPackInfo = StickerPackInfo.parseStickerPackShare(url) {
                let packView = StickerPackViewController(stickerPackInfo: stickerPackInfo)
                packView.present(from: self, animated: true)
                return
            } else {
                owsFailDebug("Could not parse sticker pack share URL: \(url)")
            }
        }

        if GroupManager.isPossibleGroupInviteLink(url) {
            cvc_didTapGroupInviteLink(url: url)
            return
        }

        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    public func cvc_didTapContactShare(_ contactShare: ContactShareViewModel) {
        AssertIsOnMainThread()

        let view = ContactViewController(contactShare: contactShare)
        navigationController?.pushViewController(view, animated: true)
    }

    public func cvc_didTapSendMessage(toContactShare contactShare: ContactShareViewModel) {
        AssertIsOnMainThread()

        contactShareViewHelper.sendMessage(contactShare: contactShare, fromViewController: self)
    }

    public func cvc_didTapSendInvite(toContactShare contactShare: ContactShareViewModel) {
        AssertIsOnMainThread()

        contactShareViewHelper.showInviteContact(contactShare: contactShare, fromViewController: self)
    }

    public func cvc_didTapAddToContacts(contactShare: ContactShareViewModel) {
        AssertIsOnMainThread()

        contactShareViewHelper.showAddToContacts(contactShare: contactShare, fromViewController: self)
    }

    public func cvc_didTapStickerPack(_ stickerPackInfo: StickerPackInfo) {
        AssertIsOnMainThread()

        let packView = StickerPackViewController(stickerPackInfo: stickerPackInfo)
        packView.present(from: self, animated: true)
    }

    public func cvc_didTapGroupInviteLink(url: URL) {
        AssertIsOnMainThread()
        owsAssertDebug(GroupManager.isPossibleGroupInviteLink(url))

        GroupInviteLinksUI.openGroupInviteLink(url, fromViewController: self)
    }

    public func cvc_didTapShowMessageDetail(_ itemViewModel: CVItemViewModelImpl) {
        showDetailView(itemViewModel)
    }

    public func cvc_prepareMessageDetailForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl) {
        prepareDetailViewForInteractivePresentation(itemViewModel)
    }

    public func cvc_beginCellAnimation(maximumDuration: TimeInterval) -> EndCellAnimation {
        AssertIsOnMainThread()

        if maximumDuration > 0.5 {
            owsFailDebug("Animation is too long, skipping.")
            return {}
        }

        let identifier = UUID()
        viewState.beginCellAnimation(identifier: identifier)

        var timer: Timer?
        let endAnimation = { [weak self] in
            AssertIsOnMainThread()
            guard let self = self else { return }

            timer?.invalidate()
            self.viewState.endCellAnimation(identifier: identifier)
            self.loadCoordinator.enqueueReload()
        }

        // Automatically unblock loads once the max duration is reached, even
        // if the cell didn't tell us it finished.
        timer = Timer.scheduledTimer(withTimeInterval: maximumDuration, repeats: false) { _ in
            endAnimation()
        }

        return endAnimation
    }

    // MARK: - System Cell

    public func cvc_didTapPreviouslyVerifiedIdentityChange(_ address: SignalServiceAddress) {
        AssertIsOnMainThread()

        showFingerprint(address: address)
    }

    public func showFingerprint(address: SignalServiceAddress) {
        AssertIsOnMainThread()

        // Ensure keyboard isn't hiding the "safety numbers changed" interaction when we
        // return from FingerprintViewController.
        dismissKeyBoard()

        FingerprintViewController.present(from: self, address: address)
    }

    public func cvc_didTapUnverifiedIdentityChange(_ address: SignalServiceAddress) {
        AssertIsOnMainThread()
        owsAssertDebug(address.isValid)

        dismissKeyBoard()

        let headerImageView = UIImageView(image: UIImage(named: "safety-number-change"))
        let headerView = UIView()
        headerView.addSubview(headerImageView)
        headerImageView.autoPinEdge(toSuperviewEdge: .top, withInset: 22)
        headerImageView.autoPinEdge(toSuperviewEdge: .bottom)
        headerImageView.autoHCenterInSuperview()
        headerImageView.autoSetDimension(.width, toSize: 200)
        headerImageView.autoSetDimension(.height, toSize: 110)

        let displayName = contactsManager.displayName(for: address)
        let messageFormat = NSLocalizedString("UNVERIFIED_SAFETY_NUMBER_CHANGE_DESCRIPTION_FORMAT",
                                              comment: "Description for the unverified safety number change. Embeds {name of contact with identity change}")

        let actionSheet = ActionSheetController(title: nil,
                                                message: String(format: messageFormat, displayName))
        actionSheet.customHeader = headerView

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("UNVERIFIED_SAFETY_NUMBER_VERIFY_ACTION",
                                                                         comment: "Action to verify a safety number after it has changed"),
                                                style: .default) { [weak self] _ in
            self?.showFingerprint(address: address)
        })

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.notNowButton,
                                                style: .cancel,
                                                handler: nil))
        presentActionSheet(actionSheet)
    }

    public func cvc_didTapInvalidIdentityKeyErrorMessage(_ message: TSInvalidIdentityKeyErrorMessage) {
        AssertIsOnMainThread()

        let keyOwner = contactsManager.displayName(for: message.theirSignalAddress())
        let titleFormat = NSLocalizedString("SAFETY_NUMBERS_ACTIONSHEET_TITLE", comment: "Action sheet heading")
        let titleText = String(format: titleFormat, keyOwner)

        let actionSheet = ActionSheetController(title: titleText, message: nil)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("SHOW_SAFETY_NUMBER_ACTION",
                                                                         comment: "Action sheet item"),
                                                accessibilityIdentifier: "show_safety_number",
                                                style: .default) { [weak self] _ in
            Logger.info("Remote Key Changed actions: Show fingerprint display")
            self?.showFingerprint(address: message.theirSignalAddress())
        })

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("ACCEPT_NEW_IDENTITY_ACTION",
                                                                         comment: "Action sheet item"),
                                                accessibilityIdentifier: "accept_safety_number",
                                                style: .default) { _ in
            Logger.info("Remote Key Changed actions: Accepted new identity key")

            // DEPRECATED: we're no longer creating these incoming SN error's per message,
            // but there will be some legacy ones in the wild, behind which await
            // as-of-yet-undecrypted messages
            if let errorMessage = message as? TSInvalidIdentityKeyReceivingErrorMessage {
                do {
                    _ = try errorMessage.acceptNewIdentityKey()
                } catch {
                    // Deliberately crash if the user fails to explicitly accept the new identity
                    // key. In practice we haven't been creating these messages in over a year.
                    owsFail("Error: \(error)")
                }
            }
        })

        dismissKeyBoard()
        self.presentActionSheet(actionSheet)
    }

    public func cvc_didTapCorruptedMessage(_ message: TSErrorMessage) {
        AssertIsOnMainThread()

        let threadName = databaseStorage.read { transaction in
            Self.contactsManager.displayName(for: self.thread, transaction: transaction)
        }
        let alertMessage = String(format: NSLocalizedString("CORRUPTED_SESSION_DESCRIPTION",
                                                            comment: "ActionSheet title"),
                                  threadName)
        let alert = ActionSheetController(title: nil, message: alertMessage)

        alert.addAction(OWSActionSheets.cancelAction)

        alert.addAction(ActionSheetAction(title: NSLocalizedString("FINGERPRINT_SHRED_KEYMATERIAL_BUTTON",
                                                                   comment: ""),
                                          accessibilityIdentifier: "reset_session",
                                          style: .default) { [weak self] _ in
            guard let self = self else { return }
            guard let contactThread = self.thread as? TSContactThread else {
                // Corrupt Message errors only appear in contact threads.
                Logger.error("Unexpected request to reset session in group thread.")
                return
            }

            Self.databaseStorage.asyncWrite { transaction in
                Self.sessionResetJobQueue.add(contactThread: contactThread, transaction: transaction)
            }
        })

        dismissKeyBoard()
        self.presentActionSheet(alert)
    }

    public func cvc_didTapSessionRefreshMessage(_ message: TSErrorMessage) {
        dismissKeyBoard()

        let headerImageView = UIImageView(image: UIImage(named: "chat-session-refresh"))

        let headerView = UIView()
        headerView.addSubview(headerImageView)
        headerImageView.autoPinEdge(toSuperviewEdge: .top, withInset: 22)
        headerImageView.autoPinEdge(toSuperviewEdge: .bottom)
        headerImageView.autoHCenterInSuperview()
        headerImageView.autoSetDimension(.width, toSize: 200)
        headerImageView.autoSetDimension(.height, toSize: 110)

        ContactSupportAlert.presentAlert(title: NSLocalizedString("SESSION_REFRESH_ALERT_TITLE",
                                                                  comment: "Title for the session refresh alert"),
                                         message: NSLocalizedString("SESSION_REFRESH_ALERT_MESSAGE",
                                                                    comment: "Description for the session refresh alert"),
                                         emailSupportFilter: "Signal iOS Session Refresh",
                                         fromViewController: self,
                                         additionalActions: [
                                            ActionSheetAction(title: CommonStrings.okayButton,
                                                              accessibilityIdentifier: "okay",
                                                              style: .default,
                                                              handler: nil)
                                         ],
                                         customHeader: headerView,
                                         showCancel: false)
    }

    // See: resendGroupUpdate
    public func cvc_didTapResendGroupUpdateForErrorMessage(_ message: TSErrorMessage) {
        AssertIsOnMainThread()

        guard let groupThread = self.thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        firstly(on: .global()) { () -> Promise<Void> in
            GroupManager.sendGroupUpdateMessage(thread: groupThread)
        }.done(on: .global()) {
            Logger.info("Group updated, removing group creation error.")

            Self.databaseStorage.write { transaction in
                message.anyRemove(transaction: transaction)
            }
        }.catch(on: .global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    public func cvc_didTapShowFingerprint(_ address: SignalServiceAddress) {
        AssertIsOnMainThread()

        showFingerprint(address: address)
    }

    // MARK: -

    public func cvc_didTapIndividualCall(_ call: TSCall) {
        AssertIsOnMainThread()
        owsAssertDebug(self.inputToolbar != nil)

        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Invalid thread.")
            return
        }

        let displayName = contactsManager.displayName(for: contactThread.contactAddress)

        let alert = ActionSheetController(title: CallStrings.callBackAlertTitle,
                                          message: String(format: CallStrings.callBackAlertMessageFormat,
                                                          displayName))

        alert.addAction(ActionSheetAction(title: CallStrings.callBackAlertCallButton,
                                          accessibilityIdentifier: "call_back",
                                          style: .default) { [weak self] _ in
            guard let self = self else { return }
            switch call.offerType {
            case .audio:
                self.startIndividualAudioCall()
            case .video:
                self.startIndividualVideoCall()
            }
        })
        alert.addAction(OWSActionSheets.cancelAction)

        inputToolbar?.clearDesiredKeyboard()
        dismissKeyBoard()
        self.presentActionSheet(alert)
    }

    public func cvc_didTapGroupCall() {
        AssertIsOnMainThread()

        showGroupLobbyOrActiveCall()
    }

    public func cvc_didTapPendingOutgoingMessage(_ message: TSOutgoingMessage) {
        AssertIsOnMainThread()

        SpamCaptchaViewController.presentActionSheet(from: self)
    }

    public func cvc_didTapFailedOutgoingMessage(_ message: TSOutgoingMessage) {
        AssertIsOnMainThread()

        resendFailedOutgoingMessage(message)
    }

    public func cvc_didTapShowGroupMigrationLearnMoreActionSheet(infoMessage: TSInfoMessage,
                                                                 oldGroupModel: TSGroupModel,
                                                                 newGroupModel: TSGroupModel) {
        AssertIsOnMainThread()

        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }

        let actionSheet = GroupMigrationActionSheet.actionSheetForMigratedGroup(groupThread: groupThread,
                                                                                oldGroupModel: oldGroupModel,
                                                                                newGroupModel: newGroupModel)
        actionSheet.present(fromViewController: self)
    }

    public func cvc_didTapGroupInviteLinkPromotion(groupModel: TSGroupModel) {
        AssertIsOnMainThread()

        showGroupLinkPromotionActionSheet()
    }

    public func cvc_didTapViewGroupDescription(groupModel: TSGroupModel?) {
        AssertIsOnMainThread()

        func getGroupModel() -> TSGroupModel? {
            if let groupModel = groupModel {
                return groupModel
            }
            if let groupThread = thread as? TSGroupThread {
                return groupThread.groupModel
            }
            return nil
        }
        guard let groupModel = getGroupModel() else {
            owsFailDebug("Unexpectedly missing group model.")
            return
        }

        let vc = GroupDescriptionViewController(groupModel: groupModel)
        let navigationController = OWSNavigationController(rootViewController: vc)
        self.presentFormSheet(navigationController, animated: true)
    }

    public func cvc_didTapShowConversationSettings() {
        AssertIsOnMainThread()

        showConversationSettings()
    }

    public func cvc_didTapShowConversationSettingsAndShowMemberRequests() {
        AssertIsOnMainThread()

        showConversationSettingsAndShowMemberRequests()
    }

    public func cvc_didTapShowUpgradeAppUI() {
        AssertIsOnMainThread()

        let url = "https://itunes.apple.com/us/app/signal-private-messenger/id874139669?mt=8"
        UIApplication.shared.open(URL(string: url)!, options: [:], completionHandler: nil)
    }

    public func cvc_didTapUpdateSystemContact(_ address: SignalServiceAddress,
                                              newNameComponents: PersonNameComponents) {
        AssertIsOnMainThread()

        guard contactsManagerImpl.supportsContactEditing else {
            owsFailDebug("Contact editing unexpectedly unsupported")
            return
        }

        guard let contactViewController = contactsViewHelper.contactViewController(for: address,
                                                                                   editImmediately: true,
                                                                                   addToExisting: nil,
                                                                                   updatedNameComponents: newNameComponents) else {
            owsFailDebug("Could not build contact view.")
            return
        }
        contactViewController.delegate = self
        navigationController?.pushViewController(contactViewController, animated: true)
    }

    public func cvc_didTapViewOnceAttachment(_ interaction: TSInteraction) {
        AssertIsOnMainThread()

        ViewOnceMessageViewController.tryToPresent(interaction: interaction, from: self)
    }

    public func cvc_didTapViewOnceExpired(_ interaction: TSInteraction) {
        AssertIsOnMainThread()

        if interaction is TSOutgoingMessage {
            presentViewOnceOutgoingToast()
        } else {
            presentViewOnceAlreadyViewedToast()
        }
    }

    public func cvc_didTapUnknownThreadWarningGroup() {
        AssertIsOnMainThread()

        showUnknownThreadWarningAlert()
    }

    public func cvc_didTapUnknownThreadWarningContact() {
        AssertIsOnMainThread()

        showUnknownThreadWarningAlert()
    }
}
