//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

fileprivate extension IndexSet {
    func shifted(startingAt index: Int? = nil, by amount: Int) -> IndexSet {
        var result = self
        result.shift(startingAt: index ?? self.first ?? 0, by: amount)
        return result
    }
}

@objc
public class MediaTileViewController: UICollectionViewController, MediaGalleryDelegate, UICollectionViewDelegateFlowLayout {
    private var galleryDates: [GalleryDate] { return mediaGallery.sections.orderedKeys }

    private let thread: TSThread
    private lazy var mediaGallery: MediaGallery = {
        let mediaGallery = MediaGallery(thread: thread)
        mediaGallery.addDelegate(self)
        return mediaGallery
    }()
    fileprivate let mediaTileViewLayout: MediaTileViewLayout

    @objc
    public init(thread: TSThread) {
        self.thread = thread
        let layout: MediaTileViewLayout = type(of: self).buildLayout()
        self.mediaTileViewLayout = layout
        super.init(collectionViewLayout: layout)
    }

    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: Subviews

    lazy var footerBar: UIToolbar = {
        let footerBar = UIToolbar()
        let footerItems = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            deleteButton,
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        ]
        footerBar.setItems(footerItems, animated: false)

        return footerBar
    }()

    lazy var deleteButton: UIBarButtonItem = {
        let deleteButton = UIBarButtonItem(barButtonSystemItem: .trash,
                                           target: self,
                                           action: #selector(didPressDelete),
                                           accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "delete_button"))

        return deleteButton
    }()

    // MARK: View Lifecycle Overrides

    override public func viewDidLoad() {
        super.viewDidLoad()

        self.title = MediaStrings.allMedia

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        collectionView.register(PhotoGridViewCell.self, forCellWithReuseIdentifier: PhotoGridViewCell.reuseIdentifier)
        collectionView.register(ThemeCollectionViewSectionHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: ThemeCollectionViewSectionHeader.reuseIdentifier)
        collectionView.register(MediaGalleryStaticHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: MediaGalleryStaticHeader.reuseIdentifier)

        collectionView.delegate = self

        // feels a bit weird to have content smashed all the way to the bottom edge.
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)

        self.view.addSubview(self.footerBar)
        footerBar.autoPinWidthToSuperview()
        footerBar.autoSetDimension(.height, toSize: kFooterBarHeight)
        self.footerBarBottomConstraint = footerBar.autoPinEdge(toSuperviewEdge: .bottom, withInset: -kFooterBarHeight)

        updateSelectButton()

        self.mediaTileViewLayout.invalidateLayout()

        applyTheme()

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .ThemeDidChange, object: nil)
    }

    override public func viewWillAppear(_ animated: Bool) {
        defer { super.viewWillAppear(animated) }

        if mediaGallery.sections.isEmpty {
            databaseStorage.read { transaction in
                _ = self.mediaGallery.loadEarlierSections(batchSize: kLoadBatchSize, transaction: transaction)
            }
            if mediaGallery.sections.isEmpty {
                // There must be no media.
                return
            }
        }

        self.view.layoutIfNeeded()
        let lastSectionItemCount = self.collectionView(self.collectionView!,
                                                       numberOfItemsInSection: self.galleryDates.count)
        self.collectionView.scrollToItem(at: IndexPath(item: lastSectionItemCount - 1,
                                                       section: self.galleryDates.count),
                                         at: .bottom,
                                         animated: false)
    }

    override public func viewWillTransition(to size: CGSize,
                                            with coordinator: UIViewControllerTransitionCoordinator) {
        self.mediaTileViewLayout.invalidateLayout()
        super.viewWillTransition(to: size, with: coordinator)
    }

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        self.updateLayout()
    }

    // MARK: Theme

    @objc func applyTheme() {
        footerBar.barTintColor = Theme.navbarBackgroundColor
        footerBar.tintColor = Theme.primaryIconColor

        deleteButton.tintColor = Theme.primaryIconColor

        collectionView.backgroundColor = Theme.backgroundColor
    }

    // MARK: Orientation

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.defaultSupportedOrienations
    }

    // MARK: UICollectionViewDelegate

    override public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.autoLoadMoreIfNecessary()
    }

    var previousAdjustedContentInset: UIEdgeInsets = UIEdgeInsets()

    override public func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        defer { previousAdjustedContentInset = scrollView.adjustedContentInset }
        guard !galleryDates.isEmpty else {
            return
        }

        if scrollView.contentSize.height > scrollView.bounds.height - scrollView.adjustedContentInset.totalHeight {
            // Were we pinned to the bottom before? If so, scroll back down.
            let dy = scrollView.adjustedContentInset.totalHeight - previousAdjustedContentInset.totalHeight
            if scrollView.contentOffset.y + dy + scrollView.bounds.height >= scrollView.contentSize.height {
                scrollView.contentOffset.y =
                    scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            }
        }
    }

    override public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {

        Logger.debug("")

        guard galleryDates.count > 0 else {
            return false
        }

        switch indexPath.section {
        case kLoadOlderSectionIdx, loadNewerSectionIdx:
            return false
        default:
            return true
        }
    }

    override public func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {

        Logger.debug("")

        guard galleryDates.count > 0 else {
            return false
        }

        switch indexPath.section {
        case kLoadOlderSectionIdx, loadNewerSectionIdx:
            return false
        default:
            return true
        }
    }

    public override func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {

        Logger.debug("")

        guard galleryDates.count > 0 else {
            return false
        }

        switch indexPath.section {
        case kLoadOlderSectionIdx, loadNewerSectionIdx:
            return false
        default:
            return true
        }
    }

    override public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Logger.debug("")

        guard let gridCell = self.collectionView(collectionView, cellForItemAt: indexPath) as? PhotoGridViewCell else {
            owsFailDebug("galleryCell was unexpectedly nil")
            return
        }

        guard let galleryItem = (gridCell.item as? GalleryGridCellItem)?.galleryItem else {
            owsFailDebug("galleryItem was unexpectedly nil")
            return
        }

        if isInBatchSelectMode {
            updateDeleteButton()
        } else {
            collectionView.deselectItem(at: indexPath, animated: true)

            let pageVC = MediaPageViewController(
                initialMediaAttachment: galleryItem.attachmentStream,
                mediaGallery: mediaGallery
            )
            present(pageVC, animated: true)
        }
    }

    public override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        Logger.debug("")

        if isInBatchSelectMode {
            updateDeleteButton()
        }
    }

    // MARK: UICollectionViewDataSource

    override public func numberOfSections(in collectionView: UICollectionView) -> Int {
        Logger.debug("")

        guard galleryDates.count > 0 else {
            // empty gallery
            return 1
        }

        // One for each galleryDate plus a "loading older" and "loading newer" section
        return galleryDates.count + 2
    }

    override public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        Logger.debug("\(sectionIdx)")

        guard galleryDates.count > 0 else {
            // empty gallery
            return 0
        }

        if sectionIdx == kLoadOlderSectionIdx {
            // load older
            return 0
        }

        if sectionIdx == loadNewerSectionIdx {
            // load more recent
            return 0
        }

        guard let count = mediaGallery.sections[safe: sectionIdx - 1]?.value.count else {
            owsFailDebug("unknown section: \(sectionIdx)")
            return 0
        }

        return count
    }

    override public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {

        let defaultView = UICollectionReusableView()

        guard galleryDates.count > 0 else {
            guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MediaGalleryStaticHeader.reuseIdentifier, for: indexPath) as? MediaGalleryStaticHeader else {

                owsFailDebug("unable to build section header for kLoadOlderSectionIdx")
                return defaultView
            }
            let title = NSLocalizedString("GALLERY_TILES_EMPTY_GALLERY", comment: "Label indicating media gallery is empty")
            sectionHeader.configure(title: title)
            return sectionHeader
        }

        if kind == UICollectionView.elementKindSectionHeader {
            switch indexPath.section {
            case kLoadOlderSectionIdx:
                guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MediaGalleryStaticHeader.reuseIdentifier, for: indexPath) as? MediaGalleryStaticHeader else {

                    owsFailDebug("unable to build section header for kLoadOlderSectionIdx")
                    return defaultView
                }
                let title = NSLocalizedString("GALLERY_TILES_LOADING_OLDER_LABEL", comment: "Label indicating loading is in progress")
                sectionHeader.configure(title: title)
                return sectionHeader
            case loadNewerSectionIdx:
                guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MediaGalleryStaticHeader.reuseIdentifier, for: indexPath) as? MediaGalleryStaticHeader else {

                    owsFailDebug("unable to build section header for kLoadOlderSectionIdx")
                    return defaultView
                }
                let title = NSLocalizedString("GALLERY_TILES_LOADING_MORE_RECENT_LABEL", comment: "Label indicating loading is in progress")
                sectionHeader.configure(title: title)
                return sectionHeader
            default:
                guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: ThemeCollectionViewSectionHeader.reuseIdentifier, for: indexPath) as? ThemeCollectionViewSectionHeader else {
                    owsFailDebug("unable to build section header for indexPath: \(indexPath)")
                    return defaultView
                }
                guard let date = self.galleryDates[safe: indexPath.section - 1] else {
                    owsFailDebug("unknown section for indexPath: \(indexPath)")
                    return defaultView
                }

                sectionHeader.configure(title: date.localizedString)
                return sectionHeader
            }
        }

        return defaultView
    }

    override public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        Logger.debug("indexPath: \(indexPath)")

        let defaultCell = UICollectionViewCell()

        guard galleryDates.count > 0 else {
            owsFailDebug("unexpected cell for loadNewerSectionIdx")
            return defaultCell
        }

        switch indexPath.section {
        case kLoadOlderSectionIdx:
            owsFailDebug("unexpected cell for kLoadOlderSectionIdx")
            return defaultCell
        case loadNewerSectionIdx:
            owsFailDebug("unexpected cell for loadNewerSectionIdx")
            return defaultCell
        default:
            guard let galleryItem = galleryItem(at: indexPath) else {
                owsFailDebug("no message for path: \(indexPath)")
                return defaultCell
            }

            guard let cell = self.collectionView?.dequeueReusableCell(withReuseIdentifier: PhotoGridViewCell.reuseIdentifier, for: indexPath) as? PhotoGridViewCell else {
                owsFailDebug("unexpected cell for indexPath: \(indexPath)")
                return defaultCell
            }

            let gridCellItem = GalleryGridCellItem(galleryItem: galleryItem)
            cell.configure(item: gridCellItem)

            return cell
        }
    }

    override public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let photoGridViewCell = cell as? PhotoGridViewCell else {
            owsFailDebug("unexpected cell: \(cell)")
            return
        }

        photoGridViewCell.allowsMultipleSelection = collectionView.allowsMultipleSelection
    }

    func galleryItem(at indexPath: IndexPath) -> MediaGalleryItem? {
        var underlyingPath = indexPath
        underlyingPath.section -= 1
        if let loadedGalleryItem = mediaGallery.galleryItem(at: underlyingPath) {
            return loadedGalleryItem
        }

        // Only load "after" the current item in this function, to avoid shifting section indexes.
        mediaGallery.ensureGalleryItemsLoaded(.after,
                                              sectionIndex: underlyingPath.section,
                                              itemIndex: underlyingPath.item,
                                              amount: kLoadBatchSize,
                                              shouldLoadAlbumRemainder: false) { newSectionIndexes in
            UIView.performWithoutAnimation {
                self.collectionView.insertSections(newSectionIndexes.shifted(by: 1))
            }
        }

        return mediaGallery.galleryItem(at: underlyingPath)
    }

    func updateVisibleCells() {
        for cell in collectionView.visibleCells {
            guard let photoGridViewCell = cell as? PhotoGridViewCell else {
                owsFailDebug("unexpected cell: \(cell)")
                continue
            }

            photoGridViewCell.allowsMultipleSelection = collectionView.allowsMultipleSelection
        }
    }

    // MARK: UICollectionViewDelegateFlowLayout

    static let kInterItemSpacing: CGFloat = 2
    private class func buildLayout() -> MediaTileViewLayout {
        let layout = MediaTileViewLayout()

        layout.sectionInsetReference = .fromSafeArea
        layout.minimumInteritemSpacing = kInterItemSpacing
        layout.minimumLineSpacing = kInterItemSpacing
        layout.sectionHeadersPinToVisibleBounds = true

        return layout
    }

    func updateLayout() {
        let rawSize = view.safeAreaLayoutGuide.layoutFrame.size

        let containerSize = CGSize(width: floor(rawSize.width), height: floor(rawSize.height))

        let kItemsPerPortraitRow = 4
        let minimumViewWidth = min(containerSize.width, containerSize.height)
        let approxItemWidth = minimumViewWidth / CGFloat(kItemsPerPortraitRow)

        let itemCount = round(containerSize.width / approxItemWidth)
        let interSpaceWidth = (itemCount - 1) * type(of: self).kInterItemSpacing
        let availableWidth = max(0, containerSize.width - interSpaceWidth)

        let itemWidth = floor(availableWidth / CGFloat(itemCount))
        let newItemSize = CGSize(square: itemWidth)
        let remainingSpace = availableWidth - (itemCount * itemWidth)
        let hInset = remainingSpace / 2
        if newItemSize != mediaTileViewLayout.itemSize || hInset != mediaTileViewLayout.sectionInset.left {
            mediaTileViewLayout.itemSize = newItemSize
            // Inset any remaining space around the outside edges to ensure all inter-item spacing is exactly equal, otherwise
            // we may get slightly different gaps between rows vs. columns
            mediaTileViewLayout.sectionInset = UIEdgeInsets(top: 0, leading: hInset, bottom: 0, trailing: hInset)
            mediaTileViewLayout.invalidateLayout()
        }
    }

    public func collectionView(_ collectionView: UICollectionView,
                               layout collectionViewLayout: UICollectionViewLayout,
                               referenceSizeForHeaderInSection section: Int) -> CGSize {

        let kMonthHeaderSize: CGSize = CGSize(width: 0, height: 50)
        let kStaticHeaderSize: CGSize = CGSize(width: 0, height: 100)

        guard galleryDates.count > 0 else {
            return kStaticHeaderSize
        }

        switch section {
        case kLoadOlderSectionIdx:
            // Show "loading older..." iff there is still older data to be fetched
            return mediaGallery.hasFetchedOldest ? CGSize.zero : kStaticHeaderSize
        case loadNewerSectionIdx:
            // Show "loading newer..." iff there is still more recent data to be fetched
            return mediaGallery.hasFetchedMostRecent ? CGSize.zero : kStaticHeaderSize
        default:
            return kMonthHeaderSize
        }
    }

    // MARK: Batch Selection

    var isInBatchSelectMode = false {
        didSet {
            let didChange = isInBatchSelectMode != oldValue
            if didChange {
                collectionView!.allowsMultipleSelection = isInBatchSelectMode
                updateVisibleCells()
                updateSelectButton()
                updateDeleteButton()
            }
        }
    }

    func updateDeleteButton() {
        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        if let count = collectionView.indexPathsForSelectedItems?.count, count > 0 {
            self.deleteButton.isEnabled = true
        } else {
            self.deleteButton.isEnabled = false
        }
    }

    func updateSelectButton() {
        if isInBatchSelectMode {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(didCancelSelect),
                                                                     accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "cancel_select_button"))
        } else {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("BUTTON_SELECT", comment: "Button text to enable batch selection mode"),
                                                                     style: .plain,
                                                                     target: self,
                                                                     action: #selector(didTapSelect),
                                                                     accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "select_button"))
        }
    }

    @objc
    func didTapSelect(_ sender: Any) {
        isInBatchSelectMode = true

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        // show toolbar
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut, animations: {
            NSLayoutConstraint.deactivate([self.footerBarBottomConstraint])
            self.footerBarBottomConstraint = self.footerBar.autoPin(toBottomLayoutGuideOf: self, withInset: 0)

            self.footerBar.superview?.layoutIfNeeded()

            // ensure toolbar doesn't cover bottom row.
            collectionView.contentInset.bottom += self.kFooterBarHeight
        }, completion: nil)

        // disabled until at least one item is selected
        self.deleteButton.isEnabled = false

        // Don't allow the user to leave mid-selection, so they realized they have
        // to cancel (lose) their selection if they leave.
        self.navigationItem.hidesBackButton = true
    }

    @objc
    func didCancelSelect(_ sender: Any) {
        endSelectMode()
    }

    func endSelectMode() {
        isInBatchSelectMode = false

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        // hide toolbar
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut, animations: {
            NSLayoutConstraint.deactivate([self.footerBarBottomConstraint])
            self.footerBarBottomConstraint = self.footerBar.autoPinEdge(toSuperviewEdge: .bottom, withInset: -self.kFooterBarHeight)
            self.footerBar.superview?.layoutIfNeeded()

            // undo "ensure toolbar doesn't cover bottom row."
            collectionView.contentInset.bottom -= self.kFooterBarHeight
        }, completion: nil)

        self.navigationItem.hidesBackButton = false

        // deselect any selected
        collectionView.indexPathsForSelectedItems?.forEach { collectionView.deselectItem(at: $0, animated: false)}
    }

    @objc
    func didPressDelete(_ sender: Any) {
        Logger.debug("")

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        guard let indexPaths = collectionView.indexPathsForSelectedItems else {
            owsFailDebug("indexPaths was unexpectedly nil")
            return
        }

        let items: [MediaGalleryItem] = indexPaths.compactMap { return self.galleryItem(at: $0) }
        guard items.count == indexPaths.count else {
            owsFailDebug("trying to delete an item that never loaded")
            return
        }

        let confirmationTitle: String = {
            if indexPaths.count == 1 {
                return NSLocalizedString("MEDIA_GALLERY_DELETE_SINGLE_MESSAGE", comment: "Confirmation button text to delete selected media message from the gallery")
            } else {
                let format = NSLocalizedString("MEDIA_GALLERY_DELETE_MULTIPLE_MESSAGES_FORMAT", comment: "Confirmation button text to delete selected media from the gallery, embeds {{number of messages}}")
                return String(format: format, indexPaths.count)
            }
        }()

        let deleteAction = ActionSheetAction(title: confirmationTitle, style: .destructive) { _ in
            let galleryIndexPaths = indexPaths.map { IndexPath(item: $0.item, section: $0.section - 1) }
            self.mediaGallery.delete(items: items, atIndexPaths: galleryIndexPaths, initiatedBy: self, deleteFromDB: true)
            self.endSelectMode()
        }

        let actionSheet = ActionSheetController(title: nil, message: nil)
        actionSheet.addAction(deleteAction)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    var footerBarBottomConstraint: NSLayoutConstraint!
    let kFooterBarHeight: CGFloat = 40

    // MARK: MediaGalleryDelegate

    func mediaGallery(_ mediaGallery: MediaGallery, willDelete items: [MediaGalleryItem], initiatedBy: AnyObject) {
        Logger.debug("")

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        // We've got to lay out the collectionView before any changes are made to the date source
        // otherwise we'll fail when we try to remove the deleted sections/rows
        collectionView.layoutIfNeeded()
    }

    func mediaGallery(_ mediaGallery: MediaGallery, deletedSections: IndexSet, deletedItems: [IndexPath]) {
        Logger.debug("with deletedSections: \(deletedSections) deletedItems: \(deletedItems)")

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        guard galleryDates.count > 0 else {
            // Show Empty
            self.collectionView?.reloadData()
            return
        }

        collectionView.performBatchUpdates({
            collectionView.deleteSections(deletedSections.shifted(by: 1))
            collectionView.deleteItems(at: deletedItems.map { IndexPath(item: $0.item, section: $0.section + 1) })
        })
    }

    func mediaGallery(_ mediaGallery: MediaGallery, didReloadItemsInSections sections: IndexSet) {
        collectionView.reloadSections(sections.shifted(by: 1))
    }

    // MARK: Lazy Loading

    var isFetchingMoreData: Bool = false
    let kLoadBatchSize: Int = 50

    let kLoadOlderSectionIdx: Int = 0
    var loadNewerSectionIdx: Int {
        return galleryDates.count + 1
    }

    public func autoLoadMoreIfNecessary() {
        let kEdgeThreshold: CGFloat = 800

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        let contentOffsetY = collectionView.contentOffset.y
        let oldContentHeight = collectionView.contentSize.height
        let direction: GalleryDirection

        if contentOffsetY < kEdgeThreshold && !mediaGallery.hasFetchedOldest {
            // Near the top, load older content
            mediaTileViewLayout.recordContentSizeBeforeInsertingToTop()
            direction = .before

        } else if oldContentHeight - contentOffsetY < kEdgeThreshold && !mediaGallery.hasFetchedMostRecent {
            // Near the bottom, load newer content
            direction = .after

        } else {
            return
        }

        guard !isFetchingMoreData else {
            Logger.debug("already fetching more data")
            return
        }
        isFetchingMoreData = true

        UIView.performWithoutAnimation {
            collectionView.performBatchUpdates({
                databaseStorage.read { transaction in
                    let newSections: Range<Int>
                    switch direction {
                    case .before:
                        newSections = 0..<mediaGallery.loadEarlierSections(batchSize: kLoadBatchSize,
                                                                           transaction: transaction)
                    case .after:
                        let newSectionCount = mediaGallery.loadLaterSections(batchSize: kLoadBatchSize,
                                                                             transaction: transaction)
                        newSections = (mediaGallery.sections.count - newSectionCount)..<mediaGallery.sections.count
                    case .around:
                        preconditionFailure() // unused
                    }
                    Logger.debug("found new sections: \(newSections)")
                    collectionView.insertSections(IndexSet(newSections).shifted(by: 1))
                }
            }, completion: { finished in
                Logger.debug("performBatchUpdates finished: \(finished)")
                self.isFetchingMoreData = false
            })
        }
    }
}

