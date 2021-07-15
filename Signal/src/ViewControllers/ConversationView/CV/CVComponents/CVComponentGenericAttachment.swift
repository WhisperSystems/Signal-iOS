//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import QuickLook
import PassKit

@objc
public class CVComponentGenericAttachment: CVComponentBase, CVComponent {

    private let genericAttachment: CVComponentState.GenericAttachment
    private var attachment: TSAttachment { genericAttachment.attachment }
    private var attachmentStream: TSAttachmentStream? { genericAttachment.attachmentStream }
    private var attachmentPointer: TSAttachmentPointer? { genericAttachment.attachmentPointer }

    init(itemModel: CVItemModel, genericAttachment: CVComponentState.GenericAttachment) {
        self.genericAttachment = genericAttachment

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewGenericAttachment()
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewGenericAttachment else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let hStackView = componentView.hStackView
        let vStackView = componentView.vStackView

        var hSubviews = [UIView]()

        if let downloadView = tryToBuildProgressView() {
            hSubviews.append(downloadView)
        } else {
            let iconImageView = componentView.iconImageView
            if let icon = UIImage(named: "generic-attachment") {
                owsAssertDebug(icon.size == iconSize)
                iconImageView.image = icon
            } else {
                owsFailDebug("Missing icon.")
            }
            hSubviews.append(iconImageView)

            let fileTypeLabel = componentView.fileTypeLabel
            fileTypeLabelConfig.applyForRendering(label: fileTypeLabel)
            fileTypeLabel.adjustsFontSizeToFitWidth = true
            fileTypeLabel.minimumScaleFactor = 0.25
            fileTypeLabel.textAlignment = .center
            // Center on icon.
            iconImageView.addSubview(fileTypeLabel)
            vStackView.addLayoutBlock { _ in
                guard let superview = fileTypeLabel.superview else {
                    owsFailDebug("Missing superview.")
                    return
                }
                var labelSize = fileTypeLabel.sizeThatFitsMaxSize
                labelSize.width = min(labelSize.width,
                                      superview.bounds.width - 15)

                let labelFrame = CGRect(origin: ((superview.bounds.size - labelSize) * 0.5).asPoint,
                                        size: labelSize)
                fileTypeLabel.frame = labelFrame
            }
        }

        let topLabel = componentView.topLabel
        let bottomLabel = componentView.bottomLabel

        topLabelConfig.applyForRendering(label: topLabel)
        bottomLabelConfig.applyForRendering(label: bottomLabel)

        let vSubviews = [
            componentView.topLabel,
            componentView.bottomLabel
        ]
        vStackView.configure(config: vStackConfig,
                             cellMeasurement: cellMeasurement,
                             measurementKey: Self.measurementKey_vStack,
                             subviews: vSubviews)
        hSubviews.append(vStackView)
        hStackView.configure(config: hStackConfig,
                                 cellMeasurement: cellMeasurement,
                                 measurementKey: Self.measurementKey_hStack,
                                 subviews: hSubviews)
    }

