//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public enum LinkPreviewError: Int, Error {
    /// A preview could not be generated from available input
    case noPreview
    /// A preview should have been generated, but something unexpected caused it to fail
    case invalidPreview
    /// A preview could not be generated due to an issue fetching a network resource
    case fetchFailure
    /// A preview could not be generated because the feature is disabled
    case featureDisabled
}

// MARK: - OWSLinkPreviewDraft

// This contains the info for a link preview "draft".
public class OWSLinkPreviewDraft: NSObject {
    @objc
    public var url: URL

    @objc
    public var urlString: String {
        return url.absoluteString
    }

    @objc
    public var title: String?

    @objc
    public var imageData: Data?

    @objc
    public var imageMimeType: String?

    @objc
    public var previewDescription: String?

    @objc
    public var date: Date?

    public init(url: URL, title: String?, imageData: Data? = nil, imageMimeType: String? = nil) {
        self.url = url
        self.title = title
        self.imageData = imageData
        self.imageMimeType = imageMimeType

        super.init()
    }

    fileprivate func isValid() -> Bool {
        var hasTitle = false
        if let titleValue = title {
            hasTitle = titleValue.count > 0
        }
        let hasImage = imageData != nil && imageMimeType != nil
        return hasTitle || hasImage
    }

    @objc
    public func displayDomain() -> String? {
        return OWSLinkPreviewManager.displayDomain(forUrl: urlString)
    }
}

// MARK: - OWSLinkPreview

@objc
public class OWSLinkPreview: MTLModel {

    @objc
    public var urlString: String?

    @objc
    public var title: String?

    @objc
    public var imageAttachmentId: String?

    @objc
    public var previewDescription: String?

    @objc
    public var date: Date?

    @objc
    public init(urlString: String, title: String?, imageAttachmentId: String?) {
        self.urlString = urlString
        self.title = title
        self.imageAttachmentId = imageAttachmentId

        super.init()
    }

    @objc
    public override init() {
        super.init()
    }

