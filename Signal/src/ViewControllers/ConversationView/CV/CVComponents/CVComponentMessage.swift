//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentMessage: CVComponentBase, CVRootComponent {

    public var cellReuseIdentifier: CVCellReuseIdentifier {
        guard !isShowingSelectionUI else {
            return .`default`
        }
        if let bodyTextState = itemViewState.bodyTextState,
           !bodyTextState.canUseDedicatedCell {
            return .`default`
        }
        let dedicatedTextOnlyKeys: [CVComponentKey] = [
            .bodyText
        ]
        let activeKeys = activeComponentKeys()
        if activeKeys == Set(dedicatedTextOnlyKeys) {
            return isIncoming ? .dedicatedTextOnlyIncoming : .dedicatedTextOnlyOutgoing
        } else {
            return .`default`
        }
    }

    public var isDedicatedCell: Bool {
        // TODO: Re-enable reuse of this component.
        // cellReuseIdentifier != .`default`
        return false
    }

    private var bodyText: CVComponent?

    private var bodyMedia: CVComponent?

    private var senderName: CVComponent?

    private var senderAvatar: CVComponentState.SenderAvatar?
    private var hasSenderAvatarLayout: Bool {

        // Return true if space for a sender avatar appears in the layout.
        // Avatar itself might not appear due to de-duplication.
        isIncoming && isGroupThread && senderAvatar != nil && !shouldHideSenderAvaters
    }
    private var hasSenderAvatar: Bool {
        // Return true if a sender avatar appears.
        hasSenderAvatarLayout && itemViewState.shouldShowSenderAvatar
    }

    // This is the "standalone" footer, as opposed to
    // a footer overlaid over body media.
    private var standaloneFooter: CVComponentFooter?

    private var sticker: CVComponent?

    private var viewOnce: CVComponent?

    private var quotedReply: CVComponent?

    private var linkPreview: CVComponent?

    private var reactions: CVComponent?

    private var audioAttachment: CVComponent?

    private var genericAttachment: CVComponent?

    private var contactShare: CVComponent?

    private var bottomButtons: CVComponent?

    private var swipeToReplyProgress: CVSwipeToReplyState.Progress?
    private var swipeToReplyReference: CVSwipeToReplyState.Reference?

    private var hasSendFailureBadge = false
    
    private var shouldHideSenderAvaters = false;

    override init(itemModel: CVItemModel) {
        super.init(itemModel: itemModel)

        buildComponentStates()
    }

    private var sharpCorners: OWSDirectionalRectCorner {

        var rawValue: UInt = 0

        if !itemViewState.isFirstInCluster {
            rawValue |= isIncoming ? OWSDirectionalRectCorner.topLeading.rawValue : OWSDirectionalRectCorner.topTrailing.rawValue
        }

        if !itemViewState.isLastInCluster {
            rawValue |= isIncoming ? OWSDirectionalRectCorner.bottomLeading.rawValue : OWSDirectionalRectCorner.bottomTrailing.rawValue
        }

        return OWSDirectionalRectCorner(rawValue: rawValue)
    }

    private var sharpCornersForQuotedMessage: OWSDirectionalRectCorner {
        if itemViewState.senderName != nil {
            return .allCorners
        } else {
            var rawValue = sharpCorners.rawValue
            rawValue |= OWSDirectionalRectCorner.bottomLeading.rawValue
            rawValue |= OWSDirectionalRectCorner.bottomTrailing.rawValue
            return OWSDirectionalRectCorner(rawValue: rawValue)
        }
    }

    private func subcomponent(forKey key: CVComponentKey) -> CVComponent? {
        switch key {
        case .senderName:
            return self.senderName
        case .bodyText:
            return self.bodyText
        case .bodyMedia:
            return self.bodyMedia
        case .footer:
            return self.standaloneFooter
        case .sticker:
            return self.sticker
        case .viewOnce:
            return self.viewOnce
        case .audioAttachment:
            return self.audioAttachment
        case .genericAttachment:
            return self.genericAttachment
        case .quotedReply:
            return self.quotedReply
        case .linkPreview:
            return self.linkPreview
        case .reactions:
            return self.reactions
        case .contactShare:
            return self.contactShare
        case .bottomButtons:
            return self.bottomButtons

        // We don't render sender avatars with a subcomponent.
        case .senderAvatar:
            return nil
        case .systemMessage, .dateHeader, .unreadIndicator, .typingIndicator, .threadDetails, .failedOrPendingDownloads, .sendFailureBadge:
            return nil
        }
    }

    private var canFooterOverlayMedia: Bool {
        hasBodyMediaWithThumbnail && !isBorderless
    }

    private var hasBodyMediaWithThumbnail: Bool {
        bodyMedia != nil
    }

    // TODO: We might want to render the "remotely deleted" indicator using a dedicated component.
    private var hasBodyText: Bool {
        if wasRemotelyDeleted {
            return true
        }

        return componentState.bodyText != nil
    }

    private var isBubbleTransparent: Bool {
        if wasRemotelyDeleted {
            return false
        } else if componentState.isSticker {
            return true
        } else if isBorderlessViewOnceMessage {
            return false
        } else {
            return isBorderless
        }
    }

    private var isBorderlessViewOnceMessage: Bool {
        guard let viewOnce = componentState.viewOnce else {
            return false
        }
        switch viewOnce.viewOnceState {
        case .unknown:
            owsFailDebug("Invalid value.")
            return true
        case .incomingExpired, .incomingInvalidContent:
            return true
        default:
            return false
        }
    }

    private var hasTapForMore: Bool {
        standaloneFooter?.hasTapForMore ?? false
    }

    private func buildComponentStates() {
        if isGroupThread {
            SDSDatabaseStorage.shared.asyncRead { readTx in
                self.shouldHideSenderAvaters = SSKPreferences.hideGroupChatAvatars(transaction: readTx)
            }
        }
        
        hasSendFailureBadge = componentState.sendFailureBadge != nil

        if let senderName = itemViewState.senderName {
            self.senderName = CVComponentSenderName(itemModel: itemModel, senderName: senderName)
        }
        if let senderAvatar = componentState.senderAvatar {
            self.senderAvatar = senderAvatar
        }
        if let stickerState = componentState.sticker {
            self.sticker = CVComponentSticker(itemModel: itemModel, sticker: stickerState)
        }
        if let viewOnceState = componentState.viewOnce {
            self.viewOnce = CVComponentViewOnce(itemModel: itemModel, viewOnce: viewOnceState)
        }
        if let audioAttachmentState = componentState.audioAttachment {
            self.audioAttachment = CVComponentAudioAttachment(itemModel: itemModel,
                                                              audioAttachment: audioAttachmentState)
        }
        if let genericAttachmentState = componentState.genericAttachment {
            self.genericAttachment = CVComponentGenericAttachment(itemModel: itemModel,
                                                                  genericAttachment: genericAttachmentState)
        }
        if let bodyTextState = itemViewState.bodyTextState {
            bodyText = CVComponentBodyText(itemModel: itemModel, bodyTextState: bodyTextState)
        }
        if let contactShareState = componentState.contactShare {
            contactShare = CVComponentContactShare(itemModel: itemModel,
                                                   contactShareState: contactShareState)
        }
        if let bottomButtonsState = componentState.bottomButtons {
            bottomButtons = CVComponentBottomButtons(itemModel: itemModel,
                                                     bottomButtonsState: bottomButtonsState)
        }

        var footerOverlay: CVComponentFooter?
        if let bodyMediaState = componentState.bodyMedia {
            let shouldFooterOverlayMedia = (bodyText == nil && !isBorderless && !itemViewState.shouldHideFooter && !hasTapForMore)
            if shouldFooterOverlayMedia {
                if let footerState = itemViewState.footerState {
                    footerOverlay = CVComponentFooter(itemModel: itemModel,
                                                      footerState: footerState,
                                                      isOverlayingMedia: true,
                                                      isOutsideBubble: false)
                } else {
                    owsFailDebug("Missing footerState.")
                }
            }

            bodyMedia = CVComponentBodyMedia(itemModel: itemModel, bodyMedia: bodyMediaState, footerOverlay: footerOverlay)
        }

        let hasStandaloneFooter = (footerOverlay == nil && !itemViewState.shouldHideFooter)
        if hasStandaloneFooter {
            if let footerState = itemViewState.footerState {
                self.standaloneFooter = CVComponentFooter(itemModel: itemModel,
                                                          footerState: footerState,
                                                          isOverlayingMedia: false,
                                                          isOutsideBubble: isBubbleTransparent)
            } else {
                owsFailDebug("Missing footerState.")
            }
        }

        if let quotedReplyState = componentState.quotedReply {
            self.quotedReply = CVComponentQuotedReply(itemModel: itemModel,
                                                      quotedReply: quotedReplyState,
                                                      sharpCornersForQuotedMessage: sharpCornersForQuotedMessage)
        }

        if let linkPreviewState = componentState.linkPreview {
            self.linkPreview = CVComponentLinkPreview(itemModel: itemModel,
                                                      linkPreviewState: linkPreviewState)
        }

        if let reactionsState = componentState.reactions {
            self.reactions = CVComponentReactions(itemModel: itemModel, reactions: reactionsState)
        }
    }

    public func configure(cellView: UIView,
                          cellMeasurement: CVCellMeasurement,
                          componentDelegate: CVComponentDelegate,
                          cellSelection: CVCellSelection,
                          swipeToReplyState: CVSwipeToReplyState,
                          componentView: CVComponentView) {

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        configureForRendering(componentView: componentView,
                              cellMeasurement: cellMeasurement,
                              componentDelegate: componentDelegate)
        let rootView = componentView.rootView
        let isReusing = rootView.superview != nil
        if !isReusing {
            owsAssertDebug(cellView.layoutMargins == .zero)
            owsAssertDebug(cellView.subviews.isEmpty)

            cellView.layoutMargins = cellLayoutMargins
            cellView.addSubview(rootView)
            rootView.autoPinEdge(toSuperviewEdge: .top)
        }
        let bottomInset = reactions != nil ? reactionsVProtrusion : 0
        componentView.layoutConstraints.append(rootView.autoPinEdge(toSuperviewEdge: .bottom, withInset: bottomInset))

        self.swipeToReplyReference = nil
        self.swipeToReplyProgress = swipeToReplyState.getProgress(interactionId: interaction.uniqueId)

        var leadingView: UIView?
        if isShowingSelectionUI {
            owsAssertDebug(!isReusing)

            let selectionView = componentView.selectionView
            selectionView.isSelected = componentDelegate.cvc_isMessageSelected(interaction)
            cellView.addSubview(selectionView)
            selectionView.autoPinEdges(toSuperviewMarginsExcludingEdge: .trailing)
            leadingView = selectionView
        }

        if isReusing {
            owsAssertDebug(leadingView == nil)
            owsAssertDebug(!hasSendFailureBadge)
        } else if isIncoming {
            if let leadingView = leadingView {
                rootView.autoPinEdge(.leading, to: .trailing, of: leadingView, withOffset: selectionViewSpacing)
            } else {
                rootView.autoPinEdge(toSuperviewMargin: .leading)
            }
        } else if hasSendFailureBadge {
            // Send failures are rare, so it's cheaper to only build these views when we need them.
            let sendFailureBadge = UIImageView()
            sendFailureBadge.contentMode = .center
            sendFailureBadge.setTemplateImageName("error-outline-24", tintColor: .ows_accentRed)
            sendFailureBadge.autoSetDimensions(to: CGSize(square: sendFailureBadgeSize))
            cellView.addSubview(sendFailureBadge)
            sendFailureBadge.autoPinEdge(toSuperviewMargin: .trailing)

            if conversationStyle.hasWallpaper {
                sendFailureBadge.backgroundColor = conversationStyle.bubbleColor(isIncoming: true)
                sendFailureBadge.layer.cornerRadius = sendFailureBadgeSize / 2
                sendFailureBadge.clipsToBounds = true

                sendFailureBadge.autoPinEdge(.bottom, to: .bottom, of: rootView)
            } else {
                let sendFailureBadgeBottomMargin = round(conversationStyle.lastTextLineAxis - sendFailureBadgeSize * 0.5)
                sendFailureBadge.autoPinEdge(.bottom, to: .bottom, of: rootView, withOffset: -sendFailureBadgeBottomMargin)
            }

            rootView.autoPinEdge(.trailing, to: .leading, of: sendFailureBadge, withOffset: -sendFailureBadgeSpacing)
        } else {
            rootView.autoPinEdge(toSuperviewMargin: .trailing)
        }
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewMessage()
    }

    public static let textViewVSpacing: CGFloat = 2
    public static let bodyMediaQuotedReplyVSpacing: CGFloat = 6
    public static let quotedReplyTopMargin: CGFloat = 6

    private var selectionViewSpacing: CGFloat { ConversationStyle.messageStackSpacing }
    private var selectionViewWidth: CGFloat { ConversationStyle.selectionViewWidth }
    private var sendFailureBadgeSize: CGFloat { conversationStyle.hasWallpaper ? 40 : 24 }
    private var sendFailureBadgeSpacing: CGFloat { ConversationStyle.messageStackSpacing }

    // The "message" contents of this component are vertically
    // stacked in four sections.  Ordering of the keys in each
    // section determines the ordering of the subcomponents.
    private var topFullWidthCVComponentKeys: [CVComponentKey] { [.linkPreview] }
    private var topNestedCVComponentKeys: [CVComponentKey] { [.senderName] }
    private var bottomFullWidthCVComponentKeys: [CVComponentKey] { [.quotedReply, .bodyMedia] }
    private var bottomNestedCVComponentKeys: [CVComponentKey] { [.viewOnce, .audioAttachment, .genericAttachment, .contactShare, .bodyText, .footer] }

    public func configureForRendering(componentView: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        let isReusing = componentView.rootView.superview != nil
        guard !isReusing else {
            // This "dedicated" component already has the correct
            // configuration; we only need to update the contents
            // of the subcomponents.
            let bodyTextResult = configureSubcomponentForStack(messageView: componentView,
                                                               axis: .vertical,
                                                               cellMeasurement: cellMeasurement,
                                                               componentDelegate: componentDelegate,
                                                               key: .bodyText)
            owsAssertDebug(bodyTextResult != nil)

            _ = configureSubcomponentForStack(messageView: componentView,
                                              axis: .vertical,
                                              cellMeasurement: cellMeasurement,
                                              componentDelegate: componentDelegate,
                                              key: .footer)

            return
        }

        let cellHStack = componentView.cellHStack
        cellHStack.apply(config: cellHStackConfig)

        var outerAvatarView: AvatarImageView?
        var outerBubbleView: OWSBubbleView?
        let outerContentView: UIView

        if hasSenderAvatarLayout,
           let senderAvatar = self.senderAvatar {
            if hasSenderAvatar {
                componentView.avatarView.image = senderAvatar.senderAvatar
            }
            outerAvatarView = componentView.avatarView
        }

        let topFullWidthSubcomponents = subcomponents(forKeys: topFullWidthCVComponentKeys)
        let topNestedSubcomponents = subcomponents(forKeys: topNestedCVComponentKeys)
        let bottomFullWidthSubcomponents = subcomponents(forKeys: bottomFullWidthCVComponentKeys)
        let bottomNestedSubcomponents = subcomponents(forKeys: bottomNestedCVComponentKeys)
        let stickerOverlaySubcomponent = subcomponent(forKey: .sticker)

        func configureBubbleView() {
            let bubbleView = componentView.bubbleView
            bubbleView.backgroundColor = bubbleBackgroundColor
            bubbleView.sharpCorners = self.sharpCorners
            if let bubbleStrokeColor = self.bubbleStrokeColor {
                bubbleView.strokeColor = bubbleStrokeColor
                bubbleView.strokeThickness = 1
            } else {
                bubbleView.strokeColor = nil
                bubbleView.strokeThickness = 0
            }
            outerBubbleView = bubbleView
        }

        func configureStackView(_ stackView: OWSStackView,
                                config: CVStackViewConfig,
                                componentKeys keys: [CVComponentKey]) -> OWSStackView {
            self.configureSubcomponentStack(messageView: componentView,
                                            stackView: stackView,
                                            config: config,
                                            cellMeasurement: cellMeasurement,
                                            componentDelegate: componentDelegate,
                                            keys: keys)
            return stackView
        }

        if nil != stickerOverlaySubcomponent {
            // Sticker message.
            //
            // Stack is borderless.
            //
            // Optional senderName and footer.
            outerContentView = configureStackView(componentView.contentStackView,
                                                  config: buildBorderlessStackViewConfig(),
                                                  componentKeys: [.senderName, .sticker, .footer])
        } else {
            // Has full-width components.

            // TODO: We don't always use the bubble view for media.
            configureBubbleView()

            let contentStackView = componentView.contentStackView
            contentStackView.apply(config: buildNoMarginsStackViewConfig())
            outerContentView = contentStackView

            if !topFullWidthSubcomponents.isEmpty {
                let config = buildFullWidthStackViewConfig(includeTopMargin: false)
                let topFullWidthStackView = configureStackView(componentView.topFullWidthStackView,
                                                               config: config,
                                                               componentKeys: topFullWidthCVComponentKeys)
                contentStackView.addArrangedSubview(topFullWidthStackView)
            }
            if !topNestedSubcomponents.isEmpty {
                let hasNeighborsAbove = !topFullWidthSubcomponents.isEmpty
                let hasNeighborsBelow = (!bottomFullWidthSubcomponents.isEmpty ||
                                            !bottomNestedSubcomponents.isEmpty ||
                                            nil != bottomButtons)
                let config = buildNestedStackViewConfig(hasNeighborsAbove: hasNeighborsAbove,
                                                        hasNeighborsBelow: hasNeighborsBelow)
                let topNestedStackView = configureStackView(componentView.topNestedStackView,
                                                            config: config,
                                                            componentKeys: topNestedCVComponentKeys)
                contentStackView.addArrangedSubview(topNestedStackView)
            }
            if !bottomFullWidthSubcomponents.isEmpty {
                // If a quoted reply is the top-most subcomponent,
                // apply a top margin.
                let applyTopMarginToFullWidthStack = (topFullWidthSubcomponents.isEmpty &&
                                                        topNestedSubcomponents.isEmpty &&
                                                        quotedReply != nil)
                let config = buildFullWidthStackViewConfig(includeTopMargin: applyTopMarginToFullWidthStack)
                let bottomFullWidthStackView = configureStackView(componentView.bottomFullWidthStackView,
                                                                  config: config,
                                                                  componentKeys: bottomFullWidthCVComponentKeys)
                contentStackView.addArrangedSubview(bottomFullWidthStackView)
            }
            if !bottomNestedSubcomponents.isEmpty {
                let hasNeighborsAbove = (!topFullWidthSubcomponents.isEmpty ||
                                            !topNestedSubcomponents.isEmpty ||
                                            !bottomFullWidthSubcomponents.isEmpty)
                let hasNeighborsBelow = (nil != bottomButtons)
                let config = buildNestedStackViewConfig(hasNeighborsAbove: hasNeighborsAbove,
                                                        hasNeighborsBelow: hasNeighborsBelow)
                let bottomNestedStackView = configureStackView(componentView.bottomNestedStackView,
                                                               config: config,
                                                               componentKeys: bottomNestedCVComponentKeys)
                contentStackView.addArrangedSubview(bottomNestedStackView)
            }
            if nil != bottomButtons {
                if let componentAndView = configureSubcomponentForStack(messageView: componentView,
                                                                        axis: .vertical,
                                                                        cellMeasurement: cellMeasurement,
                                                                        componentDelegate: componentDelegate,
                                                                        key: .bottomButtons) {
                    let subview = componentAndView.componentView.rootView
                    contentStackView.addArrangedSubview(subview)
                } else {
                    owsFailDebug("Couldn't configure bottomButtons.")
                }
            }
        }

        if let contentWidth = cellMeasurement.value(key: contentWidthKey) {
            componentView.layoutConstraints.append(outerContentView.autoSetDimension(.width, toSize: contentWidth))
        } else {
            owsFailDebug("Missing contentWidth.")
        }

        if let subview = outerAvatarView {
            subview.setContentHuggingHigh()
            subview.setCompressionResistanceHigh()
            cellHStack.addArrangedSubview(subview)
        }

        let swipeToReplyContentView: UIView
        if let bubbleView = outerBubbleView {
            outerContentView.setContentHuggingLow()
            outerContentView.setCompressionResistanceLow()
            bubbleView.addSubview(outerContentView)
            outerContentView.autoPinEdgesToSuperviewEdges()
            bubbleView.setContentHuggingLow()
            bubbleView.setCompressionResistanceLow()
            cellHStack.addArrangedSubview(bubbleView)
            swipeToReplyContentView = bubbleView

            if let componentAndView = findActiveComponentAndView(key: .bodyMedia,
                                                          messageView: componentView) {
                if let bodyMediaComponent = componentAndView.component as? CVComponentBodyMedia {
                    if let bubbleViewPartner = bodyMediaComponent.bubbleViewPartner(componentView: componentAndView.componentView) {
                        bubbleView.addPartnerView(bubbleViewPartner)
                    }
                } else {
                    owsFailDebug("Invalid component.")
                }
            }
        } else {
            outerContentView.setContentHuggingLow()
            outerContentView.setCompressionResistanceLow()
            cellHStack.addArrangedSubview(outerContentView)
            swipeToReplyContentView = outerContentView
        }

        componentView.swipeToReplyContentView = swipeToReplyContentView
        let swipeToReplyIconView = componentView.swipeToReplyIconView
        swipeToReplyIconView.contentMode = .center
        swipeToReplyIconView.alpha = 0
        cellHStack.addSubview(swipeToReplyIconView)
        cellHStack.sendSubviewToBack(swipeToReplyIconView)
        swipeToReplyIconView.autoAlignAxis(.horizontal, toSameAxisOf: swipeToReplyContentView)
        swipeToReplyIconView.autoPinEdge(.leading, to: .leading, of: swipeToReplyContentView, withOffset: 8)

        if conversationStyle.hasWallpaper {
            swipeToReplyIconView.backgroundColor = conversationStyle.bubbleColor(isIncoming: true)
            swipeToReplyIconView.layer.cornerRadius = 17
            swipeToReplyIconView.clipsToBounds = true
            swipeToReplyIconView.autoSetDimensions(to: CGSize(square: 34))

            swipeToReplyIconView.setTemplateImageName("reply-outline-20",
                                                      tintColor: .ows_gray45)
        } else {
            swipeToReplyIconView.backgroundColor = .clear
            swipeToReplyIconView.layer.cornerRadius = 0
            swipeToReplyIconView.clipsToBounds = false
            swipeToReplyIconView.autoSetDimensions(to: CGSize(square: 24))

            swipeToReplyIconView.setTemplateImageName("reply-outline-24",
                                                      tintColor: .ows_gray45)
        }

        if let reactions = self.reactions {
            let reactionsView = configureSubcomponentView(messageView: componentView,
                                                          subcomponent: reactions,
                                                          cellMeasurement: cellMeasurement,
                                                          componentDelegate: componentDelegate,
                                                          key: .reactions)

            cellHStack.addSubview(reactionsView.rootView)
            if isIncoming {
                reactionsView.rootView.autoPinEdge(.leading,
                                                   to: .leading,
                                                   of: outerContentView,
                                                   withOffset: +reactionsHInset,
                                                   relation: .greaterThanOrEqual)
            } else {
                reactionsView.rootView.autoPinEdge(.trailing,
                                                   to: .trailing,
                                                   of: outerContentView,
                                                   withOffset: -reactionsHInset,
                                                   relation: .lessThanOrEqual)
            }

            // We want the reaction bubbles to stick to the middle of the screen inset from
            // the edge of the bubble with a small amount of padding unless the bubble is smaller
            // than the reactions view in which case it will break these constraints and extend
            // further into the middle of the screen than the message itself.
            NSLayoutConstraint.autoSetPriority(.defaultLow) {
                //            [NSLayoutConstraint autoSetPriority:UILayoutPriorityDefaultLow
                //            forConstraints:^{
                if self.isIncoming {
                    reactionsView.rootView.autoPinEdge(.trailing,
                                                       to: .trailing,
                                                       of: outerContentView,
                                                       withOffset: -reactionsHInset)
                } else {
                    reactionsView.rootView.autoPinEdge(.leading,
                                                       to: .leading,
                                                       of: outerContentView,
                                                       withOffset: +reactionsHInset)
                }
            }

            reactionsView.rootView.autoPinEdge(.top,
                                               to: .bottom,
                                               of: outerContentView,
                                               withOffset: -reactionsVOverlap)
        }

        componentView.rootView.accessibilityLabel = buildAccessibilityLabel(componentView: componentView)
        componentView.rootView.isAccessibilityElement = true
    }

    // Builds an accessibility label for the entire message.
    // This label uses basic punctuation which might be used by
    // VoiceOver for pauses/timing.
    //
    // Example: Lilia sent: a picture, check out my selfie.
    // Example: You sent: great shot!
    private func buildAccessibilityLabel(componentView: CVComponentViewMessage) -> String {
        var elements = [String]()

        if isIncoming {
            if let accessibilityAuthorName = itemViewState.accessibilityAuthorName {
                let format = NSLocalizedString("CONVERSATION_VIEW_CELL_ACCESSIBILITY_SENDER_FORMAT",
                                               comment: "Format for sender info for accessibility label for message. Embeds {{ the sender name }}.")
                elements.append(String(format: format, accessibilityAuthorName))
            } else {
                owsFailDebug("Missing accessibilityAuthorName.")
            }
        } else if isOutgoing {
            elements.append(NSLocalizedString("CONVERSATION_VIEW_CELL_ACCESSIBILITY_SENDER_LOCAL_USER",
                                              comment: "Format for sender info for outgoing messages."))
        }

        // Order matters. For example, body media should be before body text.
        let accessibilityComponentKeys: [CVComponentKey] = [
            .bodyMedia,
            .bodyText,
            .sticker,
            .viewOnce,
            .audioAttachment,
            .genericAttachment,
            .contactShare
        ]
        var contents = [String]()
        for key in accessibilityComponentKeys {
            if let subcomponent = self.subcomponent(forKey: key) {
                if let accessibilityComponent = subcomponent as? CVAccessibilityComponent {
                    contents.append(accessibilityComponent.accessibilityDescription)
                } else {
                    owsFailDebug("Invalid accessibilityComponent.")
                }
            }
        }

        let timestampText = CVComponentFooter.timestampText(forInteraction: interaction,
                                                            shouldUseLongFormat: true)
        contents.append(timestampText)

        elements.append(contents.joined(separator: ", "))

        // NOTE: In the interest of keeping the accessibility label short,
        // we do not include information that is usually presented in the
        // following components:
        //
        // * footer (message send status, disappearing message status).
        //   We _do_ include time but not date. Dates are in the date headers.
        // * senderName
        // * senderAvatar
        // * quotedReply
        // * linkPreview
        // * reactions
        // * bottomButtons
        // * sendFailureBadge

        let result = elements.joined(separator: " ")
        return result
    }

    private var cellLayoutMargins: UIEdgeInsets {
        UIEdgeInsets(top: 0,
                     leading: conversationStyle.fullWidthGutterLeading,
                     bottom: 0,
                     trailing: conversationStyle.fullWidthGutterTrailing)
    }

    private var cellHStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .bottom,
                          spacing: ConversationStyle.messageStackSpacing,
                          layoutMargins: .zero)
    }

    private let reactionsHInset: CGFloat = 6
    // The overlap between the message content and the reactions bubble.
    private var reactionsVOverlap: CGFloat {
        CVReactionCountsView.inset
    }
    // How far the reactions bubble protrudes below the message content.
    private var reactionsVProtrusion: CGFloat {
        let reactionsHeight = CVReactionCountsView.height
        return max(0, reactionsHeight - reactionsVOverlap)
    }

    private var bubbleBackgroundColor: UIColor {
        if !conversationStyle.hasWallpaper && (wasRemotelyDeleted || isBorderlessViewOnceMessage) {
            return Theme.backgroundColor
        }
        if isBubbleTransparent {
            return .clear
        }
        return itemModel.conversationStyle.bubbleColor(isIncoming: isIncoming)
    }

    private var bubbleStrokeColor: UIColor? {
        if wasRemotelyDeleted || isBorderlessViewOnceMessage {
            return conversationStyle.hasWallpaper ? nil : Theme.outlineColor
        } else {
            return nil
        }
    }

    private func measureStackView(config: CVStackViewConfig,
                                  measurementBuilder: CVCellMeasurement.Builder,
                                  componentKeys keys: [CVComponentKey],
                                  maxWidth: CGFloat) -> CGSize {

        let maxWidth = maxWidth - config.layoutMargins.left + config.layoutMargins.right
        var subviewSizes = [CGSize]()
        for key in keys {
            guard let subcomponent = self.subcomponent(forKey: key) else {
                // Not all subcomponents may be present.
                continue
            }
            let subviewSize = subcomponent.measure(maxWidth: maxWidth, measurementBuilder: measurementBuilder)
            subviewSizes.append(subviewSize)

            // We store the measured size so that we can pin the
            // subcomponent view during configuration for rendering.
            measurementBuilder.setSize(key: key.asKey, size: subviewSize)
        }

        return CVStackView.measure(config: config, subviewSizes: subviewSizes)
    }

    private let contentWidthKey = "contentWidthKey"

    public func measure(maxWidth maxWidthChatHistory: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidthChatHistory > 0)

        let outerStackViewMaxWidth = max(0, maxWidthChatHistory - cellLayoutMargins.totalWidth)
        var cellHStackSize = CGSize.zero
        var outerStackViewSize: CGSize = .zero

        if hasSenderAvatarLayout {
            // Sender avatar in groups.
            outerStackViewSize.width += ConversationStyle.groupMessageAvatarDiameter + ConversationStyle.messageStackSpacing
            outerStackViewSize.height = max(outerStackViewSize.height, ConversationStyle.groupMessageAvatarDiameter)
        }
        if isShowingSelectionUI {
            outerStackViewSize.width += selectionViewWidth + selectionViewSpacing
        }
        if !isIncoming, hasSendFailureBadge {
            outerStackViewSize.width += sendFailureBadgeSize + sendFailureBadgeSpacing
        }
        // The message cell's "outer" stack can contain many views:
        // sender avatar, selection UI, send failure badge.
        // The message cell's "content" stack must fit within the
        // remaining space in the "outer" stack.
        let contentMaxWidth = max(0,
                                  min(conversationStyle.maxMessageWidth,
                                      outerStackViewMaxWidth - (outerStackViewSize.width +
                                                                    ConversationStyle.messageDirectionSpacing)))

        func measureStackView(config: CVStackViewConfig,
                              componentKeys keys: [CVComponentKey]) -> CGSize {
            let maxStackWidth = max(0, contentMaxWidth - config.layoutMargins.totalWidth)
            return self.measureStackView(config: config,
                                         measurementBuilder: measurementBuilder,
                                         componentKeys: keys,
                                         maxWidth: maxStackWidth)
        }

        let topFullWidthSubcomponents = subcomponents(forKeys: topFullWidthCVComponentKeys)
        let topNestedSubcomponents = subcomponents(forKeys: topNestedCVComponentKeys)
        let bottomFullWidthSubcomponents = subcomponents(forKeys: bottomFullWidthCVComponentKeys)
        let bottomNestedSubcomponents = subcomponents(forKeys: bottomNestedCVComponentKeys)
        let stickerOverlaySubcomponent = subcomponent(forKey: .sticker)

        func applyContentMeasurement(_ size: CGSize) {
            outerStackViewSize.width += size.width
            outerStackViewSize.height = max(outerStackViewSize.height, size.height)

            measurementBuilder.setValue(key: contentWidthKey, value: size.width)
        }

        if nil != stickerOverlaySubcomponent {
            // Sticker message.
            //
            // Stack is borderless.
            // Optional footer.

            applyContentMeasurement(measureStackView(config: buildBorderlessStackViewConfig(),
                                                     componentKeys: [.senderName, .sticker, .footer]))
        } else {
            // There are full-width components.
            // Use multiple stacks.

            var subviewSizes = [CGSize]()

            if !topFullWidthSubcomponents.isEmpty {
                let config = buildFullWidthStackViewConfig(includeTopMargin: false)
                subviewSizes.append(measureStackView(config: config,
                                                     componentKeys: topFullWidthCVComponentKeys))
            }
            if !topNestedSubcomponents.isEmpty {
                let hasNeighborsAbove = !topFullWidthSubcomponents.isEmpty
                let hasNeighborsBelow = (!bottomFullWidthSubcomponents.isEmpty ||
                                            !bottomNestedSubcomponents.isEmpty ||
                                            nil != bottomButtons)
                let config = buildNestedStackViewConfig(hasNeighborsAbove: hasNeighborsAbove,
                                                        hasNeighborsBelow: hasNeighborsBelow)
                subviewSizes.append(measureStackView(config: config,
                                                     componentKeys: topNestedCVComponentKeys))
            }
            if !bottomFullWidthSubcomponents.isEmpty {
                // If a quoted reply is the top-most subcomponent,
                // apply a top margin.
                let applyTopMarginToFullWidthStack = (topFullWidthSubcomponents.isEmpty &&
                                                        topNestedSubcomponents.isEmpty &&
                                                        quotedReply != nil)
                let config = buildFullWidthStackViewConfig(includeTopMargin: applyTopMarginToFullWidthStack)
                subviewSizes.append(measureStackView(config: config,
                                                     componentKeys: bottomFullWidthCVComponentKeys))
            }
            if !bottomNestedSubcomponents.isEmpty {
                let hasNeighborsAbove = (!topFullWidthSubcomponents.isEmpty ||
                                            !topNestedSubcomponents.isEmpty ||
                                            !bottomFullWidthSubcomponents.isEmpty)
                let hasNeighborsBelow = (nil != bottomButtons)
                let config = buildNestedStackViewConfig(hasNeighborsAbove: hasNeighborsAbove,
                                                        hasNeighborsBelow: hasNeighborsBelow)
                subviewSizes.append(measureStackView(config: config,
                                                     componentKeys: bottomNestedCVComponentKeys))
            }
            if let bottomButtons = bottomButtons {
                let subviewSize = bottomButtons.measure(maxWidth: contentMaxWidth,
                                                        measurementBuilder: measurementBuilder)

                // We store the measured size so that we can pin the
                // subcomponent view during configuration for rendering.
                let key = CVComponentKey.bottomButtons
                measurementBuilder.setSize(key: key.asKey, size: subviewSize)

                subviewSizes.append(subviewSize)
            }

            applyContentMeasurement(CVStackView.measure(config: buildNoMarginsStackViewConfig(),
                                                        subviewSizes: subviewSizes))
        }

        cellHStackSize.width += outerStackViewSize.width
        let minBubbleWidth = kOWSMessageCellCornerRadius_Large * 2
        cellHStackSize.width = max(cellHStackSize.width, minBubbleWidth)
        cellHStackSize.height = max(cellHStackSize.height, outerStackViewSize.height)

        if nil != reactions {
            cellHStackSize.height += reactionsVProtrusion
        }

        return cellHStackSize.ceil
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return false
        }

        if isShowingSelectionUI {
            let selectionView = componentView.selectionView
            let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
            if componentDelegate.cvc_isMessageSelected(interaction) {
                selectionView.isSelected = false
                componentDelegate.cvc_didDeselectViewItem(itemViewModel)
            } else {
                selectionView.isSelected = true
                componentDelegate.cvc_didSelectViewItem(itemViewModel)
            }
            // Suppress other tap handling during selection mode.
            return true
        }

        if let outgoingMessage = interaction as? TSOutgoingMessage {
            switch outgoingMessage.messageState {
            case .failed:
                // Tap to retry.
                componentDelegate.cvc_didTapFailedOutgoingMessage(outgoingMessage)
                return true
            case .sending:
                // Ignore taps on outgoing messages being sent.
                return true
            default:
                break
            }
        }

        if hasSenderAvatar,
           componentView.avatarView.containsGestureLocation(sender) {
            componentDelegate.cvc_didTapSenderAvatar(interaction)
            return true
        }

        if let subcomponentAndView = findComponentAndView(sender: sender,
                                                          componentView: componentView) {
            let subcomponent = subcomponentAndView.component
            let subcomponentView = subcomponentAndView.componentView
            Logger.verbose("key: \(subcomponentAndView.key)")
            if subcomponent.handleTap(sender: sender,
                                      componentDelegate: componentDelegate,
                                      componentView: subcomponentView,
                                      renderItem: renderItem) {
                return true
            }
        }

        if let message = interaction as? TSMessage,
           nil != componentState.failedOrPendingDownloads {
            Logger.verbose("Retrying failed downloads.")
            componentDelegate.cvc_didTapFailedOrPendingDownloads(message)
            return true
        }

        return false
    }

    public override func findLongPressHandler(sender: UILongPressGestureRecognizer,
                                              componentDelegate: CVComponentDelegate,
                                              componentView: CVComponentView,
                                              renderItem: CVRenderItem) -> CVLongPressHandler? {

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }

        if let subcomponentView = componentView.subcomponentView(key: .sticker),
           subcomponentView.rootView.containsGestureLocation(sender) {
            return CVLongPressHandler(delegate: componentDelegate,
                                      renderItem: renderItem,
                                      gestureLocation: .sticker)
        }
        if let subcomponentView = componentView.subcomponentView(key: .bodyMedia),
           subcomponentView.rootView.containsGestureLocation(sender) {
            return CVLongPressHandler(delegate: componentDelegate,
                                      renderItem: renderItem,
                                      gestureLocation: .media)
        }
        if let subcomponentView = componentView.subcomponentView(key: .audioAttachment),
           subcomponentView.rootView.containsGestureLocation(sender) {
            return CVLongPressHandler(delegate: componentDelegate,
                                      renderItem: renderItem,
                                      gestureLocation: .media)
        }
        if let subcomponentView = componentView.subcomponentView(key: .genericAttachment),
           subcomponentView.rootView.containsGestureLocation(sender) {
            return CVLongPressHandler(delegate: componentDelegate,
                                      renderItem: renderItem,
                                      gestureLocation: .media)
        }
        // TODO: linkPreview?
        if let subcomponentView = componentView.subcomponentView(key: .quotedReply),
           subcomponentView.rootView.containsGestureLocation(sender) {
            return CVLongPressHandler(delegate: componentDelegate,
                                      renderItem: renderItem,
                                      gestureLocation: .quotedReply)
        }

        return CVLongPressHandler(delegate: componentDelegate,
                                  renderItem: renderItem,
                                  gestureLocation: .`default`)
    }

    // For a configured & active cell, this will return the list of
    // currently active subcomponents & their corresponding subcomponent
    // views. This can be used for gesture dispatch, etc.
    private func findComponentAndView(sender: UIGestureRecognizer,
                                      componentView: CVComponentViewMessage) -> CVComponentAndView? {
        for subcomponentAndView in activeComponentAndViews(messageView: componentView) {
            let subcomponentView = subcomponentAndView.componentView
            let rootView = subcomponentView.rootView
            if rootView.containsGestureLocation(sender) {
                return subcomponentAndView
            }
        }
        return nil
    }

    // For a configured & active cell, this will return the list of
    // currently active subcomponents & their corresponding subcomponent
    // views. This can be used for gesture dispatch, etc.
    private func activeComponentAndViews(messageView: CVComponentViewMessage) -> [CVComponentAndView] {
        var result = [CVComponentAndView]()
        for key in CVComponentKey.allCases {
            guard let componentAndView = findActiveComponentAndView(key: key,
                                                                    messageView: messageView,
                                                                    ignoreMissing: true) else {
                continue
            }
            result.append(componentAndView)
        }
        return result
    }

    // For a configured & active cell, this will return a (component,
    // component view) tuple IFF that component is active.
    private func findActiveComponentAndView(key: CVComponentKey,
                                            messageView: CVComponentViewMessage,
                                            ignoreMissing: Bool = false) -> CVComponentAndView? {
        guard let subcomponent = self.subcomponent(forKey: key) else {
            // Not all subcomponents will be active.
            return nil
        }
        guard let subcomponentView = messageView.subcomponentView(key: key) else {
            if ignoreMissing {
                Logger.verbose("Missing subcomponentView: \(key).")
            } else {
                owsFailDebug("Missing subcomponentView.")
            }
            return nil
        }
        return CVComponentAndView(key: key, component: subcomponent, componentView: subcomponentView)
    }

    private func activeComponentKeys() -> Set<CVComponentKey> {
        Set(CVComponentKey.allCases.filter { key in
            nil != subcomponent(forKey: key)
        })
    }

    public func albumItemView(forAttachment attachment: TSAttachmentStream,
                              componentView: CVComponentView) -> UIView? {
        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }
        guard let componentAndView = findActiveComponentAndView(key: .bodyMedia,
                                                                messageView: componentView) else {
            owsFailDebug("Missing bodyMedia subcomponent.")
            return nil
        }
        guard let bodyMediaComponent = componentAndView.component as? CVComponentBodyMedia else {
            owsFailDebug("Unexpected subcomponent.")
            return nil
        }
        let bodyMediaComponentView = componentAndView.componentView
        return bodyMediaComponent.albumItemView(forAttachment: attachment,
                                                componentView: bodyMediaComponentView)
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewMessage: NSObject, CVComponentView {

        // Contains the "outer" contents which are arranged horizontally:
        //
        // * Gutters
        // * Group sender bubble
        // * Content view wrapped in message bubble _or_ unwrapped content view.
        // * Reactions view, which uses a custom layout block.
        fileprivate let cellHStack = OWSStackView(name: "cellHStack")

        fileprivate let avatarView = AvatarImageView()

        fileprivate let bubbleView = OWSBubbleView()
        fileprivate let contentStackView = OWSStackView(name: "contentStackView")

        // We use these stack views when there is a mixture of subcomponents,
        // some of which are full-width and some of which are not.
        fileprivate let topFullWidthStackView = OWSStackView(name: "topFullWidthStackView")
        fileprivate let topNestedStackView = OWSStackView(name: "topNestedStackView")
        fileprivate let bottomFullWidthStackView = OWSStackView(name: "bottomFullWidthStackView")
        fileprivate let bottomNestedStackView = OWSStackView(name: "bottomNestedStackView")

        fileprivate let selectionView = MessageSelectionView()

        fileprivate var swipeToReplyContentView: UIView?

        fileprivate let swipeToReplyIconView = UIImageView()

        fileprivate var layoutConstraints = [NSLayoutConstraint]()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            cellHStack
        }

        // MARK: - Subcomponents

        var senderNameView: CVComponentView?
        var bodyTextView: CVComponentView?
        var bodyMediaView: CVComponentView?
        var footerView: CVComponentView?
        var stickerView: CVComponentView?
        var viewOnceView: CVComponentView?
        var quotedReplyView: CVComponentView?
        var linkPreviewView: CVComponentView?
        var reactionsView: CVComponentView?
        var audioAttachmentView: CVComponentView?
        var genericAttachmentView: CVComponentView?
        var contactShareView: CVComponentView?
        var bottomButtonsView: CVComponentView?

        private var allSubcomponentViews: [CVComponentView] {
            [senderNameView, bodyTextView, bodyMediaView, footerView, stickerView, quotedReplyView, linkPreviewView, reactionsView, viewOnceView, audioAttachmentView, genericAttachmentView, contactShareView, bottomButtonsView].compactMap { $0 }
        }

        fileprivate func subcomponentView(key: CVComponentKey) -> CVComponentView? {
            switch key {
            case .senderName:
                return senderNameView
            case .bodyText:
                return bodyTextView
            case .bodyMedia:
                return bodyMediaView
            case .footer:
                return footerView
            case .sticker:
                return stickerView
            case .viewOnce:
                return viewOnceView
            case .quotedReply:
                return quotedReplyView
            case .linkPreview:
                return linkPreviewView
            case .reactions:
                return reactionsView
            case .audioAttachment:
                return audioAttachmentView
            case .genericAttachment:
                return genericAttachmentView
            case .contactShare:
                return contactShareView
            case .bottomButtons:
                return bottomButtonsView

            // We don't render sender avatars with a subcomponent.
            case .senderAvatar:
                owsFailDebug("Invalid component key: \(key)")
                return nil
            case .systemMessage, .dateHeader, .unreadIndicator, .typingIndicator, .threadDetails, .failedOrPendingDownloads, .sendFailureBadge:
                owsFailDebug("Invalid component key: \(key)")
                return nil
            }
        }

        fileprivate func setSubcomponentView(key: CVComponentKey, subcomponentView: CVComponentView?) {
            switch key {
            case .senderName:
                senderNameView = subcomponentView
            case .bodyText:
                bodyTextView = subcomponentView
            case .bodyMedia:
                bodyMediaView = subcomponentView
            case .footer:
                footerView = subcomponentView
            case .sticker:
                stickerView = subcomponentView
            case .viewOnce:
                viewOnceView = subcomponentView
            case .quotedReply:
                quotedReplyView = subcomponentView
            case .linkPreview:
                linkPreviewView = subcomponentView
            case .reactions:
                reactionsView = subcomponentView
            case .audioAttachment:
                audioAttachmentView = subcomponentView
            case .genericAttachment:
                genericAttachmentView = subcomponentView
            case .contactShare:
                contactShareView = subcomponentView
            case .bottomButtons:
                bottomButtonsView = subcomponentView

            // We don't render sender avatars with a subcomponent.
            case .senderAvatar:
                owsAssertDebug(subcomponentView == nil)
            case .systemMessage, .dateHeader, .unreadIndicator, .typingIndicator, .threadDetails, .failedOrPendingDownloads, .sendFailureBadge:
                owsAssertDebug(subcomponentView == nil)
            }
        }

        // MARK: -

        override required init() {
            avatarView.autoSetDimensions(to: CGSize(square: ConversationStyle.groupMessageAvatarDiameter))

            bubbleView.layoutMargins = .zero
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {
            for subcomponentView in allSubcomponentViews {
                subcomponentView.setIsCellVisible(isCellVisible)
            }
        }

        public func reset() {
            removeSwipeToReplyAnimations()

            if !isDedicatedCellView {
                cellHStack.reset()
                bubbleView.removeAllSubviews()
                contentStackView.reset()
                topFullWidthStackView.reset()
                topNestedStackView.reset()
                bottomFullWidthStackView.reset()
                bottomNestedStackView.reset()
            }

            avatarView.image = nil

            bubbleView.clearPartnerViews()

            if !isDedicatedCellView {
                swipeToReplyContentView = nil
                swipeToReplyIconView.image = nil
            }
            swipeToReplyIconView.alpha = 0

            // We use cellHStack.frame to detect whether or not
            // the cell has been laid out yet. Therefore we clear it here.
            cellHStack.frame = .zero

            if isDedicatedCellView {
                for subcomponentView in allSubcomponentViews {
                    subcomponentView.isDedicatedCellView = true
                }
            }

            for subcomponentView in allSubcomponentViews {
                subcomponentView.reset()
            }

            if !isDedicatedCellView {
                for key in CVComponentKey.allCases {
                    // Don't clear bodyTextView; it is expensive to build.
                    if key != .bodyText {
                        self.setSubcomponentView(key: key, subcomponentView: nil)
                    }
                }
            }

            NSLayoutConstraint.deactivate(layoutConstraints)
            layoutConstraints = []
        }

        fileprivate func removeSwipeToReplyAnimations() {
            swipeToReplyContentView?.layer.removeAllAnimations()
            avatarView.layer.removeAllAnimations()
            swipeToReplyIconView.layer.removeAllAnimations()
            reactionsView?.rootView.layer.removeAllAnimations()
        }
    }

    // MARK: - Swipe To Reply

    public override func findPanHandler(sender: UIPanGestureRecognizer,
                                        componentDelegate: CVComponentDelegate,
                                        componentView: CVComponentView,
                                        renderItem: CVRenderItem,
                                        swipeToReplyState: CVSwipeToReplyState) -> CVPanHandler? {
        AssertIsOnMainThread()

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }

        if let audioAttachment = self.audioAttachment,
           let subcomponentView = componentView.subcomponentView(key: .audioAttachment),
           subcomponentView.rootView.containsGestureLocation(sender),
           let panHandler = audioAttachment.findPanHandler(sender: sender,
                                                           componentDelegate: componentDelegate,
                                                           componentView: subcomponentView,
                                                           renderItem: renderItem,
                                                           swipeToReplyState: swipeToReplyState) {
            return panHandler
        }

        let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
        guard componentDelegate.cvc_shouldAllowReplyForItem(itemViewModel) else {
            return nil
        }
        tryToUpdateSwipeToReplyReference(componentView: componentView,
                                         renderItem: renderItem,
                                         swipeToReplyState: swipeToReplyState)
        guard swipeToReplyReference != nil else {
            owsFailDebug("Missing reference[\(renderItem.interactionUniqueId)].")
            return nil
        }

        return CVPanHandler(delegate: componentDelegate,
                            panType: .swipeToReply,
                            renderItem: renderItem)
    }

    public override func startPanGesture(sender: UIPanGestureRecognizer,
                                         panHandler: CVPanHandler,
                                         componentDelegate: CVComponentDelegate,
                                         componentView: CVComponentView,
                                         renderItem: CVRenderItem,
                                         swipeToReplyState: CVSwipeToReplyState) {
        AssertIsOnMainThread()

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return
        }
        owsAssertDebug(sender.state == .began)

        switch panHandler.panType {
        case .scrubAudio:
            guard let audioAttachment = self.audioAttachment,
                  let subcomponentView = componentView.subcomponentView(key: .audioAttachment) else {
                owsFailDebug("Missing audio attachment component.")
                return
            }
            audioAttachment.startPanGesture(sender: sender,
                                            panHandler: panHandler,
                                            componentDelegate: componentDelegate,
                                            componentView: subcomponentView,
                                            renderItem: renderItem,
                                            swipeToReplyState: swipeToReplyState)
        case .swipeToReply:
            tryToUpdateSwipeToReplyReference(componentView: componentView,
                                             renderItem: renderItem,
                                             swipeToReplyState: swipeToReplyState)
            updateSwipeToReplyProgress(sender: sender,
                                       panHandler: panHandler,
                                       componentDelegate: componentDelegate,
                                       renderItem: renderItem,
                                       componentView: componentView,
                                       swipeToReplyState: swipeToReplyState,
                                       hasFinished: false)
            tryToApplySwipeToReply(componentView: componentView, isAnimated: false)
        }
    }

    public override func handlePanGesture(sender: UIPanGestureRecognizer,
                                          panHandler: CVPanHandler,
                                          componentDelegate: CVComponentDelegate,
                                          componentView: CVComponentView,
                                          renderItem: CVRenderItem,
                                          swipeToReplyState: CVSwipeToReplyState) {
        AssertIsOnMainThread()

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        switch panHandler.panType {
        case .scrubAudio:
            guard let audioAttachment = self.audioAttachment,
                  let subcomponentView = componentView.subcomponentView(key: .audioAttachment) else {
                owsFailDebug("Missing audio attachment component.")
                return
            }
            audioAttachment.handlePanGesture(sender: sender,
                                             panHandler: panHandler,
                                             componentDelegate: componentDelegate,
                                             componentView: subcomponentView,
                                             renderItem: renderItem,
                                             swipeToReplyState: swipeToReplyState)
        case .swipeToReply:
            let hasFinished: Bool
            switch sender.state {
            case .changed:
                hasFinished = false
            case .ended:
                hasFinished = true
            default:
                clearSwipeToReply(componentView: componentView,
                                  renderItem: renderItem,
                                  swipeToReplyState: swipeToReplyState,
                                  isAnimated: false)
                return
            }
            updateSwipeToReplyProgress(sender: sender,
                                       panHandler: panHandler,
                                       componentDelegate: componentDelegate,
                                       renderItem: renderItem,
                                       componentView: componentView,
                                       swipeToReplyState: swipeToReplyState,
                                       hasFinished: hasFinished)
            let hasFailed = sender.state == .failed || sender.state == .cancelled
            let isAnimated = !hasFailed
            tryToApplySwipeToReply(componentView: componentView, isAnimated: isAnimated)
            if sender.state == .ended {
                clearSwipeToReply(componentView: componentView,
                                  renderItem: renderItem,
                                  swipeToReplyState: swipeToReplyState,
                                  isAnimated: true)
            }
        }
    }

    public override func cellDidLayoutSubviews(componentView: CVComponentView,
                                               renderItem: CVRenderItem,
                                               swipeToReplyState: CVSwipeToReplyState) {
        AssertIsOnMainThread()

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return
        }
        tryToUpdateSwipeToReplyReference(componentView: componentView,
                                         renderItem: renderItem,
                                         swipeToReplyState: swipeToReplyState)
        tryToApplySwipeToReply(componentView: componentView, isAnimated: false)
    }

    public override func cellDidBecomeVisible(componentView: CVComponentView,
                                              renderItem: CVRenderItem,
                                              swipeToReplyState: CVSwipeToReplyState) {
        AssertIsOnMainThread()

        guard let componentView = componentView as? CVComponentViewMessage else {
            owsFailDebug("Unexpected componentView.")
            return
        }
        tryToUpdateSwipeToReplyReference(componentView: componentView,
                                         renderItem: renderItem,
                                         swipeToReplyState: swipeToReplyState)
        tryToApplySwipeToReply(componentView: componentView, isAnimated: false)
    }

    private func tryToUpdateSwipeToReplyReference(componentView: CVComponentViewMessage,
                                                  renderItem: CVRenderItem,
                                                  swipeToReplyState: CVSwipeToReplyState) {
        AssertIsOnMainThread()

        guard swipeToReplyReference == nil else {
            // Reference already set.
            return
        }

        guard let contentView = componentView.swipeToReplyContentView else {
            owsFailDebug("Missing outerContentView.")
            return
        }
        let avatarView = componentView.avatarView
        let iconView = componentView.swipeToReplyIconView
        let cellHStack = componentView.cellHStack

        let contentViewCenter = contentView.center
        let avatarViewCenter = avatarView.center
        let iconViewCenter = iconView.center
        guard cellHStack.frame != .zero else {
            // Cell has not been laid out yet.
            return
        }
        var reactionsViewCenter: CGPoint?
        if let reactionsView = componentView.reactionsView {
            reactionsViewCenter = reactionsView.rootView.center
        }
        let reference = CVSwipeToReplyState.Reference(contentViewCenter: contentViewCenter,
                                                      reactionsViewCenter: reactionsViewCenter,
                                                      avatarViewCenter: avatarViewCenter,
                                                      iconViewCenter: iconViewCenter)
        self.swipeToReplyReference = reference
    }

    private var swipeToReplyThreshold: CGFloat = 55

    private func updateSwipeToReplyProgress(sender: UIPanGestureRecognizer,
                                            panHandler: CVPanHandler,
                                            componentDelegate: CVComponentDelegate,
                                            renderItem: CVRenderItem,
                                            componentView: CVComponentViewMessage,
                                            swipeToReplyState: CVSwipeToReplyState,
                                            hasFinished: Bool) {
        AssertIsOnMainThread()

        var xOffset = sender.translation(in: componentView.rootView).x
        // Invert positions for RTL logic, since the user is swiping in the opposite direction.
        if CurrentAppContext().isRTL {
            xOffset = -xOffset
        }
        let hasFailed = sender.state == .failed || sender.state == .cancelled
        let storedOffset = (hasFailed || hasFinished) ? 0 : xOffset
        let progress = CVSwipeToReplyState.Progress(xOffset: storedOffset)
        swipeToReplyState.setProgress(interactionId: renderItem.interactionUniqueId,
                                      progress: progress)
        self.swipeToReplyProgress = progress

        let swipeToReplyIconView = componentView.swipeToReplyIconView

        let isReplyActive = xOffset >= swipeToReplyThreshold

        // If we're transitioning to the active state, play haptic feedback.
        if isReplyActive, !panHandler.isReplyActive {
            ImpactHapticFeedback.impactOccured(style: .light)
        }

        // Update the reply image styling to reflect active state
        let isStarting = sender.state == .began
        let didChange = isReplyActive != panHandler.isReplyActive
        let shouldUpdateViews = isStarting || didChange
        if shouldUpdateViews {
            let shouldAnimate = didChange
            let transform: CGAffineTransform
            let tintColor: UIColor
            if isReplyActive {
                transform = CGAffineTransform(scaleX: 1.16, y: 1.16)
                tintColor = isDarkThemeEnabled ? .ows_gray25 : .ows_gray75
            } else {
                transform = .identity
                tintColor = .ows_gray45
            }
            swipeToReplyIconView.layer.removeAllAnimations()
            swipeToReplyIconView.tintColor = tintColor
            if shouldAnimate {
                UIView.animate(withDuration: 0.2,
                               delay: 0,
                               usingSpringWithDamping: 0.06,
                               initialSpringVelocity: 0.8,
                               options: [.curveEaseInOut, .beginFromCurrentState],
                               animations: {
                                swipeToReplyIconView.transform = transform
                               },
                               completion: nil)
            } else {
                swipeToReplyIconView.transform = transform
            }
        }

        panHandler.isReplyActive = isReplyActive

        if panHandler.isReplyActive && hasFinished {
            let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
            componentDelegate.cvc_didTapReplyToItem(itemViewModel)
        }
    }

    private func tryToApplySwipeToReply(componentView: CVComponentViewMessage,
                                        isAnimated: Bool) {
        AssertIsOnMainThread()

        guard let contentView = componentView.swipeToReplyContentView else {
            owsFailDebug("Missing outerContentView.")
            return
        }
        guard let swipeToReplyReference = swipeToReplyReference,
              let swipeToReplyProgress = swipeToReplyProgress else {
            return
        }
        let swipeToReplyIconView = componentView.swipeToReplyIconView
        let avatarView = componentView.avatarView
        let iconView = componentView.swipeToReplyIconView

        // Scale the translation above or below the desired range,
        // to produce an elastic feeling when you overscroll.
        var alpha = swipeToReplyProgress.xOffset
        if alpha < 0 {
            alpha = alpha / 4
        } else if alpha > swipeToReplyThreshold {
            let overflow = alpha - swipeToReplyThreshold
            alpha = swipeToReplyThreshold + overflow / 4
        }
        let position = CurrentAppContext().isRTL ? -alpha : alpha
        // The swipe content moves at 1/8th the speed of the message bubble,
        // so that it reveals itself from underneath with an elastic feel.
        let slowPosition = position / 8

        var iconAlpha: CGFloat = 1
        let useSwipeFadeTransition = isBorderless
        if useSwipeFadeTransition {
            iconAlpha = CGFloatInverseLerp(alpha, 0, swipeToReplyThreshold).clamp01()
        }

        let animations = {
            swipeToReplyIconView.alpha = iconAlpha
            contentView.center = swipeToReplyReference.contentViewCenter.plusX(position)
            avatarView.center = swipeToReplyReference.avatarViewCenter.plusX(slowPosition)
            iconView.center = swipeToReplyReference.iconViewCenter.plusX(slowPosition)
            if let reactionsViewCenter = swipeToReplyReference.reactionsViewCenter,
               let reactionsView = componentView.reactionsView {
                reactionsView.rootView.center = reactionsViewCenter.plusX(position)
            }
        }
        if isAnimated {
            UIView.animate(withDuration: 0.1,
                           delay: 0,
                           options: [.beginFromCurrentState],
                           animations: animations,
                           completion: nil)
        } else {
            componentView.removeSwipeToReplyAnimations()
            animations()
        }
    }

    private func clearSwipeToReply(componentView: CVComponentViewMessage,
                                   renderItem: CVRenderItem,
                                   swipeToReplyState: CVSwipeToReplyState,
                                   isAnimated: Bool) {
        AssertIsOnMainThread()

        swipeToReplyState.resetProgress(interactionId: renderItem.interactionUniqueId)

        guard let contentView = componentView.swipeToReplyContentView else {
            owsFailDebug("Missing outerContentView.")
            return
        }
        let avatarView = componentView.avatarView
        let iconView = componentView.swipeToReplyIconView
        guard let swipeToReplyReference = swipeToReplyReference else {
            return
        }

        let animations = {
            contentView.center = swipeToReplyReference.contentViewCenter
            avatarView.center = swipeToReplyReference.avatarViewCenter
            iconView.center = swipeToReplyReference.iconViewCenter
            iconView.alpha = 0

            if let reactionsViewCenter = swipeToReplyReference.reactionsViewCenter,
               let reactionsView = componentView.reactionsView {
                reactionsView.rootView.center = reactionsViewCenter
            }
        }

        if isAnimated {
            UIView.animate(withDuration: 0.2, animations: animations)
        } else {
            componentView.removeSwipeToReplyAnimations()
            animations()
        }

        self.swipeToReplyProgress = nil
    }
}