extension MediaTileViewController: MediaPresentationContextProvider {
    func mediaPresentationContext(item: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        // First time presentation can occur before layout.
        view.layoutIfNeeded()

        guard case let .gallery(galleryItem) = item else {
            owsFailDebug("Unexpected media type")
            return nil
        }

        guard let underlyingPath = mediaGallery.indexPath(for: galleryItem) else {
            owsFailDebug("galleryItemIndexPath was unexpectedly nil")
            return nil
        }
        var indexPath = underlyingPath
        indexPath.section += 1

        guard let visibleIndex = collectionView.indexPathsForVisibleItems.firstIndex(of: indexPath) else {
            Logger.debug("visibleIndex was nil, swiped to offscreen gallery item")
            return nil
        }

        guard let cell = collectionView.visibleCells[safe: visibleIndex] as? PhotoGridViewCell else {
            owsFailDebug("cell was unexpectedly nil")
            return nil
        }

        let mediaView = cell.imageView

        guard let mediaSuperview = mediaView.superview else {
            owsFailDebug("mediaSuperview was unexpectedly nil")
            return nil
        }

        let presentationFrame = coordinateSpace.convert(mediaView.frame, from: mediaSuperview)

        return MediaPresentationContext(mediaView: mediaView, presentationFrame: presentationFrame, cornerRadius: 0)
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return nil
    }
}