    @objc
    public required init!(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    @objc
    public class func isNoPreviewError(_ error: Error) -> Bool {
        guard let error = error as? LinkPreviewError else {
            return false
        }
        return error == .noPreview
    }

    @objc
    public class func buildValidatedLinkPreview(dataMessage: SSKProtoDataMessage,
                                                body: String?,
                                                transaction: SDSAnyWriteTransaction) throws -> OWSLinkPreview {
        guard let previewProto = dataMessage.preview.first else {
            throw LinkPreviewError.noPreview
        }
        guard dataMessage.attachments.count < 1 else {
            Logger.error("Discarding link preview; message has attachments.")
            throw LinkPreviewError.invalidPreview
        }
        let urlString = previewProto.url

        guard let url = URL(string: urlString), url.isPermittedLinkPreviewUrl() else {
            Logger.error("Could not parse preview url.")
            throw LinkPreviewError.invalidPreview
        }

        guard let body = body, body.contains(urlString) else {
            Logger.error("Url not present in body")
            throw LinkPreviewError.invalidPreview
        }

        var title: String?
        var previewDescription: String?
        if let rawTitle = previewProto.title {
            let normalizedTitle = normalizeString(rawTitle, maxLines: 2)
            if normalizedTitle.count > 0 {
                title = normalizedTitle
            }
        }
        if let rawDescription = previewProto.previewDescription, previewProto.title != previewProto.previewDescription {
            let normalizedDescription = normalizeString(rawDescription, maxLines: 3)
            if normalizedDescription.count > 0 {
                previewDescription = normalizedDescription
            }
        }

        var imageAttachmentId: String?
        if let imageProto = previewProto.image {
            if let imageAttachmentPointer = TSAttachmentPointer(fromProto: imageProto, albumMessage: nil) {
                imageAttachmentPointer.anyInsert(transaction: transaction)
                imageAttachmentId = imageAttachmentPointer.uniqueId
            } else {
                Logger.error("Could not parse image proto.")
                throw LinkPreviewError.invalidPreview
            }
        }

        let linkPreview = OWSLinkPreview(urlString: urlString, title: title, imageAttachmentId: imageAttachmentId)
        linkPreview.previewDescription = previewDescription

        // Zero check required. Some devices in the wild will explicitly set zero to mean "no date"
        if previewProto.hasDate, previewProto.date > 0 {
            linkPreview.date = Date(millisecondsSince1970: previewProto.date)
        }

        guard linkPreview.isValid() else {
            Logger.error("Preview has neither title nor image.")
            throw LinkPreviewError.invalidPreview
        }

        return linkPreview
    }

    @objc
    public class func buildValidatedLinkPreview(fromInfo info: OWSLinkPreviewDraft,
                                                transaction: SDSAnyWriteTransaction) throws -> OWSLinkPreview {
        guard SSKPreferences.areLinkPreviewsEnabled(transaction: transaction) else {
            throw LinkPreviewError.featureDisabled
        }
        let imageAttachmentId = OWSLinkPreview.saveAttachmentIfPossible(imageData: info.imageData,
                                                                        imageMimeType: info.imageMimeType,
                                                                        transaction: transaction)

        let linkPreview = OWSLinkPreview(urlString: info.urlString, title: info.title, imageAttachmentId: imageAttachmentId)
        linkPreview.previewDescription = info.previewDescription
        linkPreview.date = info.date

        guard linkPreview.isValid() else {
            owsFailDebug("Preview has neither title nor image.")
            throw LinkPreviewError.invalidPreview
        }

        return linkPreview
    }

    private class func saveAttachmentIfPossible(imageData: Data?,
                                                imageMimeType: String?,
                                                transaction: SDSAnyWriteTransaction) -> String? {
        guard let imageData = imageData else {
            return nil
        }
        guard let imageMimeType = imageMimeType else {
            return nil
        }
        guard let fileExtension = MIMETypeUtil.fileExtension(forMIMEType: imageMimeType) else {
            return nil
        }
        let fileSize = imageData.count
        guard fileSize > 0 else {
            owsFailDebug("Invalid file size for image data.")
            return nil
        }
        let contentType = imageMimeType

        let fileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: fileExtension)
        do {
            try imageData.write(to: fileUrl)
            let dataSource = try DataSourcePath.dataSource(with: fileUrl, shouldDeleteOnDeallocation: true)
            let attachment = TSAttachmentStream(contentType: contentType, byteCount: UInt32(fileSize), sourceFilename: nil, caption: nil, albumMessageId: nil)
            try attachment.writeConsumingDataSource(dataSource)
            attachment.anyInsert(transaction: transaction)

            return attachment.uniqueId
        } catch {
            owsFailDebug("Could not write data source for: \(fileUrl), error: \(error)")
            return nil
        }
    }

    private func isValid() -> Bool {
        var hasTitle = false
        if let titleValue = title {
            hasTitle = titleValue.count > 0
        }
        let hasImage = imageAttachmentId != nil
        return hasTitle || hasImage
    }

    @objc
    public func removeAttachment(transaction: SDSAnyWriteTransaction) {
        guard let imageAttachmentId = imageAttachmentId else {
            owsFailDebug("No attachment id.")
            return
        }
        guard let attachment = TSAttachment.anyFetch(uniqueId: imageAttachmentId, transaction: transaction) else {
            owsFailDebug("Could not load attachment.")
            return
        }
        attachment.anyRemove(transaction: transaction)
    }

    @objc
    public func displayDomain() -> String? {
        return OWSLinkPreviewManager.displayDomain(forUrl: urlString)
    }
}

// MARK: -

@objc
public class OWSLinkPreviewManager: NSObject, Dependencies {

    // Although link preview fetches are non-blocking, the user may still end up
    // waiting for the fetch to complete. Because of this, UserInitiated is likely
    // most appropriate QoS.
    static let workQueue: DispatchQueue = .sharedUserInitiated

    // MARK: - Public