// MARK: -

fileprivate extension CVComponentMessage {

    func configureSubcomponentView(messageView: CVComponentViewMessage,
                                   subcomponent: CVComponent,
                                   cellMeasurement: CVCellMeasurement,
                                   componentDelegate: CVComponentDelegate,
                                   key: CVComponentKey) -> CVComponentView {
        if let subcomponentView = messageView.subcomponentView(key: key) {
            subcomponent.configureForRendering(componentView: subcomponentView,
                                               cellMeasurement: cellMeasurement,
                                               componentDelegate: componentDelegate)
            // TODO: Pin to measured height?
            return subcomponentView
        } else {
            let subcomponentView = subcomponent.buildComponentView(componentDelegate: componentDelegate)
            messageView.setSubcomponentView(key: key, subcomponentView: subcomponentView)
            subcomponent.configureForRendering(componentView: subcomponentView,
                                               cellMeasurement: cellMeasurement,
                                               componentDelegate: componentDelegate)
            // TODO: Pin to measured height?
            return subcomponentView
        }
    }

    func configureSubcomponent(messageView: CVComponentViewMessage,
                               cellMeasurement: CVCellMeasurement,
                               componentDelegate: CVComponentDelegate,
                               key: CVComponentKey) -> CVComponentAndView? {
        guard let subcomponent = self.subcomponent(forKey: key) else {
            return nil
        }
        let subcomponentView = configureSubcomponentView(messageView: messageView,
                                                         subcomponent: subcomponent,
                                                         cellMeasurement: cellMeasurement,
                                                         componentDelegate: componentDelegate,
                                                         key: key)
        return CVComponentAndView(key: key, component: subcomponent, componentView: subcomponentView)
    }

    func buildNestedStackViewConfig(hasNeighborsAbove: Bool,
                                    hasNeighborsBelow: Bool) -> CVStackViewConfig {
        var layoutMargins = conversationStyle.textInsets
        if hasNeighborsAbove {
            layoutMargins.top = Self.textViewVSpacing
        }
        if hasNeighborsBelow {
            layoutMargins.bottom = Self.textViewVSpacing
        }
        return CVStackViewConfig(axis: .vertical,
                                 alignment: .fill,
                                 spacing: Self.textViewVSpacing,
                                 layoutMargins: layoutMargins)
    }

    func buildBorderlessStackViewConfig() -> CVStackViewConfig {
        buildNoMarginsStackViewConfig()
    }

    func buildFullWidthStackViewConfig(includeTopMargin: Bool) -> CVStackViewConfig {
        var layoutMargins = UIEdgeInsets.zero
        if includeTopMargin {
            layoutMargins.top = conversationStyle.textInsets.top
        }
        return CVStackViewConfig(axis: .vertical,
                                 alignment: .fill,
                                 spacing: Self.textViewVSpacing,
                                 layoutMargins: layoutMargins)
    }

    func buildNoMarginsStackViewConfig() -> CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: Self.textViewVSpacing,
                          layoutMargins: .zero)
    }

    func configureSubcomponentStack(messageView: CVComponentViewMessage,
                                    stackView: OWSStackView,
                                    config: CVStackViewConfig,
                                    cellMeasurement: CVCellMeasurement,
                                    componentDelegate: CVComponentDelegate,
                                    keys: [CVComponentKey]) {

        stackView.apply(config: config)

        for key in keys {
            // TODO: configureSubcomponent should probably just return the componentView.
            if let componentAndView = configureSubcomponentForStack(messageView: messageView,
                                                                    axis: config.axis,
                                                                    cellMeasurement: cellMeasurement,
                                                                    componentDelegate: componentDelegate,
                                                                    key: key) {
                let subview = componentAndView.componentView.rootView
                stackView.addArrangedSubview(subview)
            }
        }
    }

    func configureSubcomponentForStack(messageView: CVComponentViewMessage,
                                       axis: NSLayoutConstraint.Axis,
                                       cellMeasurement: CVCellMeasurement,
                                       componentDelegate: CVComponentDelegate,
                                       key: CVComponentKey) -> CVComponentAndView? {

        guard let componentAndView = configureSubcomponent(messageView: messageView,
                                                           cellMeasurement: cellMeasurement,
                                                           componentDelegate: componentDelegate,
                                                           key: key) else {
            return nil
        }
        let subview = componentAndView.componentView.rootView

        // We pin the subcomponent view to its measured size
        // during configuration for rendering.
        if let subcomponentSize = cellMeasurement.size(key: key.asKey) {
            switch axis {
            case .horizontal:
                owsAssertDebug(subcomponentSize.width > 0)
                messageView.layoutConstraints.append(subview.autoSetDimension(.width, toSize: subcomponentSize.width))
            case .vertical:
                owsAssertDebug(subcomponentSize.height > 0)
                messageView.layoutConstraints.append(subview.autoSetDimension(.height, toSize: subcomponentSize.height))
            @unknown default:
                owsFailDebug("Invalid axis.")
            }
        } else {
            owsFailDebug("Missing size for key: \(key)")
        }

        return componentAndView
    }

    func subcomponents(forKeys keys: [CVComponentKey]) -> [CVComponent] {
        keys.compactMap { key in
            guard let subcomponent = self.subcomponent(forKey: key) else {
                // Not all subcomponents may be present.
                return nil
            }
            return subcomponent
        }
    }

    func buildSubcomponentMap(keys: [CVComponentKey]) -> [CVComponentKey: CVComponent] {
        var result = [CVComponentKey: CVComponent]()
        for key in keys {
            guard let subcomponent = self.subcomponent(forKey: key) else {
                // Not all subcomponents may be present.
                continue
            }
            result[key] = subcomponent
        }
        return result
    }
}
