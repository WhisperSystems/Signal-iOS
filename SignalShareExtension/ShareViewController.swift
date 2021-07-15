//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit

import SignalMessaging
import PureLayout
import SignalServiceKit
import PromiseKit
import Intents

@objc
public class ShareViewController: UIViewController, ShareViewDelegate, SAEFailedViewDelegate {

    enum ShareViewControllerError: Error, Equatable {
        case assertionError(description: String)
        case unsupportedMedia
        case notRegistered
        case obsoleteShare
        case tooManyAttachments
    }

    private var hasInitialRootViewController = false
    private var isReadyForAppExtensions = false
    private var areVersionMigrationsComplete = false

    private var progressPoller: ProgressPoller?
    lazy var loadViewController = SAELoadViewController(delegate: self)

    public var shareViewNavigationController: OWSNavigationController?

    override open func loadView() {
        super.loadView()

        // This should be the first thing we do.
        let appContext = ShareAppExtensionContext(rootViewController: self)
        SetCurrentAppContext(appContext)

        DebugLogger.shared().enableTTYLogging()
        if _isDebugAssertConfiguration() {
            DebugLogger.shared().enableFileLogging()
        } else if OWSPreferences.isLoggingEnabled() {
            DebugLogger.shared().enableFileLogging()
        }

        Logger.info("")

        _ = AppVersion.shared()

        Cryptography.seedRandom()

        // We don't need to use DeviceSleepManager in the SAE.

        // We don't need to use applySignalAppearence in the SAE.

        if CurrentAppContext().isRunningTests {
            // TODO: Do we need to implement isRunningTests in the SAE context?
            return
        }

        // We shouldn't set up our environment until after we've consulted isReadyForAppExtensions.
        AppSetup.setupEnvironment(appSpecificSingletonBlock: {
            SSKEnvironment.shared.callMessageHandlerRef = NoopCallMessageHandler()
            SSKEnvironment.shared.notificationsManagerRef = NoopNotificationsManager()
        },
        migrationCompletion: { [weak self] error in
            AssertIsOnMainThread()

            guard let strongSelf = self else { return }

            if let error = error {
                owsFailDebug("Error \(error)")
                strongSelf.showNotReadyView()
                return
            }

            // performUpdateCheck must be invoked after Environment has been initialized because
            // upgrade process may depend on Environment.
            strongSelf.versionMigrationsDidComplete()
        })

        let shareViewNavigationController = OWSNavigationController()
        shareViewNavigationController.presentationController?.delegate = self
        self.shareViewNavigationController = shareViewNavigationController

        // Don't display load screen immediately, in hopes that we can avoid it altogether.
        after(seconds: 0.8).done { [weak self] in
            AssertIsOnMainThread()

            guard let strongSelf = self else { return }
            guard strongSelf.presentedViewController == nil else {
                Logger.debug("setup completed quickly, no need to present load view controller.")
                return
            }

            Logger.debug("setup is slow - showing loading screen")
            strongSelf.showPrimaryViewController(strongSelf.loadViewController)
        }

        // We don't need to use "screen protection" in the SAE.

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(storageIsReady),
                                               name: .StorageIsReady,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .registrationStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(owsApplicationWillEnterForeground),
                                               name: .OWSApplicationWillEnterForeground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidEnterBackground),
                                               name: .OWSApplicationDidEnterBackground,
                                               object: nil)

        Logger.info("completed.")

        OWSAnalytics.appLaunchDidBegin()
    }

    deinit {
        Logger.info("deinit")
        NotificationCenter.default.removeObserver(self)

        // Share extensions reside in a process that may be reused between usages.
        // That isn't safe; the codebase is full of statics (e.g. singletons) which
        // we can't easily clean up.
        ExitShareExtension()
    }

    @objc
    public func applicationDidEnterBackground() {
        AssertIsOnMainThread()

        Logger.info("")

        if OWSScreenLock.shared.isScreenLockEnabled() {

            Logger.info("dismissing.")

            self.dismiss(animated: false) { [weak self] in
                AssertIsOnMainThread()
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }

    private func activate() {
        AssertIsOnMainThread()

        Logger.debug("")

        // We don't need to use "screen protection" in the SAE.

        ensureRootViewController()

        // Always check prekeys after app launches, and sometimes check on app activation.
        TSPreKeyManager.checkPreKeysIfNecessary()

        // We don't need to use RTCInitializeSSL() in the SAE.

        if tsAccountManager.isRegistered {
            Logger.info("running post launch block for registered user: \(String(describing: TSAccountManager.localAddress))")
        } else {
            Logger.info("running post launch block for unregistered user.")

            // We don't need to update the app icon badge number in the SAE.

            // We don't need to prod the TSSocketManager in the SAE.
        }

        if tsAccountManager.isRegistered {
            DispatchQueue.main.async { [weak self] in
                guard let _ = self else { return }
                Logger.info("running post launch block for registered user: \(String(describing: TSAccountManager.localAddress))")

                // We don't need to use the TSSocketManager in the SAE.

                // TODO: Re-enable when system contact fetching uses less memory.
                // Environment.shared.contactsManager.fetchSystemContactsOnceIfAlreadyAuthorized()

                // We don't need to fetch messages in the SAE.

                // We don't need to use OWSSyncPushTokensJob in the SAE.
            }
        }
    }

    @objc
    func versionMigrationsDidComplete() {
        AssertIsOnMainThread()

        Logger.debug("")

        areVersionMigrationsComplete = true

        checkIsAppReady()
    }

    @objc
    func storageIsReady() {
        AssertIsOnMainThread()

        Logger.debug("")

        checkIsAppReady()
    }

    @objc
    func checkIsAppReady() {
        AssertIsOnMainThread()

        // App isn't ready until storage is ready AND all version migrations are complete.
        guard areVersionMigrationsComplete else {
            return
        }
        guard storageCoordinator.isStorageReady else {
            return
        }
        guard !AppReadiness.isAppReady else {
            // Only mark the app as ready once.
            return
        }

        // We don't need to use LaunchJobs in the SAE.

        Logger.debug("")

        // Note that this does much more than set a flag;
        // it will also run all deferred blocks.
        AppReadiness.setAppIsReady()

        if tsAccountManager.isRegistered {
            Logger.info("localAddress: \(String(describing: TSAccountManager.localAddress))")

            // We don't need to use messageFetcherJob in the SAE.

            // We don't need to use SyncPushTokensJob in the SAE.
        }

        // We don't need to use DeviceSleepManager in the SAE.

        AppVersion.shared().saeLaunchDidComplete()

        ensureRootViewController()

        // We don't need to use OWSOrphanDataCleaner in the SAE.

        // We don't need to fetch the local profile in the SAE
    }

    @objc
    func registrationStateDidChange() {
        AssertIsOnMainThread()

        Logger.debug("")

        if tsAccountManager.isRegistered {
            Logger.info("localAddress: \(String(describing: TSAccountManager.localAddress))")

            // We don't need to use ExperienceUpgradeFinder in the SAE.

            // We don't need to use OWSDisappearingMessagesJob in the SAE.
        }
    }

    private func ensureRootViewController() {
        AssertIsOnMainThread()

        Logger.debug("")

        guard AppReadiness.isAppReady else {
            return
        }
        guard !hasInitialRootViewController else {
            return
        }
        hasInitialRootViewController = true

        Logger.info("Presenting initial root view controller")

        if OWSScreenLock.shared.isScreenLockEnabled() {
            presentScreenLock()
        } else {
            presentContentView()
        }
    }

    private func presentContentView() {
        AssertIsOnMainThread()

        Logger.debug("")

        Logger.info("Presenting content view")

        guard tsAccountManager.isRegistered else {
            showNotRegisteredView()
            return
        }

        let localProfileExists = databaseStorage.read { transaction in
            return self.profileManager.localProfileExists(with: transaction)
        }
        guard localProfileExists else {
            // This is a rare edge case, but we want to ensure that the user
            // has already saved their local profile key in the main app.
            showNotReadyView()
            return
        }

        guard tsAccountManager.isOnboarded() else {
            showNotReadyView()
            return
        }

        buildAttachmentsAndPresentConversationPicker()
        // We don't use the AppUpdateNag in the SAE.
    }

    // MARK: Error Views

    private func showNotReadyView() {
        AssertIsOnMainThread()

        let failureTitle = NSLocalizedString("SHARE_EXTENSION_NOT_YET_MIGRATED_TITLE",
                                             comment: "Title indicating that the share extension cannot be used until the main app has been launched at least once.")
        let failureMessage = NSLocalizedString("SHARE_EXTENSION_NOT_YET_MIGRATED_MESSAGE",
                                               comment: "Message indicating that the share extension cannot be used until the main app has been launched at least once.")
        showErrorView(title: failureTitle, message: failureMessage)
    }

    private func showNotRegisteredView() {
        AssertIsOnMainThread()

        let failureTitle = NSLocalizedString("SHARE_EXTENSION_NOT_REGISTERED_TITLE",
                                             comment: "Title indicating that the share extension cannot be used until the user has registered in the main app.")
        let failureMessage = NSLocalizedString("SHARE_EXTENSION_NOT_REGISTERED_MESSAGE",
                                               comment: "Message indicating that the share extension cannot be used until the user has registered in the main app.")
        showErrorView(title: failureTitle, message: failureMessage)
    }

    private func showErrorView(title: String, message: String) {
        AssertIsOnMainThread()

        let viewController = SAEFailedViewController(delegate: self, title: title, message: message)

        let navigationController = UINavigationController()
        navigationController.presentationController?.delegate = self
        navigationController.setViewControllers([viewController], animated: false)
        if self.presentedViewController == nil {
            Logger.debug("presenting modally: \(viewController)")
            self.present(navigationController, animated: true)
        } else {
            owsFailDebug("modal already presented. swapping modal content for: \(viewController)")
            assert(self.presentedViewController == navigationController)
        }
    }

    // MARK: View Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()

        Logger.debug("")

        if isReadyForAppExtensions {
            AppReadiness.runNowOrWhenAppDidBecomeReadySync { [weak self] in
                AssertIsOnMainThread()
                self?.activate()
            }
        }
    }

    override open func viewWillAppear(_ animated: Bool) {
        Logger.debug("")

        super.viewWillAppear(animated)
    }

    override open func viewDidAppear(_ animated: Bool) {
        Logger.debug("")

        super.viewDidAppear(animated)
    }

    override open func viewWillDisappear(_ animated: Bool) {
        Logger.debug("")

        super.viewWillDisappear(animated)

        Logger.flush()

        // Share extensions reside in a process that may be reused between usages.
        // That isn't safe; the codebase is full of statics (e.g. singletons) which
        // we can't easily clean up.
        //
        // We do this here, because since iOS 13 `viewDidDisappear` is never called.
        DispatchQueue.main.async { ExitShareExtension() }
    }

    @objc
    func owsApplicationWillEnterForeground() throws {
        AssertIsOnMainThread()

        Logger.debug("")

        // If a user unregisters in the main app, the SAE should shut down
        // immediately.
        guard !tsAccountManager.isRegistered else {
            // If user is registered, do nothing.
            return
        }
        guard let shareViewNavigationController = shareViewNavigationController else {
            owsFailDebug("Missing shareViewNavigationController")
            return
        }
        guard let firstViewController = shareViewNavigationController.viewControllers.first else {
            // If no view has been presented yet, do nothing.
            return
        }
        if let _ = firstViewController as? SAEFailedViewController {
            // If root view is an error view, do nothing.
            return
        }
        throw ShareViewControllerError.notRegistered
    }

    // MARK: ShareViewDelegate, SAEFailedViewDelegate

    public func shareViewWasUnlocked() {
        Logger.info("")

        presentContentView()
    }

    public func shareViewWasCompleted() {
        Logger.info("")

        self.dismiss(animated: true) { [weak self] in
            AssertIsOnMainThread()
            guard let strongSelf = self else { return }
            strongSelf.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    public func shareViewWasCancelled() {
        Logger.info("")

        self.dismiss(animated: true) { [weak self] in
            AssertIsOnMainThread()
            guard let strongSelf = self else { return }
            strongSelf.extensionContext?.cancelRequest(withError: ShareViewControllerError.obsoleteShare)
        }
    }

    public func shareViewFailed(error: Error) {
        owsFailDebug("Error: \(error)")

        self.dismiss(animated: true) { [weak self] in
            AssertIsOnMainThread()
            guard let strongSelf = self else { return }
            strongSelf.extensionContext?.cancelRequest(withError: error)
        }
    }

    // MARK: Helpers

    // This view controller is not visible to the user. It exists to intercept touches, set up the
    // extensions dependencies, and eventually present a visible view to the user.
    // For speed of presentation, we only present a single modal, and if it's already been presented
    // we swap out the contents.
    // e.g. if loading is taking a while, the user will see the load screen presented with a modal
    // animation. Next, when loading completes, the load view will be switched out for the contact
    // picker view.
    private func showPrimaryViewController(_ viewController: UIViewController) {
        AssertIsOnMainThread()

        guard let shareViewNavigationController = shareViewNavigationController else {
            owsFailDebug("Missing shareViewNavigationController")
            return
        }
        shareViewNavigationController.setViewControllers([viewController], animated: true)
        if self.presentedViewController == nil {
            Logger.debug("presenting modally: \(viewController)")
            self.present(shareViewNavigationController, animated: true)
        } else {
            Logger.debug("modal already presented. swapping modal content for: \(viewController)")
            assert(self.presentedViewController == shareViewNavigationController)
        }
    }

    private lazy var conversationPicker = SharingThreadPickerViewController(shareViewDelegate: self)
    private func buildAttachmentsAndPresentConversationPicker() {
        let selectedThread: TSThread?
        if #available(iOS 13, *),
           let intent = extensionContext?.intent as? INSendMessageIntent,
           let threadUniqueId = intent.conversationIdentifier {
            selectedThread = databaseStorage.read { TSThread.anyFetch(uniqueId: threadUniqueId, transaction: $0) }
        } else {
            selectedThread = nil
        }

        // If we have a pre-selected thread, we wait to show the approval view
        // until the attachments have been built. Otherwise, we'll present it
        // immeidately and tell it what attachments we're sharing once we've
        // finished building them.
        if selectedThread == nil { showPrimaryViewController(conversationPicker) }

        firstly(on: .sharedUserInitiated) { () -> Promise<[UnloadedItem]> in
            guard let inputItems = self.extensionContext?.inputItems as? [NSExtensionItem] else {
                throw OWSAssertionError("no input item")
            }
            let result = try self.itemsToLoad(inputItems: inputItems)
            return Promise.value(result)
        }.then(on: .sharedUserInitiated) { [weak self] (unloadedItems: [UnloadedItem]) -> Promise<[LoadedItem]> in
            guard let self = self else { throw PMKError.cancelled }

            return self.loadItems(unloadedItems: unloadedItems)
        }.then(on: .sharedUserInitiated) { [weak self] (loadedItems: [LoadedItem]) -> Promise<[SignalAttachment]> in
            guard let self = self else { throw PMKError.cancelled }

            return self.buildAttachments(loadedItems: loadedItems)
        }.done { [weak self] (attachments: [SignalAttachment]) in
            guard let self = self else { throw PMKError.cancelled }

            // Make sure the user is not trying to share more than our attachment limit.
            guard attachments.filter({ !$0.isConvertibleToTextMessage }).count <= SignalAttachment.maxAttachmentsAllowed else {
                throw ShareViewControllerError.tooManyAttachments
            }

            self.progressPoller = nil

            Logger.info("Setting picker attachments: \(attachments)")
            self.conversationPicker.attachments = attachments

            if let selectedThread = selectedThread {
                let approvalVC = try self.conversationPicker.buildApprovalViewController(for: selectedThread)
                self.showPrimaryViewController(approvalVC)
            }
        }.catch { [weak self] error in
            guard let self = self else { return }

            let alertTitle: String
            let alertMessage: String?

            if let error = error as? ShareViewControllerError, error == .tooManyAttachments {
                let format = NSLocalizedString("IMAGE_PICKER_CAN_SELECT_NO_MORE_TOAST_FORMAT",
                                               comment: "Momentarily shown to the user when attempting to select more images than is allowed. Embeds {{max number of items}} that can be shared.")

                alertTitle = String(format: format, OWSFormat.formatInt(SignalAttachment.maxAttachmentsAllowed))
                alertMessage = nil
            } else {
                alertTitle = NSLocalizedString("SHARE_EXTENSION_UNABLE_TO_BUILD_ATTACHMENT_ALERT_TITLE",
                                               comment: "Shown when trying to share content to a Signal user for the share extension. Followed by failure details.")
                alertMessage = error.localizedDescription
            }

            OWSActionSheets.showActionSheet(
                title: alertTitle,
                message: alertMessage,
                buttonTitle: CommonStrings.cancelButton
            ) { _ in
                self.shareViewWasCancelled()
            }
            owsFailDebug("building attachment failed with error: \(error)")
        }
    }

    private func presentScreenLock() {
        AssertIsOnMainThread()

        let screenLockUI = SAEScreenLockViewController(shareViewDelegate: self)
        Logger.debug("presentScreenLock: \(screenLockUI)")
        showPrimaryViewController(screenLockUI)
        Logger.info("showing screen lock")
    }

    private class func itemMatchesSpecificUtiType(itemProvider: NSItemProvider, utiType: String) -> Bool {
        // URLs, contacts and other special items have to be detected separately.
        // Many shares (e.g. pdfs) will register many UTI types and/or conform to kUTTypeData.
        guard itemProvider.registeredTypeIdentifiers.count == 1 else {
            return false
        }
        guard let firstUtiType = itemProvider.registeredTypeIdentifiers.first else {
            return false
        }
        return firstUtiType == utiType
    }

    private class func isVisualMediaItem(itemProvider: NSItemProvider) -> Bool {
        return (itemProvider.hasItemConformingToTypeIdentifier(kUTTypeImage as String) ||
            itemProvider.hasItemConformingToTypeIdentifier(kUTTypeMovie as String))
    }

    private class func isUrlItem(itemProvider: NSItemProvider) -> Bool {
        return itemMatchesSpecificUtiType(itemProvider: itemProvider,
                                          utiType: kUTTypeURL as String)
    }

    private class func isContactItem(itemProvider: NSItemProvider) -> Bool {
        return itemMatchesSpecificUtiType(itemProvider: itemProvider,
                                          utiType: kUTTypeContact as String)
    }

    private func itemsToLoad(inputItems: [NSExtensionItem]) throws -> [UnloadedItem] {
        for inputItem in inputItems {
            guard let itemProviders = inputItem.attachments else {
                throw OWSAssertionError("attachments was empty")
            }

            let itemsToLoad: [UnloadedItem] = itemProviders.map { itemProvider in
                if itemProvider.hasItemConformingToTypeIdentifier(kUTTypeMovie as String) {
                    return UnloadedItem(itemProvider: itemProvider, itemType: .movie)
                }

                if itemProvider.hasItemConformingToTypeIdentifier(kUTTypeImage as String) {
                    return UnloadedItem(itemProvider: itemProvider, itemType: .image)
                }

                // A single inputItem can have multiple attachments, e.g. sharing from Firefox gives
                // one url attachment and another text attachment, where the the url would be https://some-news.com/articles/123-cat-stuck-in-tree
                // and the text attachment would be something like "Breaking news - cat stuck in tree"
                //
                // FIXME: For now, we prefer the URL provider and discard the text provider, since it's more useful to share the URL than the caption
                // but we *should* include both. This will be a bigger change though since our share extension is currently heavily predicated
                // on one itemProvider per share.
                if ShareViewController.isUrlItem(itemProvider: itemProvider) {
                    return UnloadedItem(itemProvider: itemProvider, itemType: .webUrl)
                }

                if itemProvider.hasItemConformingToTypeIdentifier(kUTTypeFileURL as String) {
                    return UnloadedItem(itemProvider: itemProvider, itemType: .fileUrl)
                }

                if itemProvider.hasItemConformingToTypeIdentifier(kUTTypeVCard as String) {
                    return UnloadedItem(itemProvider: itemProvider, itemType: .contact)
                }

                if itemProvider.hasItemConformingToTypeIdentifier(kUTTypeText as String) {
                    return UnloadedItem(itemProvider: itemProvider, itemType: .text)
                }

                if itemProvider.hasItemConformingToTypeIdentifier(kUTTypePDF as String) {
                    return UnloadedItem(itemProvider: itemProvider, itemType: .pdf)
                }

                if itemProvider.hasItemConformingToTypeIdentifier("com.apple.pkpass") {
                    return UnloadedItem(itemProvider: itemProvider, itemType: .pkPass)
                }

                owsFailDebug("unexpected share item: \(itemProvider)")
                return UnloadedItem(itemProvider: itemProvider, itemType: .other)
            }

            // Prefer a URL if available. If there's an image item and a URL item,
            // the URL is generally more useful. e.g. when sharing an app from the
            // App Store the image would be the app icon and the URL is the link
            // to the application.
            if let urlItem = itemsToLoad.first(where: { $0.itemType == .webUrl }) {
                return [urlItem]
            }

            let visualMediaItems = itemsToLoad.filter { ShareViewController.isVisualMediaItem(itemProvider: $0.itemProvider) }

            // We only allow sharing 1 item, unless they are visual media items. And if they are
            // visualMediaItems we share *only* the visual media items - a mix of visual and non
            // visual items is not supported.
            if visualMediaItems.count > 0 {
                return visualMediaItems
            } else if itemsToLoad.count > 0 {
                return Array(itemsToLoad.prefix(1))
            }
        }
        throw OWSAssertionError("no input item")
    }

    private
    struct LoadedItem {
        enum LoadedItemPayload {
            case fileUrl(_ fileUrl: URL)
            case inMemoryImage(_ image: UIImage)
            case webUrl(_ webUrl: URL)
            case contact(_ contactData: Data)
            case text(_ text: String)
            case pdf(_ data: Data)
            case pkPass(_ data: Data)

            var debugDescription: String {
                switch self {
                case .fileUrl:
                    return "fileUrl"
                case .inMemoryImage:
                    return "inMemoryImage"
                case .webUrl:
                    return "webUrl"
                case .contact:
                    return "contact"
                case .text:
                    return "text"
                case .pdf:
                    return "pdf"
                case .pkPass:
                    return "pkPass"
                @unknown default:
                    owsFailDebug("Unknown value.")
                    return "unknown"
                }
            }
        }

        let itemProvider: NSItemProvider
        let payload: LoadedItemPayload

        var customFileName: String? {
            isContactShare ? "Contact.vcf" : nil
        }

        private var isContactShare: Bool {
            if case .contact = payload {
                return true
            } else {
                return false
            }
        }

        var debugDescription: String {
            payload.debugDescription
        }
    }

    private
    struct UnloadedItem {
        enum ItemType {
            case movie
            case image
            case webUrl
            case fileUrl
            case contact
            case text
            case pdf
            case pkPass
            case other
        }

        let itemProvider: NSItemProvider
        let itemType: ItemType
    }

    private func loadItems(unloadedItems: [UnloadedItem]) -> Promise<[LoadedItem]> {
        let loadPromises: [Promise<LoadedItem>] = unloadedItems.map { unloadedItem in
            loadItem(unloadedItem: unloadedItem)
        }

        return when(fulfilled: loadPromises)
    }

    private func loadItem(unloadedItem: UnloadedItem) -> Promise<LoadedItem> {
        Logger.info("unloadedItem: \(unloadedItem)")

        let itemProvider = unloadedItem.itemProvider

        switch unloadedItem.itemType {
        case .movie:
            return itemProvider.loadUrl(forTypeIdentifier: kUTTypeMovie as String, options: nil).map { fileUrl in
                LoadedItem(itemProvider: unloadedItem.itemProvider,
                           payload: .fileUrl(fileUrl))

            }
        case .image:
            // When multiple image formats are available, kUTTypeImage will
            // defer to jpeg when possible. On iPhone 12 Pro, when 'heic'
            // and 'jpeg' are the available options, the 'jpeg' data breaks
            // UIImage (and underlying) in some unclear way such that trying
            // to perform any kind of transformation on the image (such as
            // resizing) causes memory to balloon uncontrolled. Luckily,
            // iOS 14 provides native UIImage support for heic and iPhone
            // 12s can only be running iOS 14+, so we can request the heic
            // format directly, which behaves correctly for all our needs.
            // A radar has been opened with apple reporting this issue.
            let desiredTypeIdentifier: String
            if #available(iOS 14, *), itemProvider.registeredTypeIdentifiers.contains("public.heic") {
                desiredTypeIdentifier = "public.heic"
            } else {
                desiredTypeIdentifier = kUTTypeImage as String
            }

            return itemProvider.loadUrl(forTypeIdentifier: desiredTypeIdentifier, options: nil).map { fileUrl in
                LoadedItem(itemProvider: unloadedItem.itemProvider,
                           payload: .fileUrl(fileUrl))
            }.recover(on: .global()) { error -> Promise<LoadedItem> in
                let nsError = error as NSError
                assert(nsError.domain == NSItemProvider.errorDomain)
                assert(nsError.code == NSItemProvider.ErrorCode.unexpectedValueClassError.rawValue)

                // If a URL wasn't available, fall back to an in-memory image.
                // One place this happens is when sharing from the screenshot app on iOS13.
                return itemProvider.loadImage(forTypeIdentifier: kUTTypeImage as String, options: nil).map { image in
                    LoadedItem(itemProvider: unloadedItem.itemProvider,
                               payload: .inMemoryImage(image))
                }
            }
        case .webUrl:
            return itemProvider.loadUrl(forTypeIdentifier: kUTTypeURL as String, options: nil).map { url in
                LoadedItem(itemProvider: unloadedItem.itemProvider,
                           payload: .webUrl(url))
            }
        case .fileUrl:
            return itemProvider.loadUrl(forTypeIdentifier: kUTTypeFileURL as String, options: nil).map { fileUrl in
                LoadedItem(itemProvider: unloadedItem.itemProvider,
                           payload: .fileUrl(fileUrl))
            }
        case .contact:
            return itemProvider.loadData(forTypeIdentifier: kUTTypeContact as String, options: nil).map { contactData in
                LoadedItem(itemProvider: unloadedItem.itemProvider,
                           payload: .contact(contactData))
            }
        case .text:
            return itemProvider.loadText(forTypeIdentifier: kUTTypeText as String, options: nil).map { text in
                LoadedItem(itemProvider: unloadedItem.itemProvider,
                           payload: .text(text))
            }
        case .pdf:
            return itemProvider.loadData(forTypeIdentifier: kUTTypePDF as String, options: nil).map { data in
                LoadedItem(itemProvider: unloadedItem.itemProvider,
                           payload: .pdf(data))
            }
        case .pkPass:
            return itemProvider.loadData(forTypeIdentifier: "com.apple.pkpass", options: nil).map { data in
                LoadedItem(itemProvider: unloadedItem.itemProvider,
                           payload: .pkPass(data))
            }
        case .other:
            return itemProvider.loadUrl(forTypeIdentifier: kUTTypeFileURL as String, options: nil).map { fileUrl in
                LoadedItem(itemProvider: unloadedItem.itemProvider,
                           payload: .fileUrl(fileUrl))
            }
        }
    }

    private func buildAttachments(loadedItems: [LoadedItem]) -> Promise<[SignalAttachment]> {
        var attachmentPromises = [Promise<SignalAttachment>]()
        for loadedItem in loadedItems {
            attachmentPromises.append(firstly(on: .sharedUserInitiated) { () -> Promise<SignalAttachment> in
                self.buildAttachment(loadedItem: loadedItem)
            })
        }
        return when(fulfilled: attachmentPromises)
    }

    private func buildAttachment(loadedItem: LoadedItem) -> Promise<SignalAttachment> {
        let itemProvider = loadedItem.itemProvider
        switch loadedItem.payload {
        case .webUrl(let webUrl):
            let dataSource = DataSourceValue.dataSource(withOversizeText: webUrl.absoluteString)
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypeText as String)
            attachment.isConvertibleToTextMessage = true
            return Promise.value(attachment)
        case .contact(let contactData):
            let dataSource = DataSourceValue.dataSource(with: contactData, utiType: kUTTypeContact as String)
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypeContact as String)
            attachment.isConvertibleToContactShare = true
            return Promise.value(attachment)
        case .text(let text):
            let dataSource = DataSourceValue.dataSource(withOversizeText: text)
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypeText as String)
            attachment.isConvertibleToTextMessage = true
            return Promise.value(attachment)
        case .fileUrl(let itemUrl):
            var url = itemUrl
            do {
                if isVideoNeedingRelocation(itemProvider: itemProvider, itemUrl: itemUrl) {
                    url = try SignalAttachment.copyToVideoTempDir(url: itemUrl)
                }
            } catch {
                let error = ShareViewControllerError.assertionError(description: "Could not copy video")
                return Promise(error: error)
            }

            guard let dataSource = try? DataSourcePath.dataSource(with: url, shouldDeleteOnDeallocation: false) else {
                let error = ShareViewControllerError.assertionError(description: "Unable to read attachment data")
                return Promise(error: error)
            }
            dataSource.sourceFilename = url.lastPathComponent
            let utiType = MIMETypeUtil.utiType(forFileExtension: url.pathExtension) ?? kUTTypeData as String

            guard !SignalAttachment.isVideoThatNeedsCompression(dataSource: dataSource, dataUTI: utiType) else {
                // This can happen, e.g. when sharing a quicktime-video from iCloud drive.

                let (promise, exportSession) = SignalAttachment.compressVideoAsMp4(dataSource: dataSource, dataUTI: utiType)

                // TODO: How can we move waiting for this export to the end of the share flow rather than having to do it up front?
                // Ideally we'd be able to start it here, and not block the UI on conversion unless there's still work to be done
                // when the user hits "send".
                if let exportSession = exportSession {
                    DispatchQueue.main.async {
                        let progressPoller = ProgressPoller(timeInterval: 0.1, ratioCompleteBlock: { return exportSession.progress })

                        self.progressPoller = progressPoller
                        progressPoller.startPolling()

                        self.loadViewController.progress = progressPoller.progress
                    }
                }

                return promise
            }

            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: utiType, imageQuality: .medium)
            return Promise.value(attachment)
        case .inMemoryImage(let image):
            guard let pngData = image.pngData() else {
                return Promise(error: OWSAssertionError("pngData was unexpectedly nil"))
            }
            let dataSource = DataSourceValue.dataSource(with: pngData, fileExtension: "png")
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypePNG as String, imageQuality: .medium)
            return Promise.value(attachment)
        case .pdf(let pdf):
            let dataSource = DataSourceValue.dataSource(with: pdf, fileExtension: "pdf")
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: kUTTypePDF as String)
            return Promise.value(attachment)
        case .pkPass(let pkPass):
            let dataSource = DataSourceValue.dataSource(with: pkPass, fileExtension: "pkpass")
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: "com.apple.pkpass")
            return Promise.value(attachment)
        }
    }

    // Some host apps (e.g. iOS Photos.app) sometimes auto-converts some video formats (e.g. com.apple.quicktime-movie)
    // into mp4s as part of the NSItemProvider `loadItem` API. (Some files the Photo's app doesn't auto-convert)
    //
    // However, when using this url to the converted item, AVFoundation operations such as generating a
    // preview image and playing the url in the AVMoviePlayer fails with an unhelpful error: "The operation could not be completed"
    //
    // We can work around this by first copying the media into our container.
    //
    // I don't understand why this is, and I haven't found any relevant documentation in the NSItemProvider
    // or AVFoundation docs.
    //
    // Notes:
    //
    // These operations succeed when sending a video which initially existed on disk as an mp4.
    // (e.g. Alice sends a video to Bob through the main app, which ensures it's an mp4. Bob saves it, then re-shares it)
    //
    // I *did* verify that the size and SHA256 sum of the original url matches that of the copied url. So there
    // is no difference between the contents of the file, yet one works one doesn't.
    // Perhaps the AVFoundation APIs require some extra file system permssion we don't have in the
    // passed through URL.
    private func isVideoNeedingRelocation(itemProvider: NSItemProvider, itemUrl: URL) -> Bool {
        let pathExtension = itemUrl.pathExtension
        guard pathExtension.count > 0 else {
            Logger.verbose("item URL has no file extension: \(itemUrl).")
            return false
        }
        guard let utiTypeForURL = MIMETypeUtil.utiType(forFileExtension: pathExtension) else {
            Logger.verbose("item has unknown UTI type: \(itemUrl).")
            return false
        }
        Logger.verbose("utiTypeForURL: \(utiTypeForURL)")
        guard utiTypeForURL == kUTTypeMPEG4 as String else {
            // Either it's not a video or it was a video which was not auto-converted to mp4.
            // Not affected by the issue.
            return false
        }

        // If video file already existed on disk as an mp4, then the host app didn't need to
        // apply any conversion, so no need to relocate the file.
        return !itemProvider.registeredTypeIdentifiers.contains(kUTTypeMPEG4 as String)
    }
}