    @objc(findFirstValidUrlInSearchString:)
    public func findFirstValidUrl(in searchString: String) -> URL? {
        guard areLinkPreviewsEnabledWithSneakyTransaction() else { return nil }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            owsFailDebug("Could not create NSDataDetector")
            return nil
        }

        let allMatches = detector.matches(
            in: searchString,
            options: [],
            range: searchString.entireRange)

        return allMatches.first(where: {
            guard let parsedUrl = $0.url else { return false }
            guard let matchedRange = Range($0.range, in: searchString) else { return false }
            let matchedString = String(searchString[matchedRange])
            return parsedUrl.isPermittedLinkPreviewUrl(parsedFrom: matchedString)
        })?.url
    }

    @objc(fetchLinkPreviewForUrl:)
    @available(swift, obsoleted: 1.0)
    public func fetchLinkPreview(for url: URL) -> AnyPromise {
        let promise: Promise<OWSLinkPreviewDraft> = fetchLinkPreview(for: url)
        return AnyPromise(promise)
    }

    public func fetchLinkPreview(for url: URL) -> Promise<OWSLinkPreviewDraft> {
        guard areLinkPreviewsEnabledWithSneakyTransaction() else {
            return Promise(error: LinkPreviewError.featureDisabled)
        }

        return firstly(on: Self.workQueue) { () -> Promise<OWSLinkPreviewDraft> in
            if StickerPackInfo.isStickerPackShare(url) {
                return self.linkPreviewDraft(forStickerShare: url)
            } else if GroupManager.isPossibleGroupInviteLink(url) {
                return self.linkPreviewDraft(forGroupInviteLink: url)
            } else {
                return self.fetchLinkPreview(forGenericUrl: url)
            }
        }.map(on: Self.workQueue) { (linkPreviewDraft) -> OWSLinkPreviewDraft in
            guard linkPreviewDraft.isValid() else {
                throw LinkPreviewError.noPreview
            }
            return linkPreviewDraft
        }
    }

    // MARK: - Private

    private func fetchLinkPreview(forGenericUrl url: URL) -> Promise<OWSLinkPreviewDraft> {
        firstly(on: Self.workQueue) { () -> Promise<(URL, String)> in
            self.fetchStringResource(from: url)

        }.then(on: Self.workQueue) { (respondingUrl, rawHTML) -> Promise<OWSLinkPreviewDraft> in
            let content = HTMLMetadata.construct(parsing: rawHTML)
            let rawTitle = content.ogTitle ?? content.titleTag
            let normalizedTitle = rawTitle.map { normalizeString($0, maxLines: 2) }
            let draft = OWSLinkPreviewDraft(url: url, title: normalizedTitle)

            let rawDescription = content.ogDescription ?? content.description
            if rawDescription != rawTitle, let description = rawDescription {
                draft.previewDescription = normalizeString(description, maxLines: 3)
            }

            draft.date = content.dateForLinkPreview

            guard let imageUrlString = content.ogImageUrlString ?? content.faviconUrlString,
                  let imageUrl = URL(string: imageUrlString, relativeTo: respondingUrl) else {
                return Promise.value(draft)
            }

            return firstly(on: Self.workQueue) { () -> Promise<Data> in
                self.fetchImageResource(from: imageUrl)
            }.then(on: Self.workQueue) { (imageData: Data) -> Promise<PreviewThumbnail?> in
                Self.previewThumbnail(srcImageData: imageData, srcMimeType: nil)
            }.map(on: Self.workQueue) { (previewThumbnail: PreviewThumbnail?) -> OWSLinkPreviewDraft in
                guard let previewThumbnail = previewThumbnail else {
                    return draft
                }
                draft.imageData = previewThumbnail.imageData
                draft.imageMimeType = previewThumbnail.mimetype
                return draft
            }.recover(on: Self.workQueue) { (_) -> Promise<OWSLinkPreviewDraft> in
                return Promise.value(draft)
            }
        }
    }

    // MARK: - Private, Utilities

    func areLinkPreviewsEnabledWithSneakyTransaction() -> Bool {
        return databaseStorage.read { transaction in
            SSKPreferences.areLinkPreviewsEnabled(transaction: transaction)
        }
    }

    // MARK: - Private, Networking

    private func buildOWSURLSession() -> OWSURLSession {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.urlCache = nil
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData

        // Twitter doesn't return OpenGraph tags to Signal
        // `curl -A Signal "https://twitter.com/signalapp/status/1280166087577997312?s=20"`
        // If this ever changes, we can switch back to our default User-Agent
        let userAgentString = "WhatsApp/2"
        let extraHeaders: [String: String] = ["User-Agent": userAgentString]

        let urlSession = OWSURLSession(baseUrl: nil,
                                       securityPolicy: OWSURLSession.defaultSecurityPolicy,
                                       configuration: sessionConfig,
                                       censorshipCircumventionHost: nil,
                                       extraHeaders: extraHeaders,
                                       maxResponseSize: Self.maxFetchedContentSize)
        urlSession.allowRedirects = true
        urlSession.customRedirectHandler = { request in
            guard request.url?.isPermittedLinkPreviewUrl() == true else {
                return nil
            }
            return request
        }
        return urlSession
    }

    func fetchStringResource(from url: URL) -> Promise<(URL, String)> {
        firstly(on: Self.workQueue) { () -> Promise<(OWSHTTPResponse)> in
            self.buildOWSURLSession().dataTaskPromise(url.absoluteString, method: .get)
                .catchCancellation(andThrow: LinkPreviewError.invalidPreview)

        }.map(on: Self.workQueue) { (httpResponse: OWSHTTPResponse) -> (URL, String) in
            let task = httpResponse.task
            guard let response = task.response as? HTTPURLResponse,
                  let respondingUrl = response.url,
                  response.statusCode >= 200 && response.statusCode < 300 else {
                Logger.warn("Invalid response: \(type(of: task.response)).")
                throw LinkPreviewError.fetchFailure
            }
            guard let data = httpResponse.responseData,
                  let string = String(data: data, urlResponse: response),
                  string.count > 0 else {
                Logger.warn("Response object could not be parsed")
                throw LinkPreviewError.invalidPreview
            }

            return (respondingUrl, string)
        }
    }

    private func fetchImageResource(from url: URL) -> Promise<Data> {
        firstly(on: Self.workQueue) { () -> Promise<(OWSHTTPResponse)> in
            self.buildOWSURLSession().dataTaskPromise(url.absoluteString, method: .get)
                .catchCancellation(andThrow: LinkPreviewError.invalidPreview)

        }.map(on: Self.workQueue) { (httpResponse: OWSHTTPResponse) -> Data in
            try autoreleasepool {
                let task = httpResponse.task
                guard let response = task.response as? HTTPURLResponse,
                      response.statusCode >= 200 && response.statusCode < 300 else {
                    Logger.warn("Invalid response: \(type(of: task.response)).")
                    throw LinkPreviewError.fetchFailure
                }
                guard let rawData = httpResponse.responseData,
                      rawData.count < Self.maxFetchedContentSize else {
                    Logger.warn("Response object could not be parsed")
                    throw LinkPreviewError.invalidPreview
                }
                return rawData
            }
        }
    }

    // MARK: - Private, Constants

    private static let maxFetchedContentSize = 2 * 1024 * 1024
    private static let allowedMIMETypes: Set = [OWSMimeTypeImagePng, OWSMimeTypeImageJpeg]

    // MARK: - Preview Thumbnails

    private struct PreviewThumbnail {
        let imageData: Data
        let mimetype: String
    }

    private static func previewThumbnail(srcImageData: Data?, srcMimeType: String?) -> Promise<PreviewThumbnail?> {
        guard let srcImageData = srcImageData else {
            return Promise.value(nil)
        }
        return firstly(on: Self.workQueue) { () -> PreviewThumbnail? in
            let imageMetadata = (srcImageData as NSData).imageMetadata(withPath: nil, mimeType: srcMimeType)
            guard imageMetadata.isValid else {
                return nil
            }
            let hasValidFormat = imageMetadata.imageFormat != .unknown
            guard hasValidFormat else {
                return nil
            }

            let maxImageSize: CGFloat = 2400

            switch imageMetadata.imageFormat {
            case .unknown:
                owsFailDebug("Invalid imageFormat.")
                return nil
            case .webp:
                guard let stillImage = (srcImageData as NSData).stillForWebpData() else {
                    owsFailDebug("Couldn't derive still image for Webp.")
                    return nil
                }

                var stillThumbnail = stillImage
                let imageSize = stillImage.pixelSize
                let shouldResize = imageSize.width > maxImageSize || imageSize.height > maxImageSize
                if shouldResize {
                    guard let resizedImage = stillImage.resized(withMaxDimensionPixels: maxImageSize) else {
                        owsFailDebug("Couldn't resize image.")
                        return nil
                    }
                    stillThumbnail = resizedImage
                }

                guard let stillData = stillThumbnail.pngData() else {
                    owsFailDebug("Couldn't derive still image for Webp.")
                    return nil
                }
                return PreviewThumbnail(imageData: stillData, mimetype: OWSMimeTypeImagePng)
            default:
                guard let mimeType = imageMetadata.mimeType else {
                    owsFailDebug("Unknown mimetype for thumbnail.")
                    return nil
                }

                let imageSize = imageMetadata.pixelSize
                let shouldResize = imageSize.width > maxImageSize || imageSize.height > maxImageSize
                if (imageMetadata.imageFormat == .jpeg || imageMetadata.imageFormat == .png),
                    !shouldResize {
                    // If we don't need to resize or convert the file format,
                    // return the original data.
                    return PreviewThumbnail(imageData: srcImageData, mimetype: mimeType)
                }

                guard let srcImage = UIImage(data: srcImageData) else {
                    owsFailDebug("Could not parse image.")
                    return nil
                }

                guard let dstImage = srcImage.resized(withMaxDimensionPixels: maxImageSize) else {
                    owsFailDebug("Could not resize image.")
                    return nil
                }
                if imageMetadata.hasAlpha {
                    guard let dstData = dstImage.pngData() else {
                        owsFailDebug("Could not write resized image to PNG.")
                        return nil
                    }
                    return PreviewThumbnail(imageData: dstData, mimetype: OWSMimeTypeImagePng)
                } else {
                    guard let dstData = dstImage.jpegData(compressionQuality: 0.8) else {
                        owsFailDebug("Could not write resized image to JPEG.")
                        return nil
                    }
                    return PreviewThumbnail(imageData: dstData, mimetype: OWSMimeTypeImageJpeg)
                }
            }
        }
    }

    // MARK: - Stickers

    private func linkPreviewDraft(forStickerShare url: URL) -> Promise<OWSLinkPreviewDraft> {
        Logger.verbose("url: \(url)")

        guard let stickerPackInfo = StickerPackInfo.parseStickerPackShare(url) else {
            Logger.error("Could not parse url.")
            return Promise(error: LinkPreviewError.invalidPreview)
        }

        // tryToDownloadStickerPack will use locally saved data if possible.
        return firstly(on: Self.workQueue) {
            StickerManager.tryToDownloadStickerPack(stickerPackInfo: stickerPackInfo)
        }.then(on: Self.workQueue) { (stickerPack) -> Promise<OWSLinkPreviewDraft> in
            let coverInfo = stickerPack.coverInfo
            // tryToDownloadSticker will use locally saved data if possible.
            return firstly { () -> Promise<URL> in
                StickerManager.tryToDownloadSticker(stickerPack: stickerPack, stickerInfo: coverInfo)
            }.map(on: Self.workQueue) { coverUrl in
                return try Data(contentsOf: coverUrl)
            }.then(on: Self.workQueue) { (coverData) -> Promise<PreviewThumbnail?> in
                Self.previewThumbnail(srcImageData: coverData, srcMimeType: OWSMimeTypeImageWebp)
            }.map(on: Self.workQueue) { (previewThumbnail: PreviewThumbnail?) -> OWSLinkPreviewDraft in
                guard let previewThumbnail = previewThumbnail else {
                    return OWSLinkPreviewDraft(url: url,
                                               title: stickerPack.title?.filterForDisplay)
                }
                return OWSLinkPreviewDraft(url: url,
                                           title: stickerPack.title?.filterForDisplay,
                                           imageData: previewThumbnail.imageData,
                                           imageMimeType: previewThumbnail.mimetype)
            }
        }
    }

    // MARK: - Group Invite Links

    private func linkPreviewDraft(forGroupInviteLink url: URL) -> Promise<OWSLinkPreviewDraft> {
        Logger.verbose("url: \(url)")

        return firstly(on: Self.workQueue) { () -> GroupInviteLinkInfo in
            guard let groupInviteLinkInfo = GroupManager.parseGroupInviteLink(url) else {
                Logger.error("Could not parse URL.")
                throw LinkPreviewError.invalidPreview
            }
            return groupInviteLinkInfo
        }.then(on: Self.workQueue) { (groupInviteLinkInfo: GroupInviteLinkInfo) -> Promise<OWSLinkPreviewDraft> in
            let groupV2ContextInfo = try self.groupsV2.groupV2ContextInfo(forMasterKeyData: groupInviteLinkInfo.masterKey)
            return firstly {
                Self.groupsV2Swift.fetchGroupInviteLinkPreview(inviteLinkPassword: groupInviteLinkInfo.inviteLinkPassword,
                                                               groupSecretParamsData: groupV2ContextInfo.groupSecretParamsData,
                                                               allowCached: false)
            }.then(on: Self.workQueue) { (groupInviteLinkPreview: GroupInviteLinkPreview) in
                return firstly { () -> Promise<Data?> in
                    guard let avatarUrlPath = groupInviteLinkPreview.avatarUrlPath else {
                        return Promise.value(nil)
                    }
                    return firstly { () -> Promise<Data> in
                        self.groupsV2Swift.fetchGroupInviteLinkAvatar(avatarUrlPath: avatarUrlPath,
                                                                      groupSecretParamsData: groupV2ContextInfo.groupSecretParamsData)
                    }.map { (avatarData: Data) -> Data? in
                        return avatarData
                    }.recover { (error: Error) -> Promise<Data?> in
                        owsFailDebugUnlessNetworkFailure(error)
                        return Promise.value(nil)
                    }
                }.then(on: Self.workQueue) { (imageData: Data?) -> Promise<PreviewThumbnail?> in
                    Self.previewThumbnail(srcImageData: imageData, srcMimeType: nil)
                }.map(on: Self.workQueue) { (previewThumbnail: PreviewThumbnail?) -> OWSLinkPreviewDraft in
                    guard let previewThumbnail = previewThumbnail else {
                        return OWSLinkPreviewDraft(url: url,
                                                   title: groupInviteLinkPreview.title)
                    }
                    return OWSLinkPreviewDraft(url: url,
                                               title: groupInviteLinkPreview.title,
                                               imageData: previewThumbnail.imageData,
                                               imageMimeType: previewThumbnail.mimetype)
                }
            }
        }
    }
}