    private var hStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .center,
                          spacing: hSpacing,
                          layoutMargins: UIEdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
    }

    private var vStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .leading,
                          spacing: labelVSpacing,
                          layoutMargins: .zero)
    }

    private var topLabelConfig: CVLabelConfig {
        var text: String = attachment.sourceFilename?.ows_stripped() ?? ""
        if text.isEmpty,
           let fileExtension = MIMETypeUtil.fileExtension(forMIMEType: attachment.contentType) {
            text = (fileExtension as NSString).localizedUppercase
        }
        if text.isEmpty {
            text = NSLocalizedString("GENERIC_ATTACHMENT_LABEL", comment: "A label for generic attachments.")
        }
        return CVLabelConfig(text: text,
                             font: UIFont.ows_dynamicTypeBody,
                             textColor: conversationStyle.bubbleTextColor(isIncoming: isIncoming),
                             lineBreakMode: .byTruncatingMiddle)
    }

    private var bottomLabelConfig: CVLabelConfig {

        // We don't want to show the file size while the attachment is downloading.
        // To avoid layout jitter when the download completes, we reserve space in
        // the layout using a whitespace string.
        var text = " "

        if let attachmentPointer = self.attachmentPointer {
            var textComponents = [String]()

            if attachmentPointer.byteCount > 0 {
                textComponents.append(OWSFormat.formatFileSize(UInt(attachmentPointer.byteCount)))
            }

            switch attachmentPointer.state {
            case .enqueued, .downloading:
                break
            case .failed, .pendingMessageRequest, .pendingManualDownload:
                textComponents.append(NSLocalizedString("ACTION_TAP_TO_DOWNLOAD", comment: "A label for 'tap to download' buttons."))
            @unknown default:
                owsFailDebug("Invalid value.")
                break
            }

            if !textComponents.isEmpty {
                text = textComponents.joined(separator: " • ")
            }
        } else if let attachmentStream = attachmentStream {
            if let originalFilePath = attachmentStream.originalFilePath,
               let nsFileSize = OWSFileSystem.fileSize(ofPath: originalFilePath) {
                let fileSize = nsFileSize.uintValue
                if fileSize > 0 {
                    text = OWSFormat.formatFileSize(fileSize)
                }
            }
        } else {
            owsFailDebug("Invalid attachment")
        }

        return CVLabelConfig(text: text,
                             font: UIFont.ows_dynamicTypeCaption1,
                             textColor: conversationStyle.bubbleSecondaryTextColor(isIncoming: isIncoming),
                             lineBreakMode: .byTruncatingMiddle)
    }

    private var fileTypeLabelConfig: CVLabelConfig {
        var filename: String = attachment.sourceFilename ?? ""
        if filename.isEmpty,
           let attachmentStream = attachmentStream,
           let originalFilePath = attachmentStream.originalFilePath {
            filename = (originalFilePath as NSString).lastPathComponent
        }
        var fileExtension: String = (filename as NSString).pathExtension
        if fileExtension.isEmpty {
            fileExtension = MIMETypeUtil.fileExtension(forMIMEType: attachment.contentType) ?? ""
        }
        let text = (fileExtension as NSString).localizedUppercase

        return CVLabelConfig(text: text,
                             font: UIFont.ows_dynamicTypeCaption1.ows_semibold,
                             textColor: .ows_gray90,
                             lineBreakMode: .byTruncatingTail)
    }

    private func tryToBuildProgressView() -> UIView? {

        let direction: CVAttachmentProgressView.Direction
        switch CVAttachmentProgressView.progressType(forAttachment: attachment,
                                                     interaction: interaction) {
        case .none:
            return nil
        case .uploading:
            // We currently only show progress for downloads here.
            return nil
        case .pendingDownload(let attachmentPointer):
            direction = .download(attachmentPointer: attachmentPointer)
        case .downloading(let attachmentPointer):
            direction = .download(attachmentPointer: attachmentPointer)
        case .restoring:
            // TODO: We could easily show progress for restores.
            owsFailDebug("Restoring progress type.")
            return nil
        case .unknown:
            owsFailDebug("Unknown progress type.")
            return nil
        }

        return CVAttachmentProgressView(direction: direction,
                                        style: .withoutCircle(diameter: progressSize),
                                        conversationStyle: conversationStyle)
    }

    private var hasProgressView: Bool {
        switch CVAttachmentProgressView.progressType(forAttachment: attachment,
                                                     interaction: interaction) {
        case .none,
             .uploading:
            // We currently only show progress for downloads here.
            return false
        case .pendingDownload,
             .downloading:
            return true
        case .restoring:
            // TODO: We could easily show progress for restores.
            owsFailDebug("Restoring progress type.")
            return false
        case .unknown:
            owsFailDebug("Unknown progress type.")
            return false
        }
    }

    private let hSpacing: CGFloat = 8
    private let labelVSpacing: CGFloat = 2
    private let iconSize = CGSize(width: 36, height: CGFloat(AvatarBuilder.standardAvatarSizePoints))
    private let progressSize: CGFloat = 36

    private static let measurementKey_hStack = "CVComponentGenericAttachment.measurementKey_hStack"
    private static let measurementKey_vStack = "CVComponentGenericAttachment.measurementKey_vStack"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let leftViewSize: CGSize = (hasProgressView
                                        ? .square(progressSize)
                                        : iconSize)

        let maxLabelWidth = max(0, maxWidth - (leftViewSize.width +
                                                hSpacing +
                                                hStackConfig.layoutMargins.totalWidth +
                                                vStackConfig.layoutMargins.totalWidth))
        let topLabelSize = CVText.measureLabel(config: topLabelConfig, maxWidth: maxLabelWidth)
        let bottomLabelSize = CVText.measureLabel(config: bottomLabelConfig, maxWidth: maxLabelWidth)

        var vSubviewInfos = [ManualStackSubviewInfo]()
        vSubviewInfos.append(topLabelSize.asManualSubviewInfo())
        vSubviewInfos.append(bottomLabelSize.asManualSubviewInfo())

        let vStackMeasurement = ManualStackView.measure(config: vStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_vStack,
                                                            subviewInfos: vSubviewInfos)

        var hSubviewInfos = [ManualStackSubviewInfo]()
        hSubviewInfos.append(leftViewSize.asManualSubviewInfo(hasFixedSize: true))
        hSubviewInfos.append(vStackMeasurement.measuredSize.asManualSubviewInfo)
        let hStackMeasurement = ManualStackView.measure(config: hStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_hStack,
                                                            subviewInfos: hSubviewInfos,
                                                            maxWidth: maxWidth)
        return hStackMeasurement.measuredSize
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        if attachmentStream != nil {
            switch componentDelegate.cvc_didTapGenericAttachment(self) {
            case .handledByDelegate:
                break
            case .default:
                showShareUI(from: componentView.rootView)
            }
        } else if let attachmentPointer = attachmentPointer {
            switch attachmentPointer.state {
            case .failed, .pendingMessageRequest, .pendingManualDownload:
                guard let message = renderItem.interaction as? TSMessage else {
                    owsFailDebug("Invalid interaction.")
                    return true
                }
                componentDelegate.cvc_didTapFailedOrPendingDownloads(message)
            case .enqueued, .downloading:
                break
            default:
                break
            }
        } else {
            owsFailDebug("Invalid attachment.")
        }

        return true
    }

    public var canQuickLook: Bool {
        guard #available(iOS 13, *) else { return false }
        guard let url = attachmentStream?.originalMediaURL else {
            return false
        }
        return QLPreviewController.canPreview(url as NSURL)
    }

    /// Returns the `PKPass` represented by this attachment, if any.
    public func representedPKPass() -> PKPass? {
        guard attachmentStream?.contentType == "application/vnd.apple.pkpass" else {
            return nil
        }
        guard let data = try? attachmentStream?.readDataFromFile() else {
            return nil
        }
        return try? PKPass(data: data)
    }

    @objc(showShareUIFromView:)
    public func showShareUI(from view: UIView) {
        guard let attachmentStream = attachmentStream else {
            owsFailDebug("should not show the share UI unless there's a downloaded attachment")
            return
        }
        // TODO: Ensure share UI is shown from correct location.
        AttachmentSharing.showShareUI(forAttachment: attachmentStream, sender: view)
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    public class CVComponentViewGenericAttachment: NSObject, CVComponentView {

        fileprivate let hStackView = ManualStackView(name: "GenericAttachment.hStackView")
        fileprivate let vStackView = ManualStackView(name: "GenericAttachment.vStackView")
        fileprivate let topLabel = CVLabel()
        fileprivate let bottomLabel = CVLabel()
        fileprivate let fileTypeLabel = CVLabel()
        fileprivate let iconImageView = CVImageView()

        public var isDedicatedCellView = false

        public var rootView: UIView {
            hStackView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            hStackView.reset()
            vStackView.reset()

            topLabel.text = nil
            bottomLabel.text = nil
            fileTypeLabel.text = nil
            iconImageView.image = nil
        }
    }
}

extension CVComponentGenericAttachment: QLPreviewControllerDataSource {
    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }

    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        owsAssertDebug(index == 0)
        return (attachmentStream?.originalMediaURL as QLPreviewItem?) ?? UnavailableItem()
    }

    private class UnavailableItem: NSObject, QLPreviewItem {
        var previewItemURL: URL? { nil }
    }
}

// MARK: -

extension CVComponentGenericAttachment: CVAccessibilityComponent {
    public var accessibilityDescription: String {
        // TODO: We could include information about the attachment format,
        //       and/or filename, and download state.
        NSLocalizedString("ACCESSIBILITY_LABEL_ATTACHMENT",
                          comment: "Accessibility label for attachment.")
    }
}