extension ShareViewController: UIAdaptivePresentationControllerDelegate {
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        shareViewWasCancelled()
    }
}

// Exposes a Progress object, whose progress is updated by polling the return of a given block
private class ProgressPoller: NSObject {

    let progress: Progress
    private(set) var timer: Timer?

    // Higher number offers higher ganularity
    let progressTotalUnitCount: Int64 = 10000
    private let timeInterval: Double
    private let ratioCompleteBlock: () -> Float

    init(timeInterval: TimeInterval, ratioCompleteBlock: @escaping () -> Float) {
        self.timeInterval = timeInterval
        self.ratioCompleteBlock = ratioCompleteBlock

        self.progress = Progress()

        progress.totalUnitCount = progressTotalUnitCount
        progress.completedUnitCount = Int64(ratioCompleteBlock() * Float(progressTotalUnitCount))
    }

    func startPolling() {
        guard self.timer == nil else {
            owsFailDebug("already started timer")
            return
        }

        self.timer = WeakTimer.scheduledTimer(timeInterval: timeInterval, target: self, userInfo: nil, repeats: true) { [weak self] (timer) in
            guard let strongSelf = self else {
                return
            }

            let completedUnitCount = Int64(strongSelf.ratioCompleteBlock() * Float(strongSelf.progressTotalUnitCount))
            strongSelf.progress.completedUnitCount = completedUnitCount

            if completedUnitCount == strongSelf.progressTotalUnitCount {
                Logger.debug("progress complete")
                timer.invalidate()
            }
        }
    }
}