// MARK: - Private Helper Classes

// Accomodates remaining scrolled to the same "apparent" position when new content is inserted
// into the top of a collectionView. There are multiple ways to solve this problem, but this
// is the only one which avoided a perceptible flicker.
private class MediaTileViewLayout: UICollectionViewFlowLayout {
    private var contentSizeBeforeInsertingToTop: CGSize?

    func recordContentSizeBeforeInsertingToTop() {
        contentSizeBeforeInsertingToTop = collectionViewContentSize
    }

    override public func prepare() {
        super.prepare()

        if let collectionView = collectionView, let oldContentSize = contentSizeBeforeInsertingToTop {
            let newContentSize = collectionViewContentSize
            collectionView.contentOffset.y += newContentSize.height - oldContentSize.height
            contentSizeBeforeInsertingToTop = nil
        }
    }
}

private class MediaGalleryStaticHeader: UICollectionViewCell {

    static let reuseIdentifier = "MediaGalleryStaticHeader"

    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textColor = Theme.primaryTextColor
        label.font = UIFont.ows_dynamicTypeBody
        addSubview(label)

        label.textAlignment = .center
        label.numberOfLines = 0
        label.autoPinEdgesToSuperviewMargins()
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public func configure(title: String) {
        label.text = title
    }

    public override func prepareForReuse() {
        label.text = nil
        label.textColor = Theme.primaryTextColor
        label.font = UIFont.ows_dynamicTypeBody
    }
}

class GalleryGridCellItem: PhotoGridItem {
    let galleryItem: MediaGalleryItem

    init(galleryItem: MediaGalleryItem) {
        self.galleryItem = galleryItem
    }

    var type: PhotoGridItemType {
        if galleryItem.isVideo {
            return .video
        } else if galleryItem.isAnimated {
            return .animated
        } else {
            return .photo
        }
    }

    func asyncThumbnail(completion: @escaping (UIImage?) -> Void) -> UIImage? {
        return galleryItem.thumbnailImage(async: completion)
    }
}