fileprivate extension URL {
    private static let schemeAllowSet: Set = ["https"]
    private static let tldRejectSet: Set = ["onion", "i2p"]
    private static let urlDelimeters: Set<Character> = Set(":/?#[]@")

    var mimeType: String? {
        guard pathExtension.count > 0 else {
            return nil
        }
        guard let mimeType = MIMETypeUtil.mimeType(forFileExtension: pathExtension) else {
            Logger.error("Image url has unknown content type: \(pathExtension).")
            return nil
        }
        return mimeType
    }

    /// Helper method that validates:
    /// - TLD is permitted
    /// - Comprised of valid character set
    static private func isValidHostname(_ hostname: String) -> Bool {
        // Technically, a TLD separator can be something other than a period (e.g. https://一二三。中国)
        // But it looks like NSURL/NSDataDetector won't even parse that. So we'll require periods for now
        let hostnameComponents = hostname.split(separator: ".")
        guard hostnameComponents.count >= 2, let tld = hostnameComponents.last?.lowercased() else {
            return false
        }
        let isValidTLD = !Self.tldRejectSet.contains(tld)
        let isAllASCII = hostname.allSatisfy { $0.isASCII }
        let isAllNonASCII = hostname.allSatisfy { !$0.isASCII || $0 == "." }

        return isValidTLD && (isAllASCII || isAllNonASCII)
    }

    /// - Parameter sourceString: The raw string that this URL was parsed from
    /// The source string will be parsed to ensure that the parsed hostname has only ASCII or non-ASCII characters
    /// to avoid homograph URLs.
    ///
    /// The source string is necessary, since NSURL and NSDataDetector will automatically punycode any returned
    /// URLs. The source string will be used to verify that the originating string's host only contained ASCII or
    /// non-ASCII characters to avoid homographs.
    ///
    /// If no sourceString is provided, the validated host will be whatever is returned from `host`, which will always
    /// be ASCII.
    func isPermittedLinkPreviewUrl(parsedFrom sourceString: String? = nil) -> Bool {
        guard let scheme = scheme?.lowercased(), scheme.count > 0 else { return false }
        guard user == nil else { return false }
        guard password == nil else { return false }
        let rawHostname: String?

        if let sourceString = sourceString {
            let schemePrefix = "\(scheme)://"
            rawHostname = sourceString
                .dropFirst(schemePrefix.count)
                .split(maxSplits: 1, whereSeparator: { Self.urlDelimeters.contains($0) }).first
                .map { String($0) }
        } else {
            // The hostname will be punycode and all ASCII
            rawHostname = host
        }

        guard let hostnameToValidate = rawHostname else { return false }
        return Self.schemeAllowSet.contains(scheme) && Self.isValidHostname(hostnameToValidate)
    }
}

fileprivate extension HTMLMetadata {
    var dateForLinkPreview: Date? {
        [ogPublishDateString, articlePublishDateString, ogModifiedDateString, articleModifiedDateString]
            .first(where: {$0 != nil})?
            .flatMap { Date.ows_parseFromISO8601String($0) }
    }
}

// MARK: - To be moved
// Everything after this line should find a new home at some point

fileprivate extension OWSLinkPreviewManager {
    @objc
    class func displayDomain(forUrl urlString: String?) -> String? {
        guard let urlString = urlString else {
            owsFailDebug("Missing url.")
            return nil
        }
        guard let url = URL(string: urlString) else {
            owsFailDebug("Invalid url.")
            return nil
        }
        if StickerPackInfo.isStickerPackShare(url) {
            return stickerPackShareDomain(forUrl: url)
        }
        if GroupManager.isPossibleGroupInviteLink(url) {
            return "signal.org"
        }
        return url.host
    }

    private class func stickerPackShareDomain(forUrl url: URL) -> String? {
        guard let domain = url.host?.lowercased() else {
            return nil
        }
        guard url.path.count > 1 else {
            // Url must have non-empty path.
            return nil
        }
        return domain
    }
}

private func normalizeString(_ string: String, maxLines: Int) -> String {
    var result = string
    var components = result.components(separatedBy: .newlines)
    if components.count > maxLines {
        components = Array(components[0..<maxLines])
        result =  components.joined(separator: "\n")
    }
    let maxCharacterCount = 2048
    if result.count > maxCharacterCount {
        let endIndex = result.index(result.startIndex, offsetBy: maxCharacterCount)
        result = String(result[..<endIndex])
    }
    return result.filterStringForDisplay()
}
