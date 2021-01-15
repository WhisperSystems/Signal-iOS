//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewController.h"
#import "AppDelegate.h"
#import "BlockListUIUtils.h"
#import "BlockListViewController.h"
#import "ContactsViewHelper.h"
#import "ConversationCollectionView.h"
#import "ConversationInputToolbar.h"
#import "ConversationScrollButton.h"
#import "DateUtil.h"
#import "DebugUITableViewController.h"
#import "FingerprintViewController.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSMath.h"
#import "Signal-Swift.h"
#import "TSAttachmentPointer.h"
#import "TSCall.h"
#import "TSContactThread.h"
#import "TSErrorMessage.h"
#import "TSGroupThread.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSInvalidIdentityKeyErrorMessage.h"
#import "UIFont+OWS.h"
#import "UIViewController+Permissions.h"
#import "ViewControllerUtils.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <ContactsUI/CNContactViewController.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <Photos/Photos.h>
#import <PromiseKit/AnyPromise.h>
#import <QuickLook/QuickLook.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalCoreKit/Threading.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSNavigationController.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/ThreadUtil.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalMessaging/UIViewController+OWS.h>
#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/MimeTypeUtil.h>
#import <SignalServiceKit/NSTimer+OWS.h>
#import <SignalServiceKit/OWSAddToContactsOfferMessage.h>
#import <SignalServiceKit/OWSAddToProfileWhitelistOfferMessage.h>
#import <SignalServiceKit/OWSAttachmentDownloads.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSFormat.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSMessageUtils.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/TSOutgoingDeleteMessage.h>
#import <SignalServiceKit/TSQuotedMessage.h>

@import SafariServices;

NS_ASSUME_NONNULL_BEGIN

static const CGFloat kToastInset = 10;

typedef enum : NSUInteger {
    kMediaTypePicture,
    kMediaTypeVideo,
} kMediaTypes;

#pragma mark -

// TODO: Audit protocol conformance, here and in header.
@interface ConversationViewController () <AttachmentApprovalViewControllerDelegate,
    ContactShareApprovalViewControllerDelegate,
    AVAudioPlayerDelegate,
    CNContactViewControllerDelegate,
    ContactsPickerDelegate,
    ContactShareViewHelperDelegate,
    ConversationSettingsViewDelegate,
    ConversationHeaderViewDelegate,
    ConversationInputTextViewDelegate,
    ConversationSearchControllerDelegate,
    ContactsViewHelperObserver,
    UIDocumentMenuDelegate,
    UIDocumentPickerDelegate,
    SendMediaNavDelegate,
    UINavigationControllerDelegate,
    UITextViewDelegate,
    ConversationCollectionViewDelegate,
    ConversationInputToolbarDelegate,
    LocationPickerDelegate,
    InputAccessoryViewPlaceholderDelegate>

@property (nonatomic, readonly) OWSAudioActivity *recordVoiceNoteAudioActivity;

@property (nonatomic, readonly) ConversationCollectionView *collectionView;
@property (nonatomic, readonly) ConversationViewLayout *layout;

@property (nonatomic, readonly) CVViewState *viewState;

@property (nonatomic, nullable) AVAudioRecorder *audioRecorder;
@property (nonatomic, nullable) NSUUID *voiceMessageUUID;

@property (nonatomic, nullable) NSTimer *readTimer;
@property (nonatomic) BOOL isMarkingAsRead;
@property (nonatomic) ConversationHeaderView *headerView;

@property (nonatomic) ConversationViewAction actionOnOpen;

@property (nonatomic) BOOL userHasScrolled;
@property (nonatomic, nullable) NSDate *lastMessageSentDate;

@property (nonatomic) uint64_t lastSortIdMarkedRead;

@property (nonatomic) BOOL isWaitingForDeceleration;

@property (nonatomic) ConversationScrollButton *scrollDownButton;
@property (nonatomic) BOOL isHidingScrollDownButton;
@property (nonatomic) ConversationScrollButton *scrollToNextMentionButton;
@property (nonatomic) BOOL isHidingScrollToNextMentionButton;

@property (nonatomic) NSUInteger unreadMessageCount;
@property (nonatomic, nullable) NSArray<TSMessage *> *unreadMentionMessages;
@property (nonatomic, nullable) NSNumber *viewHorizonTimestamp;
@property (nonatomic) ContactShareViewHelper *contactShareViewHelper;
@property (nonatomic) NSTimer *reloadTimer;

@property (nonatomic, nullable) NSTimer *scrollUpdateTimer;

@property (nonatomic, readonly) ConversationSearchController *searchController;

@property (nonatomic, nullable, weak) ReactionsDetailSheet *reactionsDetailSheet;
@property (nonatomic) MessageActionsToolbar *selectionToolbar;
@property (nonatomic, readonly) SelectionHighlightView *selectionHighlightView;

@property (nonatomic) DebouncedEvent *otherUsersProfileDidChangeEvent;

@property (nonatomic, nullable) GroupCallTooltip *groupCallTooltip;
@property (nonatomic, nullable) UIView *groupCallTooltipTailReferenceView;
@property (nonatomic, nullable) UIBarButtonItem *groupCallBarButtonItem;
@property (nonatomic) BOOL hasIncrementedGroupCallTooltipShownCount;

@end

#pragma mark -

@implementation ConversationViewController

- (instancetype)initWithThreadViewModel:(ThreadViewModel *)threadViewModel
                                 action:(ConversationViewAction)action
                         focusMessageId:(nullable NSString *)focusMessageId
{
    self = [super init];

    OWSLogVerbose(@"");

    ConversationStyle *conversationStyle = [[ConversationStyle alloc] initWithType:ConversationStyleTypeInitial
                                                                            thread:threadViewModel.threadRecord
                                                                         viewWidth:0];
    _viewState = [[CVViewState alloc] initWithThreadViewModel:threadViewModel conversationStyle:conversationStyle];
    self.viewState.delegate = self;

#ifdef TESTABLE_BUILD
    [self.initialLoadBenchSteps step:@"Init CVC"];
#endif

    self.inputAccessoryPlaceholder.delegate = self;

    // If we're not scrolling to a specific message AND we don't have
    // any unread messages, try to focus on the last visible interaction.
    if (focusMessageId == nil && !threadViewModel.hasUnreadMessages) {
        focusMessageId = [self lastVisibleInteractionIdWithSneakyTransaction:threadViewModel];
    }

    [self.contactsViewHelper addObserver:self];
    _contactShareViewHelper = [ContactShareViewHelper new];
    _contactShareViewHelper.delegate = self;

    NSString *audioActivityDescription = [NSString stringWithFormat:@"%@ voice note", self.logTag];
    _recordVoiceNoteAudioActivity = [[OWSAudioActivity alloc] initWithAudioDescription:audioActivityDescription behavior:OWSAudioBehavior_PlayAndRecord];

    self.actionOnOpen = action;

    [self recordInitialScrollState:focusMessageId];

    _loadCoordinator = [self buildLoadCoordinatorWithConversationStyle:conversationStyle
                                                  focusMessageIdOnOpen:focusMessageId];

    _searchController = [[ConversationSearchController alloc] initWithThread:threadViewModel.threadRecord];
    _searchController.delegate = self;

    // because the search bar view is hosted in the navigation bar, it's not in the CVC's responder
    // chain, and thus won't inherit our inputAccessoryView, so we manually set it here.
    OWSAssertDebug(self.inputAccessoryPlaceholder != nil);
    _searchController.uiSearchController.searchBar.inputAccessoryView = self.inputAccessoryPlaceholder;

    self.reloadTimer = [NSTimer weakTimerWithTimeInterval:1.f
                                                   target:self
                                                 selector:@selector(reloadTimerDidFire)
                                                 userInfo:nil
                                                  repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.reloadTimer forMode:NSRunLoopCommonModes];

    __weak ConversationViewController *weakSelf = self;
    _otherUsersProfileDidChangeEvent =
        [[DebouncedEvent alloc] initWithMaxFrequencySeconds:1.0
                                                    onQueue:dispatch_get_main_queue()
                                                notifyBlock:^{
                                                    // Reload all cells if this is a group conversation,
                                                    // since we may need to update the sender names on the messages.
                                                    [weakSelf.loadCoordinator
                                                        enqueueReloadWithCanReuseInteractionModels:YES
                                                                           canReuseComponentStates:NO];
                                                }];
    return self;
}

#pragma mark -

- (void)addNotificationListeners
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockListDidChange:)
                                                 name:kNSNotificationNameBlockListDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowManagerCallDidChange:)
                                                 name:OWSWindowManagerCallDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(identityStateDidChange:)
                                                 name:kNSNotificationNameIdentityStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didChangePreferredContentSize:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:OWSApplicationWillEnterForegroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:OWSApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:OWSApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(cancelReadTimer)
                                                 name:OWSApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileDidChange:)
                                                 name:kNSNotificationNameOtherUsersProfileDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileWhitelistDidChange:)
                                                 name:kNSNotificationNameProfileWhitelistDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange:)
                                                 name:ThemeDidChangeNotification
                                               object:nil];
}

- (BOOL)isGroupConversation
{
    OWSAssertDebug(self.thread);

    return self.thread.isGroupThread;
}

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    SignalServiceAddress *address = notification.userInfo[kNSNotificationKey_ProfileAddress];
    OWSAssertDebug(address.isValid);
    if (address.isValid && [self.thread.recipientAddresses containsObject:address]) {
        if ([self.thread isKindOfClass:[TSContactThread class]]) {
            // update title with profile name
            [self updateNavigationTitle];
        }

        // Reload all cells if this is a group conversation,
        // since we may need to update the sender names on the messages.
        // Use a DebounceEvent to de-bounce.
        if (self.isGroupConversation) {
            [self.otherUsersProfileDidChangeEvent requestNotify];
        }
    }
}

- (void)profileWhitelistDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    // If profile whitelist just changed, we may want to hide a profile whitelist offer.
    SignalServiceAddress *_Nullable address = notification.userInfo[kNSNotificationKey_ProfileAddress];
    NSData *_Nullable groupId = notification.userInfo[kNSNotificationKey_ProfileGroupId];
    if (address.isValid && [self.thread.recipientAddresses containsObject:address]) {
        [self ensureBannerState];
        [self showMessageRequestDialogIfRequired];
    } else if (groupId.length > 0 && self.thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)self.thread;
        if ([groupThread.groupModel.groupId isEqualToData:groupId]) {
            [self ensureBannerState];
            [self showMessageRequestDialogIfRequired];
        }
    }
}

- (void)blockListDidChange:(id)notification
{
    OWSAssertIsOnMainThread();

    [self ensureBannerState];
}

- (void)identityStateDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self updateNavigationBarSubtitleLabel];
    [self ensureBannerState];
}

- (void)themeDidChange:(NSNotification *)notification
{
    [self updateThemeIfNecessary];
}

- (BOOL)isInPreviewPlatter
{
    return self.viewState.isInPreviewPlatter;
}

- (void)setInPreviewPlatter:(BOOL)inPreviewPlatter
{
    if (self.viewState.isInPreviewPlatter != inPreviewPlatter) {
        self.viewState.isInPreviewPlatter = inPreviewPlatter;

        if (self.hasViewWillAppearEverBegun) {
            [self ensureBottomViewType];
        }
        [self configureScrollDownButtons];
    }
}

- (void)previewSetup
{
    [self setInPreviewPlatter:YES];
    self.actionOnOpen = ConversationViewActionNone;
}

- (void)updateV2GroupIfNecessary
{
    if (!self.thread.isGroupV2Thread) {
        return;
    }
    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    // Try to update the v2 group to latest from the service.
    // This will help keep us in sync if we've missed any group updates, etc.
    [self.groupV2UpdatesObjc tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithThrottling:groupThread];
}

- (void)dealloc
{
    [self.reloadTimer invalidate];
    [self.scrollUpdateTimer invalidate];
}

- (void)reloadTimerDidFire
{
    OWSAssertIsOnMainThread();

    if (self.isUserScrolling || !self.isViewCompletelyAppeared || !self.isViewVisible
        || !CurrentAppContext().isAppForegroundAndActive || !self.viewHasEverAppeared
        || self.isPresentingMessageActions) {
        return;
    }

    NSDate *now = [NSDate new];
    if (self.lastReloadDate) {
        NSTimeInterval timeSinceLastReload = [now timeIntervalSinceDate:self.lastReloadDate];
        const NSTimeInterval kReloadFrequency = 60.f;
        if (timeSinceLastReload < kReloadFrequency) {
            return;
        }
    }

    OWSLogVerbose(@"reloading conversation view contents.");

    // Auto-load more if necessary...
    if (![self autoLoadMoreIfNecessary]) {
        // ...Otherwise, reload everything.
        //
        // TODO: We could make this cheaper by using enqueueReload()
        // if we moved volatile profile / footer state to the view state.
        [self.loadCoordinator enqueueReload];
    }
}

- (void)viewDidLoad
{
    // We won't have a navigation controller if we're presented in a preview
    OWSAssertDebug(self.navigationController != nil || self.isInPreviewPlatter);

#ifdef TESTABLE_BUILD
    [self.initialLoadBenchSteps step:@"viewDidLoad.1"];
#endif

    [super viewDidLoad];

    [self createContents];
    [self createConversationScrollButtons];
    [self createHeaderViews];
    [self addNotificationListeners];
    [self.loadCoordinator viewDidLoad];

#ifdef TESTABLE_BUILD
    [self.initialLoadBenchSteps step:@"viewDidLoad.2"];
#endif
}

- (void)createContents
{
    OWSAssertDebug(self.conversationStyle);

    _layout = [[ConversationViewLayout alloc] initWithConversationStyle:self.conversationStyle];
    self.layout.delegate = self.loadCoordinator;

    // We use the root view bounds as the initial frame for the collection
    // view so that its contents can be laid out immediately.
    //
    // TODO: To avoid relayout, it'd be better to take into account safeAreaInsets,
    //       but they're not yet set when this method is called.
    _collectionView = [[ConversationCollectionView alloc] initWithFrame:self.view.bounds
                                                   collectionViewLayout:self.layout];
    self.collectionView.layoutDelegate = self;
    self.collectionView.delegate = self.loadCoordinator;
    self.collectionView.dataSource = self.loadCoordinator;
    self.collectionView.showsVerticalScrollIndicator = YES;
    self.collectionView.showsHorizontalScrollIndicator = NO;
    self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.collectionView.allowsMultipleSelection = YES;

    // To minimize time to initial apearance, we initially disable prefetching, but then
    // re-enable it once the view has appeared.
    self.collectionView.prefetchingEnabled = NO;

    [self.view addSubview:self.collectionView];
    [self.collectionView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [self.collectionView autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [self.collectionView autoPinEdgeToSuperviewSafeArea:ALEdgeLeading];
    [self.collectionView autoPinEdgeToSuperviewSafeArea:ALEdgeTrailing];

    [self.collectionView applyScrollViewInsetsFix];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _collectionView);

    [self registerReuseIdentifiers];

    [self.view addSubview:self.bottomBar];
    self.bottomBarBottomConstraint = [self.bottomBar autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [self.bottomBar autoPinWidthToSuperview];

    _selectionToolbar = [self buildSelectionToolbar];
    _selectionHighlightView = [SelectionHighlightView new];
    self.selectionHighlightView.userInteractionEnabled = NO;
    [self.collectionView addSubview:self.selectionHighlightView];
#if TESTABLE_BUILD
    self.selectionHighlightView.accessibilityIdentifier = @"selectionHighlightView";
#endif

    // Selection Highlight View Layout:
    //
    // We want the highlight view to have the same frame as the collectionView
    // but [selectionHighlightView autoPinEdgesToSuperviewEdges] undesirably
    // affects the size of the collection view. To witness this, you can longpress
    // on an item and see the collectionView offsets change. Pinning to just the
    // top left and the same height/width achieves the desired results without
    // the negative side effects.
    [self.selectionHighlightView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [self.selectionHighlightView autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    [self.selectionHighlightView autoMatchDimension:ALDimensionWidth
                                        toDimension:ALDimensionWidth
                                             ofView:self.collectionView];
    [self.selectionHighlightView autoMatchDimension:ALDimensionHeight
                                        toDimension:ALDimensionHeight
                                             ofView:self.collectionView];

    // This should kick off the first load.
    OWSAssertDebug(!self.hasRenderState);
    OWSAssertDebug(!self.loadCoordinator.hasLoadInFlight);
    [self updateConversationStyle];
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (BOOL)becomeFirstResponder
{
    BOOL result = [super becomeFirstResponder];

    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return result;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return result;
    }

    // If we become the first responder, it means that the
    // input toolbar is not the first responder. As such,
    // we should clear out the desired keyboard since an
    // interactive dismissal may have just occured and we
    // need to update the UI to reflect that fact. We don't
    // actually ever want to be the first responder, so resign
    // immediately. We just want to know when the responder
    // state of our children changed and that information is
    // conveniently bubbled up the responder chain.
    if (result) {
        [self resignFirstResponder];
        [self.inputToolbar clearDesiredKeyboard];
    }

    return result;
}

- (nullable UIView *)inputAccessoryView
{
    return self.inputAccessoryPlaceholder;
}

- (nullable NSString *)textInputContextIdentifier
{
    return self.thread.uniqueId;
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    [self startReadTimer];
    [self updateCellsVisible];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    [self updateCellsVisible];
    [self.cellMediaCache removeAllObjects];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    [self cancelVoiceMemo];
    self.isUserScrolling = NO;
    self.isWaitingForDeceleration = NO;
    [self saveDraft];
    [self markVisibleMessagesAsRead];
    [self.cellMediaCache removeAllObjects];
    [self cancelReadTimer];
    [self dismissPresentedViewControllerIfNecessary];
    [self saveLastVisibleSortIdAndOnScreenPercentage];

    [self dismissKeyBoard];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    [self startReadTimer];
}

- (void)dismissPresentedViewControllerIfNecessary
{
    UIViewController *_Nullable presentedViewController = self.presentedViewController;
    if (!presentedViewController) {
        OWSLogDebug(@"presentedViewController was nil");
        return;
    }

    if ([presentedViewController isKindOfClass:[ActionSheetController class]] ||
        [presentedViewController isKindOfClass:[UIAlertController class]]) {
        OWSLogDebug(@"dismissing presentedViewController: %@", presentedViewController);
        [self dismissViewControllerAnimated:NO completion:nil];
        return;
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [self viewWillAppearDidBegin];

#ifdef TESTABLE_BUILD
    [self.initialLoadBenchSteps step:@"viewWillAppear.1"];
#endif

    OWSLogDebug(@"viewWillAppear");

    [self ensureBannerState];

    [super viewWillAppear:animated];

    if (self.inputToolbar == nil) {
        // This will create the input toolbar for the first time.
        // It's important that we do this at the "last moment" to
        // avoid expensive work that delays CVC presentation.
        [self applyTheme];
        OWSAssertDebug(self.inputToolbar != nil);

        [self createGestureRecognizers];
    }

    self.isViewVisible = YES;
    [self viewWillAppearForLoad];

    // We should have already requested contact access at this point, so this should be a no-op
    // unless it ever becomes possible to load this VC without going via the ConversationListViewController.
    [self.contactsManager requestSystemContactsOnce];

    [self updateBarButtonItems];
    [self updateNavigationTitle];

    // One-time work performed the first time we enter the view.
    if (!self.viewHasEverAppeared) {
        [BenchManager
            completeEventWithEventId:[NSString stringWithFormat:@"presenting-conversation-%@", self.thread.uniqueId]];
    }
    [self ensureBottomViewType];
    [self updateInputToolbarLayout];
    [self refreshCallState];

    [self showMessageRequestDialogIfRequired];
    [self viewWillAppearDidComplete];
#ifdef TESTABLE_BUILD
    [self.initialLoadBenchSteps step:@"viewWillAppear.2"];
#endif
}

- (void)setUserHasScrolled:(BOOL)userHasScrolled
{
    _userHasScrolled = userHasScrolled;

    [self ensureBannerState];
}

// Returns a collection of the group members who are "no longer verified".
- (NSArray<SignalServiceAddress *> *)noLongerVerifiedAddresses
{
    NSMutableArray<SignalServiceAddress *> *result = [NSMutableArray new];
    for (SignalServiceAddress *address in self.thread.recipientAddresses) {
        if ([[OWSIdentityManager shared] verificationStateForAddress:address] == OWSVerificationStateNoLongerVerified) {
            [result addObject:address];
        }
    }
    return [result copy];
}

- (void)ensureBannerState
{
    __weak ConversationViewController *weakSelf = self;

    // This method should be called rarely, so it's simplest to discard and
    // rebuild the indicator view every time.
    [self.bannerView removeFromSuperview];
    self.bannerView = nil;

    NSMutableArray<UIView *> *banners = [NSMutableArray new];

    // Most of these banners should hide themselves when the user scrolls
    if (!self.userHasScrolled) {
        NSArray<SignalServiceAddress *> *noLongerVerifiedAddresses = [self noLongerVerifiedAddresses];
        if (noLongerVerifiedAddresses.count > 0) {
            NSString *message;
            if (noLongerVerifiedAddresses.count > 1) {
                message = NSLocalizedString(@"MESSAGES_VIEW_N_MEMBERS_NO_LONGER_VERIFIED",
                    @"Indicates that more than one member of this group conversation is no longer verified.");
            } else {
                SignalServiceAddress *address = [noLongerVerifiedAddresses firstObject];
                NSString *displayName = [self.contactsManager displayNameForAddress:address];
                NSString *format
                    = (self.isGroupConversation ? NSLocalizedString(@"MESSAGES_VIEW_1_MEMBER_NO_LONGER_VERIFIED_FORMAT",
                           @"Indicates that one member of this group conversation is no longer "
                           @"verified. Embeds {{user's name or phone number}}.")
                                                : NSLocalizedString(@"MESSAGES_VIEW_CONTACT_NO_LONGER_VERIFIED_FORMAT",
                                                    @"Indicates that this 1:1 conversation is no longer verified. Embeds "
                                                    @"{{user's name or phone number}}."));
                message = [NSString stringWithFormat:format, displayName];
            }

            UIView *banner = [ConversationViewController
                createBannerWithTitleWithTitle:message
                                   bannerColor:UIColor.ows_accentRedColor
                                      tapBlock:^{ [weakSelf noLongerVerifiedBannerViewWasTapped]; }];
            [banners addObject:banner];
        }

        NSString *blockStateMessage = nil;
        if (self.isGroupConversation) {
            int blockedGroupMemberCount = [self blockedGroupMemberCount];
            if (blockedGroupMemberCount == 1) {
                blockStateMessage = NSLocalizedString(@"MESSAGES_VIEW_GROUP_1_MEMBER_BLOCKED",
                    @"Indicates that a single member of this group has been blocked.");
            } else if (blockedGroupMemberCount > 1) {
                blockStateMessage =
                    [NSString stringWithFormat:NSLocalizedString(@"MESSAGES_VIEW_GROUP_N_MEMBERS_BLOCKED_FORMAT",
                                                   @"Indicates that some members of this group has been blocked. Embeds "
                                                   @"{{the number of blocked users in this group}}."),
                              [OWSFormat formatInt:blockedGroupMemberCount]];
            }
        }

        if (blockStateMessage) {
            UIView *banner =
                [ConversationViewController createBannerWithTitleWithTitle:blockStateMessage
                                                               bannerColor:UIColor.ows_accentRedColor
                                                                  tapBlock:^{ [weakSelf blockBannerViewWasTapped]; }];
            [banners addObject:banner];
        }

        NSUInteger pendingMemberRequestCount = self.pendingMemberRequestCount;
        if (pendingMemberRequestCount > 0 && self.canApprovePendingMemberRequests
            && !self.viewState.isPendingMemberRequestsBannerHidden) {
            UIView *banner = [self
                createPendingJoinRequestBannerWithViewState:self.viewState
                                                      count:pendingMemberRequestCount
                                    viewMemberRequestsBlock:^{ [weakSelf showConversationSettingsAndShowMemberRequests]; }];
            [banners addObject:banner];
        }

        GroupsV2MigrationInfo *_Nullable migrationInfo = [self manualMigrationInfoForGroup];
        if (migrationInfo != nil && migrationInfo.canGroupBeMigrated && !self.viewState.isMigrateGroupBannerHidden
            && !GroupManager.areMigrationsBlocking) {
            UIView *banner = [self createMigrateGroupBannerWithViewState:self.viewState migrationInfo:migrationInfo];
            [banners addObject:banner];
        }

        UIView *_Nullable droppedGroupMembersBanner;
        droppedGroupMembersBanner = [self createDroppedGroupMembersBannerIfNecessaryWithViewState:self.viewState];
        if (droppedGroupMembersBanner != nil) {
            [banners addObject:droppedGroupMembersBanner];
        }
    }

    UIView *_Nullable messageRequestNameCollisionBanner;
    messageRequestNameCollisionBanner = [self createMessageRequestNameCollisionBannerIfNecessaryWithViewState:self.viewState];
    if (messageRequestNameCollisionBanner != nil) {
        [banners addObject:messageRequestNameCollisionBanner];
    }

    if (banners.count < 1) {
        if (self.hasViewDidAppearEverBegun) {
            [self updateContentInsetsAnimated:NO];
        }
        return;
    }

    UIStackView *bannerView = [[UIStackView alloc] initWithArrangedSubviews:banners];
    bannerView.axis = UILayoutConstraintAxisVertical;
    bannerView.alignment = UIStackViewAlignmentFill;
    [self.view addSubview:bannerView];
    [bannerView autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [bannerView autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    [bannerView autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    [self.view layoutSubviews];

    self.bannerView = bannerView;
    if (self.hasViewDidAppearEverBegun) {
        [self updateContentInsetsAnimated:NO];
    }
}

- (NSUInteger)pendingMemberRequestCount
{
    if ([self.thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)self.thread;
        return groupThread.groupMembership.requestingMembers.count;
    } else {
        return 0;
    }
}

- (BOOL)canApprovePendingMemberRequests
{
    if ([self.thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)self.thread;
        return groupThread.isLocalUserFullMemberAndAdministrator;
    } else {
        return NO;
    }
}

- (void)blockBannerViewWasTapped
{
    if ([self isBlockedConversation]) {
        // If this a blocked conversation, offer to unblock.
        [self showUnblockConversationUI:nil];
    } else if (self.isGroupConversation) {
        // If this a group conversation with at least one blocked member,
        // Show the block list view.
        int blockedGroupMemberCount = [self blockedGroupMemberCount];
        if (blockedGroupMemberCount > 0) {
            BlockListViewController *vc = [[BlockListViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        }
    }
}

- (void)noLongerVerifiedBannerViewWasTapped
{
    NSArray<SignalServiceAddress *> *noLongerVerifiedAddresses = [self noLongerVerifiedAddresses];
    if (noLongerVerifiedAddresses.count < 1) {
        return;
    }
    BOOL hasMultiple = noLongerVerifiedAddresses.count > 1;

    ActionSheetController *actionSheet = [ActionSheetController new];

    __weak ConversationViewController *weakSelf = self;
    ActionSheetAction *verifyAction = [[ActionSheetAction alloc]
        initWithTitle:(hasMultiple ? NSLocalizedString(@"VERIFY_PRIVACY_MULTIPLE",
                           @"Label for button or row which allows users to verify the safety "
                           @"numbers of multiple users.")
                                   : NSLocalizedString(@"VERIFY_PRIVACY",
                                       @"Label for button or row which allows users to verify the safety "
                                       @"number of another user."))
                style:ActionSheetActionStyleDefault
              handler:^(ActionSheetAction *action) { [weakSelf showNoLongerVerifiedUI]; }];
    [actionSheet addAction:verifyAction];

    ActionSheetAction *dismissAction = [[ActionSheetAction alloc]
                  initWithTitle:CommonStrings.dismissButton
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"dismiss")
                          style:ActionSheetActionStyleCancel
                        handler:^(ActionSheetAction *action) { [weakSelf resetVerificationStateToDefault]; }];
    [actionSheet addAction:dismissAction];

    [self dismissKeyBoard];
    [self presentActionSheet:actionSheet];
}

- (void)resetVerificationStateToDefault
{
    OWSAssertIsOnMainThread();

    NSArray<SignalServiceAddress *> *noLongerVerifiedAddresses = [self noLongerVerifiedAddresses];
    for (SignalServiceAddress *address in noLongerVerifiedAddresses) {
        OWSAssertDebug(address.isValid);

        OWSRecipientIdentity *_Nullable recipientIdentity =
            [[OWSIdentityManager shared] recipientIdentityForAddress:address];
        OWSAssertDebug(recipientIdentity);

        NSData *identityKey = recipientIdentity.identityKey;
        OWSAssertDebug(identityKey.length > 0);
        if (identityKey.length < 1) {
            continue;
        }

        [OWSIdentityManager.shared setVerificationState:OWSVerificationStateDefault
                                            identityKey:identityKey
                                                address:address
                                  isUserInitiatedChange:YES];
    }
}

- (void)showUnblockConversationUI:(nullable BlockActionCompletionBlock)completionBlock
{
    self.userHasScrolled = NO;

    // To avoid "noisy" animations (hiding the keyboard before showing
    // the action sheet, re-showing it after), hide the keyboard before
    // showing the "unblock" action sheet.
    //
    // Unblocking is a rare interaction, so it's okay to leave the keyboard
    // hidden.
    [self dismissKeyBoard];

    [BlockListUIUtils showUnblockThreadActionSheet:self.thread
                                fromViewController:self
                                   completionBlock:completionBlock];
}

- (BOOL)isBlockedConversation
{
    return [self.blockingManager isThreadBlocked:self.thread];
}

- (int)blockedGroupMemberCount
{
    OWSAssertDebug(self.isGroupConversation);
    OWSAssertDebug([self.thread isKindOfClass:[TSGroupThread class]]);

    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    int blockedMemberCount = 0;
    for (SignalServiceAddress *address in groupThread.groupModel.groupMembers) {
        if ([self.blockingManager isAddressBlocked:address]) {
            blockedMemberCount++;
        }
    }
    return blockedMemberCount;
}

- (void)startReadTimer
{
    [self.readTimer invalidate];
    self.readTimer = [NSTimer weakTimerWithTimeInterval:0.1f
                                                 target:self
                                               selector:@selector(readTimerDidFire)
                                               userInfo:nil
                                                repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.readTimer forMode:NSRunLoopCommonModes];
}

- (void)readTimerDidFire
{
    if (self.layout.isPerformingBatchUpdates) {
        return;
    }
    [self markVisibleMessagesAsRead];
}

- (void)cancelReadTimer
{
    [self.readTimer invalidate];
    self.readTimer = nil;
}

- (void)viewDidAppear:(BOOL)animated
{
    [self viewDidAppearDidBegin];

#ifdef TESTABLE_BUILD
    [self.initialLoadBenchSteps step:@"viewDidAppear.1"];
#endif
    OWSLogDebug(@"viewDidAppear");

    [super viewDidAppear:animated];

    // We don't present incoming message notifications for the presented
    // conversation. But there's a narrow window *while* the conversationVC
    // is being presented where a message notification for the not-quite-yet
    // presented conversation can be shown. If that happens, dismiss it as soon
    // as we enter the conversation.
    [self.notificationPresenter cancelNotificationsWithThreadId:self.thread.uniqueId];

    // recover status bar when returning from PhotoPicker, which is dark (uses light status bar)
    [self setNeedsStatusBarAppearanceUpdate];

    [self.bulkProfileFetch fetchProfilesWithThread:self.thread];
    [self markVisibleMessagesAsRead];
    [self startReadTimer];
    [self updateNavigationBarSubtitleLabel];
    [self autoLoadMoreIfNecessary];
    [self updateV2GroupIfNecessary];

    if (!self.viewHasEverAppeared) {
        // To minimize time to initial apearance, we initially disable prefetching, but then
        // re-enable it once the view has appeared.
        self.collectionView.prefetchingEnabled = YES;
    }

    self.isViewCompletelyAppeared = YES;
    self.shouldAnimateKeyboardChanges = YES;

    switch (self.actionOnOpen) {
        case ConversationViewActionNone:
            break;
        case ConversationViewActionCompose:
            // Don't pop the keyboard if we have a pending message request, since
            // the user can't currently send a message until acting on this
            if (!self.requestView) {
                [self popKeyBoard];
            }

            // When we programmatically pop the keyboard here,
            // the scroll position gets into a weird state and
            // content is hidden behind the keyboard so we restore
            // it to the default position.
            [self scrollToInitialPositionAnimated:YES];
            break;
        case ConversationViewActionAudioCall:
            [self startIndividualAudioCall];
            break;
        case ConversationViewActionVideoCall:
            [self startIndividualVideoCall];
            break;
        case ConversationViewActionGroupCallLobby:
            [self showGroupLobbyOrActiveCall];
            break;
        case ConversationViewActionNewGroupActionSheet:
            dispatch_async(dispatch_get_main_queue(), ^{ [self showGroupLinkPromotionActionSheet]; });
            break;
    }

    // Clear the "on open" state after the view has been presented.
    self.actionOnOpen = ConversationViewActionNone;

    [self updateInputToolbarLayout];
    [self configureScrollDownButtons];
    [self.inputToolbar viewDidAppear];

    if (!self.viewState.hasTriedToMigrateGroup) {
        self.viewState.hasTriedToMigrateGroup = YES;

        [GroupsV2Migration autoMigrateThreadIfNecessary:self.thread];
    }

    [self viewDidAppearDidComplete];
#ifdef TESTABLE_BUILD
    [self.initialLoadBenchSteps step:@"viewDidAppear.2"];
#endif
}

// `viewWillDisappear` is called whenever the view *starts* to disappear,
// but, as is the case with the "pan left for message details view" gesture,
// this can be canceled. As such, we shouldn't tear down anything expensive
// until `viewDidDisappear`.
- (void)viewWillDisappear:(BOOL)animated
{
    OWSLogDebug(@"");

    [super viewWillDisappear:animated];

    self.isViewCompletelyAppeared = NO;

    [self dismissMessageActionsAnimated:NO];
    [self dismissReactionsDetailSheetAnimated:NO];
    [self saveLastVisibleSortIdAndOnScreenPercentage];
}

- (void)viewDidDisappear:(BOOL)animated
{
    OWSLogDebug(@"");

    [super viewDidDisappear:animated];
    self.userHasScrolled = NO;
    self.isViewVisible = NO;
    self.shouldAnimateKeyboardChanges = NO;

    [self.audioPlayer stopAll];

    [self cancelReadTimer];
    [self saveDraft];
    [self markVisibleMessagesAsRead];
    [self cancelVoiceMemo];
    [self.cellMediaCache removeAllObjects];
    [self.inputToolbar clearDesiredKeyboard];

    self.isUserScrolling = NO;
    self.isWaitingForDeceleration = NO;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    if (!self.hasViewWillAppearEverBegun) {
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    // We resize the inputToolbar whenever it's text is modified, including when setting saved draft-text.
    // However it's possible this draft-text is set before the inputToolbar (an inputAccessoryView) is mounted
    // in the view hierarchy. Since it's not in the view hierarchy, it hasn't been laid out and has no width,
    // which is used to determine height.
    // So here we unsure the proper height once we know everything's been layed out.
    [self.inputToolbar ensureTextViewHeight];

    [self positionGroupCallTooltip];
}

#pragma mark - Initializers

- (void)updateNavigationTitle
{
    NSString *_Nullable name;
    NSAttributedString *_Nullable attributedName;
    UIImage *_Nullable icon;
    if ([self.thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *thread = (TSContactThread *)self.thread;

        OWSAssertDebug(thread.contactAddress);

        if (thread.isNoteToSelf) {
            name = MessageStrings.noteToSelf;
        } else {
            name = [self.contactsManager displayNameForAddress:thread.contactAddress];
        }

        // If the user is in the system contacts, show a badge
        if ([self.contactsManager hasSignalAccountForAddress:thread.contactAddress]) {
            icon =
                [[UIImage imageNamed:@"contact-outline-16"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
    } else if ([self.thread isKindOfClass:TSGroupThread.class]) {
        TSGroupThread *groupThread = (TSGroupThread *)self.thread;
        name = groupThread.groupNameOrDefault;
    } else {
        OWSFailDebug(@"failure: unexpected thread: %@", self.thread);
    }
    self.title = nil;

    self.headerView.titleIcon = icon;

    if (name && !attributedName) {
        attributedName =
            [[NSAttributedString alloc] initWithString:name
                                            attributes:@{ NSForegroundColorAttributeName : Theme.primaryTextColor }];
    }

    if ([attributedName isEqual:self.headerView.attributedTitle]) {
        return;
    }

    self.headerView.attributedTitle = attributedName;
}

- (void)createHeaderViews
{
    ConversationHeaderView *headerView = [[ConversationHeaderView alloc] initWithThread:self.thread];
    headerView.accessibilityLabel = NSLocalizedString(@"CONVERSATION_SETTINGS", "title for conversation settings screen");
    self.headerView = headerView;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, headerView);

    headerView.delegate = self;
    self.navigationItem.titleView = headerView;

#ifdef USE_DEBUG_UI
    [headerView addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
                                         initWithTarget:self
                                                 action:@selector(navigationTitleLongPressed:)]];
#endif


    [self updateNavigationBarSubtitleLabel];
}

- (CGFloat)unreadCountViewDiameter
{
    return 16;
}

- (void)windowManagerCallDidChange:(NSNotification *)notification
{
    [self updateBarButtonItems];
}

- (void)updateBarButtonItems
{
    // Don't include "Back" text on view controllers pushed above us, just use the arrow.
    [self.navigationItem setBackBarButtonItem:[[UIBarButtonItem alloc] initWithTitle:@""
                                                                               style:UIBarButtonItemStylePlain
                                                                              target:nil
                                                                              action:nil]];

    self.navigationItem.hidesBackButton = NO;
    self.navigationItem.leftBarButtonItem = nil;
    self.groupCallBarButtonItem = nil;

    switch (self.uiMode) {
        case ConversationUIMode_Search: {
            if (self.userLeftGroup) {
                self.navigationItem.rightBarButtonItems = @[];
                return;
            }
            if (@available(iOS 13.0, *)) {
                OWSAssertDebug(self.navigationItem.searchController != nil);
            } else {
                self.navigationItem.rightBarButtonItems = @[];
                self.navigationItem.leftBarButtonItem = nil;
                self.navigationItem.hidesBackButton = YES;
            }
            return;
        }
        case ConversationUIMode_Selection: {
            self.navigationItem.rightBarButtonItems = @[ self.cancelSelectionBarButtonItem ];
            self.navigationItem.leftBarButtonItem = self.deleteAllBarButtonItem;
            self.navigationItem.hidesBackButton = YES;
            return;
        }
        case ConversationUIMode_Normal: {
            if (self.userLeftGroup) {
                self.navigationItem.rightBarButtonItems = @[];
                return;
            }
            NSMutableArray<UIBarButtonItem *> *barButtons = [NSMutableArray new];
            if ([self canCall]) {
                if (self.isGroupConversation) {
                    UIBarButtonItem *videoCallButton = [[UIBarButtonItem alloc] init];

                    if (self.threadViewModel.groupCallInProgress) {
                        OWSJoinGroupCallPill *pill = [[OWSJoinGroupCallPill alloc] init];
                        [pill addTarget:self
                                      action:@selector(showGroupLobbyOrActiveCall)
                            forControlEvents:UIControlEventTouchUpInside];
                        NSString *returnString = NSLocalizedString(@"RETURN_CALL_PILL_BUTTON", comment
                                                                   : "Button to return to current group call");
                        NSString *joinString = NSLocalizedString(@"JOIN_CALL_PILL_BUTTON", comment
                                                                 : "Button to join an active group call");
                        pill.buttonText = self.isCurrentCallForThread ? returnString : joinString;
                        [videoCallButton setCustomView:pill];
                    } else {
                        UIImage *image = [Theme iconImage:ThemeIconVideoCall];
                        [videoCallButton setImage:image];
                        videoCallButton.target = self;
                        videoCallButton.action = @selector(showGroupLobbyOrActiveCall);
                    }

                    videoCallButton.enabled = (self.callService.currentCall == nil) || self.isCurrentCallForThread;
                    videoCallButton.accessibilityLabel
                        = NSLocalizedString(@"VIDEO_CALL_LABEL", "Accessibility label for placing a video call");
                    self.groupCallBarButtonItem = videoCallButton;
                    [barButtons addObject:videoCallButton];
                } else {
                    UIBarButtonItem *audioCallButton =
                        [[UIBarButtonItem alloc] initWithImage:[Theme iconImage:ThemeIconAudioCall]
                                                         style:UIBarButtonItemStylePlain
                                                        target:self
                                                        action:@selector(startIndividualAudioCall)];
                    audioCallButton.enabled = !OWSWindowManager.shared.hasCall;
                    audioCallButton.accessibilityLabel
                        = NSLocalizedString(@"AUDIO_CALL_LABEL", "Accessibility label for placing an audio call");
                    [barButtons addObject:audioCallButton];

                    UIBarButtonItem *videoCallButton =
                        [[UIBarButtonItem alloc] initWithImage:[Theme iconImage:ThemeIconVideoCall]
                                                         style:UIBarButtonItemStylePlain
                                                        target:self
                                                        action:@selector(startIndividualVideoCall)];
                    videoCallButton.enabled = !OWSWindowManager.shared.hasCall;
                    videoCallButton.accessibilityLabel
                        = NSLocalizedString(@"VIDEO_CALL_LABEL", "Accessibility label for placing a video call");
                    [barButtons addObject:videoCallButton];
                }
            }

            self.navigationItem.rightBarButtonItems = [barButtons copy];
            [self showGroupCallTooltipIfNecessary];
            return;
        }
    }
}

- (void)updateNavigationBarSubtitleLabel
{
    BOOL hasCompactHeader = self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
    if (hasCompactHeader) {
        self.headerView.attributedSubtitle = nil;
        return;
    }

    NSMutableAttributedString *subtitleText = [NSMutableAttributedString new];
    UIFont *subtitleFont = self.headerView.subtitleFont;
    NSDictionary *attributes = @{
        NSFontAttributeName : subtitleFont,
        NSForegroundColorAttributeName : [Theme.navbarTitleColor colorWithAlphaComponent:(CGFloat)0.9],
    };
    NSString *hairSpace = @"\u200a";
    NSString *thinSpace = @"\u2009";
    NSString *iconSpacer = UIDevice.currentDevice.isNarrowerThanIPhone6 ? hairSpace : thinSpace;
    NSString *betweenItemSpacer = UIDevice.currentDevice.isNarrowerThanIPhone6 ? @" " : @"  ";

    BOOL isMuted = self.thread.isMuted;
    BOOL hasTimer = self.disappearingMessagesConfiguration.isEnabled;
    BOOL isVerified = self.thread.recipientAddresses.count > 0;
    for (SignalServiceAddress *address in self.thread.recipientAddresses) {
        if ([[OWSIdentityManager shared] verificationStateForAddress:address] != OWSVerificationStateVerified) {
            isVerified = NO;
            break;
        }
    }

    if (isMuted) {
        [subtitleText appendTemplatedImageNamed:@"bell-disabled-outline-24" font:subtitleFont];
        if (!isVerified) {
            [subtitleText append:iconSpacer attributes:attributes];
            [subtitleText append:NSLocalizedString(@"MUTED_BADGE", @"Badge indicating that the user is muted.")
                      attributes:attributes];
        }
    }

    if (hasTimer) {
        if (isMuted) {
            [subtitleText append:betweenItemSpacer attributes:attributes];
        }

        [subtitleText appendTemplatedImageNamed:@"timer-outline-16" font:subtitleFont];
        [subtitleText append:iconSpacer attributes:attributes];
        [subtitleText append:[NSString formatDurationSeconds:self.disappearingMessagesConfiguration.durationSeconds
                                              useShortFormat:YES]
                  attributes:attributes];
    }

    if (isVerified) {
        if (hasTimer || isMuted) {
            [subtitleText append:betweenItemSpacer attributes:attributes];
        }

        [subtitleText appendTemplatedImageNamed:@"check-12" font:subtitleFont];
        [subtitleText append:iconSpacer attributes:attributes];
        [subtitleText append:NSLocalizedString(
                                 @"PRIVACY_IDENTITY_IS_VERIFIED_BADGE", @"Badge indicating that the user is verified.")
                  attributes:attributes];
    }

    self.headerView.attributedSubtitle = subtitleText;
}


#pragma mark - Identity

/**
 * Shows confirmation dialog if at least one of the recipient id's is not confirmed.
 *
 * returns YES if an alert was shown
 *          NO if there were no unconfirmed identities
 */
- (BOOL)showSafetyNumberConfirmationIfNecessaryWithConfirmationText:(NSString *)confirmationText
                                                         completion:(void (^)(BOOL didConfirmIdentity))completionHandler
{
    return [SafetyNumberConfirmationSheet presentIfNecessaryWithAddresses:self.thread.recipientAddresses
                                                         confirmationText:confirmationText
                                                               completion:completionHandler];
}

#pragma mark - Calls

- (void)showGroupLobbyOrActiveCall
{
    if (self.isCurrentCallForThread) {
        [OWSWindowManager.shared returnToCallView];
        return;
    }

    if (!self.isGroupConversation) {
        OWSFailDebug(@"Tried to present group call for non-group thread.");
        return;
    }

    if (!self.canCall) {
        OWSFailDebug(@"Tried to initiate a call but thread is not callable.");
        return;
    }

    [self removeGroupCallTooltip];

    // We initiated a call, so if there was a pending message request we should accept it.
    [ThreadUtil addThreadToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction:self.thread];

    [GroupCallViewController presentLobbyForThread:(TSGroupThread *)self.thread];
}

- (void)startIndividualAudioCall
{
    [self individualCallWithVideo:NO];
}

- (void)startIndividualVideoCall
{
    [self individualCallWithVideo:YES];
}

- (void)individualCallWithVideo:(BOOL)isVideo
{
    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFailDebug(@"unexpected thread: %@", self.thread);
        return;
    }
    TSContactThread *contactThread = (TSContactThread *)self.thread;

    if (![self canCall]) {
        OWSLogWarn(@"Tried to initiate a call but thread is not callable.");
        return;
    }

    __weak ConversationViewController *weakSelf = self;
    if ([self isBlockedConversation]) {
        [self showUnblockConversationUI:^(BOOL isBlocked) {
            if (!isBlocked) {
                [weakSelf individualCallWithVideo:isVideo];
            }
        }];
        return;
    }

    BOOL didShowSNAlert =
        [self showSafetyNumberConfirmationIfNecessaryWithConfirmationText:[CallStrings confirmAndCallButtonTitle]
                                                               completion:^(BOOL didConfirmIdentity) {
                                                                   if (didConfirmIdentity) {
                                                                       [weakSelf individualCallWithVideo:isVideo];
                                                                   }
                                                               }];
    if (didShowSNAlert) {
        return;
    }

    // We initiated a call, so if there was a pending message request we should accept it.
    [ThreadUtil addThreadToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction:self.thread];

    [self.outboundIndividualCallInitiator initiateCallWithAddress:contactThread.contactAddress isVideo:isVideo];
}

- (BOOL)canCall
{
    return [ConversationViewController canCallThreadViewModel:self.threadViewModel];
}

- (void)refreshCallState
{
    if (self.thread.isGroupV2Thread) {
        TSGroupThread *groupThread = (TSGroupThread *)self.thread;
        [self.callService peekCallAndUpdateThread:groupThread];
    }
}

#pragma mark - Dynamic Text

/**
 Called whenever the user manually changes the dynamic type options inside Settings.

 @param notification NSNotification with the dynamic type change information.
 */
- (void)didChangePreferredContentSize:(NSNotification *)notification
{
    OWSLogInfo(@"didChangePreferredContentSize");

    [self resetForSizeOrOrientationChange];

    if (!self.hasViewWillAppearEverBegun) {
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    [self.inputToolbar updateFontSizes];
}

#pragma mark - Actions

- (void)showNoLongerVerifiedUI
{
    NSArray<SignalServiceAddress *> *noLongerVerifiedAddresses = [self noLongerVerifiedAddresses];
    if (noLongerVerifiedAddresses.count > 1) {
        [self showConversationSettingsAndShowVerification];
    } else if (noLongerVerifiedAddresses.count == 1) {
        // Pick one in an arbitrary but deterministic manner.
        SignalServiceAddress *address = noLongerVerifiedAddresses.lastObject;
        [self showFingerprintWithAddress:address];
    }
}

- (void)showConversationSettings
{
    [self showConversationSettingsWithMode:ConversationSettingsPresentationModeDefault];
}

- (void)showConversationSettingsAndShowAllMedia
{
    [self showConversationSettingsWithMode:ConversationSettingsPresentationModeShowAllMedia];
}

- (void)showConversationSettingsAndShowVerification
{
    [self showConversationSettingsWithMode:ConversationSettingsPresentationModeShowVerification];
}

- (void)showConversationSettingsAndShowMemberRequests
{
    [self showConversationSettingsWithMode:ConversationSettingsPresentationModeShowMemberRequests];
}

- (void)showConversationSettingsWithMode:(ConversationSettingsPresentationMode)mode
{
    NSMutableArray<UIViewController *> *viewControllers = [self.viewControllersUpToSelf mutableCopy];

    ConversationSettingsViewController *settingsView =
        [[ConversationSettingsViewController alloc] initWithThreadViewModel:self.threadViewModel];
    settingsView.conversationSettingsViewDelegate = self;
    [viewControllers addObject:settingsView];

    switch (mode) {
        case ConversationSettingsPresentationModeDefault:
            break;
        case ConversationSettingsPresentationModeShowVerification:
            settingsView.showVerificationOnAppear = YES;
            break;
        case ConversationSettingsPresentationModeShowMemberRequests: {
            UIViewController *_Nullable view = [settingsView buildMemberRequestsAndInvitesView];
            if (view != nil) {
                [viewControllers addObject:view];
            }
            break;
        }
        case ConversationSettingsPresentationModeShowAllMedia:
            [viewControllers addObject:[[MediaTileViewController alloc] initWithThread:self.thread]];
            break;
    }

    [self.navigationController setViewControllers:viewControllers animated:YES];
}

- (NSArray<UIViewController *> *)viewControllersUpToSelf
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.navigationController);

    if (self.navigationController.topViewController == self) {
        return self.navigationController.viewControllers;
    }

    NSArray *viewControllers = self.navigationController.viewControllers;
    NSUInteger index = [viewControllers indexOfObject:self];

    if (index == NSNotFound) {
        OWSFailDebug(@"Unexpectedly missing from view hierarhy");
        return viewControllers;
    }

    return [viewControllers subarrayWithRange:NSMakeRange(0, index + 1)];
}

#pragma mark - Load More

- (BOOL)autoLoadMoreIfNecessary
{
    if (!self.hasAppearedAndHasAppliedFirstLoad) {
        return NO;
    }
    BOOL isMainAppAndActive = CurrentAppContext().isMainAppAndActive;
    if (!self.isViewVisible || !isMainAppAndActive) {
        return NO;
    }
    if (!self.showLoadOlderHeader && !self.showLoadNewerHeader) {
        return NO;
    }
    [self.navigationController.view layoutIfNeeded];
    CGSize navControllerSize = self.navigationController.view.frame.size;
    CGFloat loadThreshold = MAX(navControllerSize.width, navControllerSize.height) * 3;
    CGFloat distanceFromTop = self.collectionView.contentOffset.y;
    BOOL closeToTop = distanceFromTop < loadThreshold;
    if (self.showLoadOlderHeader && closeToTop) {

        if (self.loadCoordinator.didLoadOlderRecently) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [weakSelf autoLoadMoreIfNecessary];
            });
            return NO;
        }

        [self.loadCoordinator loadOlderItems];
        return YES;
    }

    CGFloat distanceFromBottom = self.collectionView.contentSize.height - self.collectionView.bounds.size.height
        - self.collectionView.contentOffset.y;
    BOOL closeToBottom = distanceFromBottom < loadThreshold;
    if (self.showLoadNewerHeader && closeToBottom) {

        if (self.loadCoordinator.didLoadNewerRecently) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [weakSelf autoLoadMoreIfNecessary];
            });
            return NO;
        }

        [self.loadCoordinator loadNewerItems];
        return YES;
    }

    return NO;
}

- (BOOL)showLoadOlderHeader
{
    return self.loadCoordinator.showLoadOlderHeader;
}

- (BOOL)showLoadNewerHeader
{
    return self.loadCoordinator.showLoadNewerHeader;
}

#pragma mark - Bubble User Actions

- (void)handleTapOnFailedOrPendingDownloads:(TSMessage *)message
{
    OWSAssert(message);

    [self.attachmentDownloads downloadAttachmentsForMessageId:message.uniqueId
        attachmentGroup:AttachmentGroupAllAttachmentsIncoming
        downloadBehavior:AttachmentDownloadBehaviorBypassAll
        success:^(NSArray<TSAttachmentStream *> *attachmentStreams) {
            OWSLogInfo(@"Successfully redownloaded attachment in thread: %@", message.threadWithSneakyTransaction);
        }
        failure:^(NSError *error) { OWSLogWarn(@"Failed to redownload message with error: %@", error); }];
}

- (void)resendFailedOutgoingMessage:(TSOutgoingMessage *)message
{
    TSOutgoingMessage *messageToSend;

    // If the message was remotely deleted, resend a *delete* message
    // rather than the message itself.
    if (message.wasRemotelyDeleted) {
        messageToSend = [[TSOutgoingDeleteMessage alloc] initWithThread:self.thread message:message];
    } else {
        messageToSend = message;
    }

    NSArray<SignalServiceAddress *> *recipientsWithChangedSafetyNumber =
        [message failedRecipientAddressesWithErrorCode:OWSErrorCodeUntrustedIdentity];
    if (recipientsWithChangedSafetyNumber.count > 0) {
        // Show special safety number change dialog
        SafetyNumberConfirmationSheet *sheet = [[SafetyNumberConfirmationSheet alloc]
            initWithAddressesToConfirm:recipientsWithChangedSafetyNumber
                      confirmationText:MessageStrings.sendButton
                     completionHandler:^(BOOL didConfirm) {
                         if (didConfirm) {
                             DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                                 [self.messageSenderJobQueue addMessage:messageToSend.asPreparer
                                                            transaction:transaction];
                             });
                         }
                     }];
        [self presentViewController:sheet animated:YES completion:nil];
        return;
    }

    ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:nil
                                                                              message:message.mostRecentFailureText];

    [actionSheet addAction:[OWSActionSheets cancelAction]];

    ActionSheetAction *deleteMessageAction = [[ActionSheetAction alloc]
        initWithTitle:CommonStrings.deleteForMeButton
                style:ActionSheetActionStyleDestructive
              handler:^(ActionSheetAction *action) {
                  DatabaseStorageWrite(self.databaseStorage,
                      ^(SDSAnyWriteTransaction *transaction) { [message anyRemoveWithTransaction:transaction]; });
              }];
    [actionSheet addAction:deleteMessageAction];

    ActionSheetAction *resendMessageAction = [[ActionSheetAction alloc]
                  initWithTitle:NSLocalizedString(@"SEND_AGAIN_BUTTON", @"")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"send_again")
                          style:ActionSheetActionStyleDefault
                        handler:^(ActionSheetAction *action) {
                            DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                                [self.messageSenderJobQueue addMessage:messageToSend.asPreparer
                                                           transaction:transaction];
                            });
                        }];

    [actionSheet addAction:resendMessageAction];

    [self dismissKeyBoard];
    [self presentActionSheet:actionSheet];
}

#pragma mark -

- (void)presentMessageActions:(NSArray<MessageAction *> *)messageActions
              withFocusedCell:(UICollectionViewCell *)cell
                itemViewModel:(CVItemViewModelImpl *)itemViewModel
{
    MessageActionsViewController *messageActionsViewController =
        [[MessageActionsViewController alloc] initWithItemViewModel:itemViewModel
                                                        focusedView:cell
                                                            actions:messageActions];
    messageActionsViewController.delegate = self;

    self.messageActionsViewController = messageActionsViewController;

    [self setupMessageActionsStateForCell:cell];

    [messageActionsViewController presentOnWindow:self.view.window
        prepareConstraints:^{
            // In order to ensure the bottom bar remains above the keyboard, we pin it
            // to our bottom bar which follows the inputAccessoryView
            [messageActionsViewController.bottomBar autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.bottomBar];

            // We only want the message actions to show up over the detail view, in
            // the case where we are expanded. So match its edges to our nav controller.
            [messageActionsViewController.view autoPinToEdgesOfView:self.navigationController.view];
        }
        animateAlongside:^{ self.bottomBar.alpha = 0; }
        completion:nil];
}

- (void)updateMessageActionsStateForCell:(UIView *)cell
{
    // While presenting message actions, cache the original content offset.
    // This allows us to restore the user to their original scroll position
    // when they dismiss the menu.
    self.messageActionsOriginalContentOffset = self.collectionView.contentOffset;
    self.messageActionsOriginalFocusY = [self.view convertPoint:cell.frame.origin fromView:self.collectionView].y;
}

- (void)setupMessageActionsStateForCell:(UICollectionViewCell *)cell
{
    [self updateMessageActionsStateForCell:cell];

    // While the menu actions are presented, temporarily use extra content
    // inset padding so that interactions near the top or bottom of the
    // collection view can be scrolled anywhere within the viewport.
    // This allows us to keep the message position constant even when
    // messages dissappear above / below the focused message to the point
    // that we have less than one screen worth of content.
    CGSize navControllerSize = self.navigationController.view.frame.size;
    self.messageActionsExtraContentInsetPadding = MAX(navControllerSize.width, navControllerSize.height);

    UIEdgeInsets contentInset = self.collectionView.contentInset;
    contentInset.top += self.messageActionsExtraContentInsetPadding;
    contentInset.bottom += self.messageActionsExtraContentInsetPadding;
    self.collectionView.contentInset = contentInset;
}

- (void)clearMessageActionsState
{
    self.bottomBar.alpha = 1;

    UIEdgeInsets contentInset = self.collectionView.contentInset;
    contentInset.top -= self.messageActionsExtraContentInsetPadding;
    contentInset.bottom -= self.messageActionsExtraContentInsetPadding;
    self.collectionView.contentInset = contentInset;

    // TODO: This isn't safe. We should capture a token that represents scroll state.
    self.collectionView.contentOffset = self.messageActionsOriginalContentOffset;
    self.messageActionsOriginalContentOffset = CGPointZero;
    self.messageActionsExtraContentInsetPadding = 0;
    self.messageActionsViewController = nil;
}

- (BOOL)isPresentingMessageActions
{
    return self.messageActionsViewController != nil;
}

- (void)dismissMessageActionsAnimated:(BOOL)animated
{
    [self dismissMessageActionsAnimated:animated completion:^ {}];
}

- (void)dismissMessageActionsAnimated:(BOOL)animated completion:(void (^)(void))completion
{
    OWSLogVerbose(@"");

    if (!self.isPresentingMessageActions) {
        return;
    }

    if (animated) {
        [self.messageActionsViewController
            dismissAndAnimateAlongside:^{ self.bottomBar.alpha = 1; }
            completion:^{
                [self clearMessageActionsState];
                completion();
            }];
    } else {
        [self.messageActionsViewController dismissWithoutAnimating];
        [self clearMessageActionsState];
        completion();
    }
}

- (void)dismissMessageActionsIfNecessary
{
    if (self.shouldDismissMessageActions) {
        [self dismissMessageActionsAnimated:YES];
    }
}

- (BOOL)shouldDismissMessageActions
{
    if (!self.isPresentingMessageActions) {
        return NO;
    }
    NSString *_Nullable messageActionInteractionId = self.messageActionsViewController.focusedInteraction.uniqueId;
    if (messageActionInteractionId == nil) {
        return NO;
    }
    // Check whether there is still a view item for this interaction.
    return [self indexPathForInteractionUniqueId:messageActionInteractionId] == nil;
}

- (nullable NSValue *)targetContentOffsetForMessageActionInteraction
{
    OWSAssertDebug(self.messageActionsViewController);

    NSString *_Nullable messageActionInteractionId = self.messageActionsViewController.focusedInteraction.uniqueId;
    if (messageActionInteractionId == nil) {
        OWSFailDebug(@"Missing message action interaction.");
        return nil;
    }

    NSIndexPath *_Nullable indexPath = [self indexPathForInteractionUniqueId:messageActionInteractionId];
    if (indexPath == nil) {
        // This is expected if the menu action interaction is being deleted.
        return nil;
    }
    UICollectionViewLayoutAttributes *_Nullable layoutAttributes =
        [self.layout layoutAttributesForItemAtIndexPath:indexPath];
    if (layoutAttributes == nil) {
        OWSFailDebug(@"Missing layoutAttributes.");
        return nil;
    }
    CGRect cellFrame = layoutAttributes.frame;
    return [NSValue valueWithCGPoint:CGPointMake(0, cellFrame.origin.y - self.messageActionsOriginalFocusY)];
}

- (void)reloadReactionsDetailSheetWithTransaction:(SDSAnyReadTransaction *)transaction
{
    if (!self.reactionsDetailSheet) {
        return;
    }

    NSString *messageId = self.reactionsDetailSheet.messageId;

    NSIndexPath *_Nullable indexPath = [self indexPathForInteractionUniqueId:messageId];
    if (indexPath == nil) {
        // The message no longer exists, dismiss the sheet.
        [self dismissReactionsDetailSheetAnimated:YES];
    }

    CVRenderItem *_Nullable renderItem = [self renderItemForIndex:indexPath.row];

    InteractionReactionState *_Nullable reactionState = renderItem.reactionState;
    if (!reactionState.hasReactions) {
        // There are no longer reactions on this message, dismiss the sheet.
        [self dismissReactionsDetailSheetAnimated:YES];
        return;
    }

    // Update the detail sheet with the latest reaction
    // state, in case the reactions have changed.
    [self.reactionsDetailSheet setReactionState:reactionState transaction:transaction];
}

- (void)dismissReactionsDetailSheetAnimated:(BOOL)animated
{
    if (!self.reactionsDetailSheet) {
        return;
    }

    [self.reactionsDetailSheet dismissViewControllerAnimated:animated completion:^{ self.reactionsDetailSheet = nil; }];
}

- (void)presentAddThreadToProfileWhitelistWithSuccess:(void (^)(void))successHandler
{
    [[OWSProfileManager shared] presentAddThreadToProfileWhitelist:self.thread
                                                fromViewController:self
                                                           success:successHandler];
}

#pragma mark - CNContactViewControllerDelegate

- (void)contactViewController:(CNContactViewController *)viewController
       didCompleteWithContact:(nullable CNContact *)contact
{
    [self.navigationController popToViewController:self animated:YES];
}

#pragma mark - ContactsViewHelperObserver

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateNavigationTitle];
    [self.loadCoordinator enqueueReloadWithCanReuseInteractionModels:YES canReuseComponentStates:NO];
}

#pragma mark - Scroll Down Button

- (void)createConversationScrollButtons
{
    self.scrollDownButton = [[ConversationScrollButton alloc] initWithIconName:@"chevron-down-20"];
    [self.scrollDownButton addTarget:self
                              action:@selector(scrollDownButtonTapped)
                    forControlEvents:UIControlEventTouchUpInside];
    self.scrollDownButton.hidden = YES;
    self.scrollDownButton.alpha = 0;
    [self.view addSubview:self.scrollDownButton];
    [self.scrollDownButton autoSetDimension:ALDimensionWidth toSize:ConversationScrollButton.buttonSize];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _scrollDownButton);

    [self.scrollDownButton autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:self.bottomBar withOffset:-16];
    [self.scrollDownButton autoPinEdgeToSuperviewSafeArea:ALEdgeTrailing];

    self.scrollToNextMentionButton = [[ConversationScrollButton alloc] initWithIconName:@"mention-24"];
    [self.scrollToNextMentionButton addTarget:self
                                       action:@selector(scrollToNextMentionButtonTapped)
                             forControlEvents:UIControlEventTouchUpInside];
    self.scrollToNextMentionButton.hidden = YES;
    self.scrollToNextMentionButton.alpha = 0;
    [self.view addSubview:self.scrollToNextMentionButton];
    [self.scrollToNextMentionButton autoSetDimension:ALDimensionWidth toSize:ConversationScrollButton.buttonSize];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _scrollToNextMentionButton);

    [self.scrollToNextMentionButton autoPinEdge:ALEdgeBottom
                                         toEdge:ALEdgeTop
                                         ofView:self.scrollDownButton
                                     withOffset:-10];
    [self.scrollToNextMentionButton autoPinEdgeToSuperviewSafeArea:ALEdgeTrailing];
}

- (void)setUnreadMessageCount:(NSUInteger)unreadMessageCount
{
    OWSAssertIsOnMainThread();
    if (_unreadMessageCount != unreadMessageCount) {
        _unreadMessageCount = unreadMessageCount;
        [self configureScrollDownButtons];
    }
}

- (void)setUnreadMentionMessages:(nullable NSArray<TSMessage *> *)unreadMentionMessages
{
    OWSAssertIsOnMainThread();
    if (_unreadMentionMessages != unreadMentionMessages) {
        _unreadMentionMessages = unreadMentionMessages;
        [self configureScrollDownButtons];
    }
}

/// Checks to see if the unread message flag can be cleared. Shortcircuits if the flag is not set to begin with
- (void)clearUnreadMessageFlagIfNecessary
{
    OWSAssertIsOnMainThread();
    if (self.unreadMessageCount > 0) {
        [self updateUnreadMessageFlagUsingAsyncTransaction];
    }
}

- (void)updateUnreadMessageFlagUsingAsyncTransaction
{
    // Resubmits to the main queue because we can't verify we're not already in a transaction we don't know about.
    // This method may be called in response to all sorts of view state changes, e.g. scroll state. These changes
    // can be a result of a UIKit response to app activity that already has an open transaction.
    //
    // We need a transaction to proceed, but we can't verify that we're not already in one (unless explicitly handed
    // one) To workaround this, we async a block to open a fresh transaction on the main queue.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *newTransaction) {
            OWSAssertDebug(newTransaction);
            [self updateUnreadMessageFlagWithTransaction:newTransaction];
        }];
    });
}

- (void)updateUnreadMessageFlagWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertIsOnMainThread();
    InteractionFinder *interactionFinder = [[InteractionFinder alloc] initWithThreadUniqueId:self.thread.uniqueId];
    NSUInteger unreadCount = [interactionFinder unreadCountWithTransaction:transaction.unwrapGrdbRead];
    [self setUnreadMessageCount:unreadCount];

    self.unreadMentionMessages = [MentionFinder messagesMentioningWithAddress:self.tsAccountManager.localAddress
                                                                           in:self.thread
                                                          includeReadMessages:NO
                                                                  transaction:transaction.unwrapGrdbRead];
}

- (void)configureScrollDownButtons
{
    OWSAssertIsOnMainThread();

    if (!self.hasAppearedAndHasAppliedFirstLoad) {
        self.scrollDownButton.hidden = YES;
        self.scrollToNextMentionButton.hidden = YES;
        return;
    }

    CGFloat scrollSpaceToBottom = (self.safeContentHeight + self.collectionView.contentInset.bottom
        - (self.collectionView.contentOffset.y + self.collectionView.frame.size.height));
    CGFloat pageHeight = (self.collectionView.frame.size.height
        - (self.collectionView.contentInset.top + self.collectionView.contentInset.bottom));
    BOOL isScrolledUpOnePage = scrollSpaceToBottom > pageHeight * 1.f;

    BOOL hasLaterMessageOffscreen
        = ([self lastSortIdInLoadedWindow] > [self lastVisibleSortId]) || self.canLoadNewerItems;

    BOOL scrollDownWasHidden = self.isHidingScrollDownButton ? YES : self.scrollDownButton.hidden;
    BOOL scrollDownIsHidden = scrollDownWasHidden;

    BOOL scrollToNextMentionWasHidden
        = self.isHidingScrollToNextMentionButton ? YES : self.scrollToNextMentionButton.hidden;
    BOOL scrollToNextMentionIsHidden = scrollToNextMentionWasHidden;

    if (self.isInPreviewPlatter) {
        scrollDownIsHidden = YES;
        scrollToNextMentionIsHidden = YES;
    } else if (self.isPresentingMessageActions) {
        // Content offset calculations get messed up when we're presenting message actions
        // Don't change button visibility if we're presenting actions
        // no-op

    } else {
        BOOL shouldScrollDownAppear = isScrolledUpOnePage || hasLaterMessageOffscreen;
        scrollDownIsHidden = !shouldScrollDownAppear;

        BOOL shouldScrollToMentionAppear = shouldScrollDownAppear && self.unreadMentionMessages.count > 0;
        scrollToNextMentionIsHidden = !shouldScrollToMentionAppear;
    }

    BOOL scrollDownVisibilityDidChange = scrollDownIsHidden != scrollDownWasHidden;
    BOOL scrollToNextMentionVisibilityDidChange = scrollToNextMentionIsHidden != scrollToNextMentionWasHidden;
    BOOL shouldAnimateChanges = self.hasAppearedAndHasAppliedFirstLoad;

    if (scrollDownVisibilityDidChange || scrollToNextMentionVisibilityDidChange) {
        if (scrollDownVisibilityDidChange) {
            self.scrollDownButton.hidden = NO;
            self.isHidingScrollDownButton = scrollDownIsHidden;
            [self.scrollDownButton.layer removeAllAnimations];
        }
        if (scrollToNextMentionVisibilityDidChange) {
            self.scrollToNextMentionButton.hidden = NO;
            self.isHidingScrollToNextMentionButton = scrollToNextMentionIsHidden;
            [self.scrollToNextMentionButton.layer removeAllAnimations];
        }

        void (^alphaBlock)(void) = ^{
            if (scrollDownVisibilityDidChange) {
                self.scrollDownButton.alpha = scrollDownIsHidden ? 0 : 1;
            }
            if (scrollToNextMentionVisibilityDidChange) {
                self.scrollToNextMentionButton.alpha = scrollToNextMentionIsHidden ? 0 : 1;
            }
        };
        void (^completionBlock)(void) = ^{
            if (scrollDownVisibilityDidChange) {
                self.scrollDownButton.hidden = scrollDownIsHidden;
                self.isHidingScrollDownButton = NO;
            }
            if (scrollToNextMentionVisibilityDidChange) {
                self.scrollToNextMentionButton.hidden = scrollToNextMentionIsHidden;
                self.isHidingScrollToNextMentionButton = NO;
            }
        };

        if (shouldAnimateChanges) {
            [UIView animateWithDuration:0.2
                             animations:alphaBlock
                             completion:^(BOOL finished) {
                                 if (!finished) {
                                     return;
                                 }
                                 completionBlock();
                             }];
        } else {
            alphaBlock();
            completionBlock();
        }
    }

    self.scrollDownButton.unreadCount = self.unreadMessageCount;
    self.scrollToNextMentionButton.unreadCount = self.unreadMentionMessages.count;
}

#pragma mark - Attachment Picking: Contacts

- (void)chooseContactForSending
{
    ContactsPicker *contactsPicker = [[ContactsPicker alloc] initWithAllowsMultipleSelection:NO
                                                                            subtitleCellType:SubtitleCellValueNone];
    contactsPicker.contactsPickerDelegate = self;
    contactsPicker.title
        = NSLocalizedString(@"CONTACT_PICKER_TITLE", @"navbar title for contact picker when sharing a contact");

    OWSNavigationController *navigationController =
        [[OWSNavigationController alloc] initWithRootViewController:contactsPicker];
    [self dismissKeyBoard];
    [self presentFormSheetViewController:navigationController animated:YES completion:nil];
}

#pragma mark - Attachment Picking: Documents

- (void)showAttachmentDocumentPickerMenu
{
    ActionSheetController *actionSheet = [ActionSheetController new];

    ActionSheetAction *mediaAction = [[ActionSheetAction alloc]
        initWithTitle:NSLocalizedString(@"MEDIA_FROM_LIBRARY_BUTTON", @"media picker option to choose from library")
                style:ActionSheetActionStyleDefault
              handler:^(ActionSheetAction *action) { [self chooseFromLibraryAsDocument:YES]; }];
    [actionSheet addAction:mediaAction];

    ActionSheetAction *browseAction = [[ActionSheetAction alloc]
        initWithTitle:NSLocalizedString(@"BROWSE_FILES_BUTTON", @"browse files option from file sharing menu")
                style:ActionSheetActionStyleDefault
              handler:^(ActionSheetAction *action) { [self showDocumentPicker]; }];
    [actionSheet addAction:browseAction];

    [actionSheet addAction:OWSActionSheets.cancelAction];

    [self dismissKeyBoard];
    [self presentActionSheet:actionSheet];
}

- (void)showDocumentPicker
{
    NSString *allItems = (__bridge NSString *)kUTTypeItem;
    NSArray<NSString *> *documentTypes = @[ allItems ];

    // UIDocumentPickerModeImport copies to a temp file within our container.
    // It uses more memory than "open" but lets us avoid working with security scoped URLs.
    UIDocumentPickerMode pickerMode = UIDocumentPickerModeImport;

    UIDocumentPickerViewController *pickerController =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:documentTypes inMode:pickerMode];
    pickerController.delegate = self;

    [self dismissKeyBoard];
    [self presentFormSheetViewController:pickerController animated:YES completion:nil];
}

#pragma mark - Attachment Picking: GIFs

- (void)showGifPicker
{
    GifPickerNavigationViewController *gifModal = [GifPickerNavigationViewController new];
    gifModal.approvalDelegate = self;
    [self dismissKeyBoard];
    [self presentViewController:gifModal animated:YES completion:nil];
}

- (void)messageWasSent:(TSOutgoingMessage *)message
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(message);

    if (SSKDebugFlags.internalLogging) {
        OWSLogInfo(@"");
    }

    self.lastMessageSentDate = [NSDate new];

    [self.loadCoordinator clearUnreadMessagesIndicator];
    self.inputToolbar.quotedReply = nil;

    if ([Environment.shared.preferences soundInForeground]) {
        SystemSoundID soundId = [OWSSounds systemSoundIDForSound:OWSStandardSound_MessageSent quiet:YES];
        AudioServicesPlaySystemSound(soundId);
    }
    [self.typingIndicators didSendOutgoingMessageInThread:self.thread];
}

#pragma mark UIDocumentMenuDelegate

- (void)documentMenu:(UIDocumentMenuViewController *)documentMenu
    didPickDocumentPicker:(UIDocumentPickerViewController *)documentPicker
{
    documentPicker.delegate = self;

    [self dismissKeyBoard];
    [self presentFormSheetViewController:documentPicker animated:YES completion:nil];
}

#pragma mark UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url
{
    OWSLogDebug(@"Picked document at url: %@", url);

    NSString *type;
    NSError *typeError;
    [url getResourceValue:&type forKey:NSURLTypeIdentifierKey error:&typeError];
    if (typeError) {
        OWSFailDebug(@"Determining type of picked document at url: %@ failed with error: %@", url, typeError);
    }
    if (!type) {
        OWSFailDebug(@"falling back to default filetype for picked document at url: %@", url);
        type = (__bridge NSString *)kUTTypeData;
    }

    NSNumber *isDirectory;
    NSError *isDirectoryError;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&isDirectoryError];
    if (isDirectoryError) {
        OWSFailDebug(@"Determining if picked document was a directory failed with error: %@", isDirectoryError);
    } else if ([isDirectory boolValue]) {
        OWSLogInfo(@"User picked directory.");

        dispatch_async(dispatch_get_main_queue(), ^{
            [OWSActionSheets
                showActionSheetWithTitle:
                    NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_TITLE",
                        @"Alert title when picking a document fails because user picked a directory/bundle")
                                 message:NSLocalizedString(
                                             @"ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_BODY",
                                             @"Alert body when picking a document fails because user picked a "
                                             @"directory/bundle")];
        });
        return;
    }

    NSString *filename = url.lastPathComponent;
    if (!filename) {
        OWSFailDebug(@"Unable to determine filename");
        filename = NSLocalizedString(
            @"ATTACHMENT_DEFAULT_FILENAME", @"Generic filename for an attachment with no known name");
    }

    OWSAssertDebug(type);
    OWSAssertDebug(filename);
    NSError *error;
    _Nullable id<DataSource> dataSource = [DataSourcePath dataSourceWithURL:url
                                                 shouldDeleteOnDeallocation:NO
                                                                      error:&error];
    if (dataSource == nil) {
        OWSFailDebug(@"error: %@", error);

        dispatch_async(dispatch_get_main_queue(), ^{
            [OWSActionSheets
                showActionSheetWithTitle:NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_FAILED_ALERT_TITLE",
                                             @"Alert title when picking a document fails for an unknown reason")];
        });
        return;
    }

    [dataSource setSourceFilename:filename];

    // Although we want to be able to send higher quality attachments through the document picker
    // it's more important that we ensure the sent format is one all clients can accept (e.g. *not* quicktime .mov)
    if ([SignalAttachment isVideoThatNeedsCompressionWithDataSource:dataSource dataUTI:type]) {
        [self showApprovalDialogAfterProcessingVideoURL:url filename:filename];
        return;
    }

    // "Document picker" attachments _SHOULD NOT_ be resized, if possible.
    SignalAttachment *attachment = [SignalAttachment attachmentWithDataSource:dataSource
                                                                      dataUTI:type
                                                                 imageQuality:TSImageQualityOriginal];
    [self showApprovalDialogForAttachment:attachment];
}

#pragma mark - Media Libary

- (void)takePictureOrVideo
{
    [BenchManager startEventWithTitle:@"Show-Camera" eventId:@"Show-Camera"];
    [self ows_askForCameraPermissions:^(BOOL cameraGranted) {
        if (!cameraGranted) {
            OWSLogWarn(@"camera permission denied.");
            return;
        }
        [self ows_askForMicrophonePermissions:^(BOOL micGranted) {
            if (!micGranted) {
                OWSLogWarn(@"proceeding, though mic permission denied.");
                // We can still continue without mic permissions, but any captured video will
                // be silent.
            }

            SendMediaNavigationController *pickerModal = [SendMediaNavigationController showingCameraFirst];
            pickerModal.sendMediaNavDelegate = self;
            pickerModal.modalPresentationStyle = UIModalPresentationOverFullScreen;

            [self dismissKeyBoard];
            [self presentViewController:pickerModal animated:YES completion:nil];
        }];
    }];
}

- (void)chooseFromLibraryAsMedia
{
    OWSAssertIsOnMainThread();

    [self chooseFromLibraryAsDocument:NO];
}

- (void)chooseFromLibraryAsDocument:(BOOL)shouldTreatAsDocument
{
    OWSAssertIsOnMainThread();

    [BenchManager startEventWithTitle:@"Show-Media-Library" eventId:@"Show-Media-Library"];

    [self ows_askForMediaLibraryPermissions:^(BOOL granted) {
        if (!granted) {
            OWSLogWarn(@"Media Library permission denied.");
            return;
        }

        SendMediaNavigationController *pickerModal;
        if (shouldTreatAsDocument) {
            pickerModal = [SendMediaNavigationController asMediaDocumentPicker];
        } else {
            pickerModal = [SendMediaNavigationController showingMediaLibraryFirst];
        }

        pickerModal.sendMediaNavDelegate = self;

        [self dismissKeyBoard];
        [self presentFullScreenViewController:pickerModal animated:YES completion:nil];
    }];
}

#pragma mark - SendMediaNavDelegate

- (void)sendMediaNavDidCancel:(SendMediaNavigationController *)sendMediaNavigationController
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)sendMediaNav:(SendMediaNavigationController *)sendMediaNavigationController
    didApproveAttachments:(NSArray<SignalAttachment *> *)attachments
              messageBody:(nullable MessageBody *)messageBody
{
    [self tryToSendAttachments:attachments messageBody:messageBody];
    [self.inputToolbar clearTextMessageAnimated:NO];

    // we want to already be at the bottom when the user returns, rather than have to watch
    // the new message scroll into view.
    [self scrollToBottomOfConversationAnimated:NO];

    [self dismissViewControllerAnimated:YES completion:nil];
}

- (nullable MessageBody *)sendMediaNavInitialMessageBody:(SendMediaNavigationController *)sendMediaNavigationController
{
    return self.inputToolbar.messageBody;
}

- (void)sendMediaNav:(SendMediaNavigationController *)sendMediaNavigationController
    didChangeMessageBody:(nullable MessageBody *)messageBody
{
    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    [self.inputToolbar setMessageBody:messageBody animated:NO];
}

- (NSString *)sendMediaNavApprovalButtonImageName
{
    return @"send-solid-24";
}

- (BOOL)sendMediaNavCanSaveAttachments
{
    return YES;
}

- (nullable NSString *)sendMediaNavTextInputContextIdentifier
{
    return self.textInputContextIdentifier;
}

- (NSArray<NSString *> *)sendMediaNavRecipientNames
{
    return @[ [self.contactsManager displayNameForThreadWithSneakyTransaction:self.thread] ];
}

- (NSArray<SignalServiceAddress *> *)sendMediaNavMentionableAddresses
{
    if (!self.supportsMentions) {
        return @[];
    }

    return self.thread.recipientAddresses;
}

#pragma mark -

- (void)sendContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(contactShare);

    OWSLogVerbose(@"Sending contact share.");

    __block BOOL didAddToProfileWhitelist;
    TSThread *thread = self.thread;
    DatabaseStorageAsyncWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
        didAddToProfileWhitelist = [ThreadUtil addThreadToProfileWhitelistIfEmptyOrPendingRequest:thread
                                                                                      transaction:transaction];

        // TODO - in line with QuotedReply and other message attachments, saving should happen as part of sending
        // preparation rather than duplicated here and in the SAE
        if (contactShare.avatarImage) {
            [contactShare.dbRecord saveAvatarImage:contactShare.avatarImage transaction:transaction];
        }

        [transaction addAsyncCompletion:^{
            TSOutgoingMessage *message = [ThreadUtil enqueueMessageWithContactShare:contactShare.dbRecord
                                                                             thread:thread];
            [self messageWasSent:message];

            if (didAddToProfileWhitelist) {
                [self ensureBannerState];
            }
        }];
    });
}

- (void)showApprovalDialogAfterProcessingVideoURL:(NSURL *)movieURL filename:(nullable NSString *)filename
{
    OWSAssertIsOnMainThread();

    [ModalActivityIndicatorViewController
        presentFromViewController:self
                        canCancel:YES
                  backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                      NSError *dataSourceError;
                      id<DataSource> dataSource = [DataSourcePath dataSourceWithURL:movieURL
                                                         shouldDeleteOnDeallocation:NO
                                                                              error:&dataSourceError];
                      if (dataSourceError != nil) {
                          [self showErrorAlertForAttachment:nil];
                          return;
                      }

                      dataSource.sourceFilename = filename;
                      VideoCompressionResult *compressionResult =
                          [SignalAttachment compressVideoAsMp4WithDataSource:dataSource
                                                                     dataUTI:(NSString *)kUTTypeMPEG4];

                      compressionResult.attachmentPromise
                          .then(^(SignalAttachment *attachment) {
                              OWSAssertIsOnMainThread();
                              OWSAssertDebug([attachment isKindOfClass:[SignalAttachment class]]);

                              if (modalActivityIndicator.wasCancelled) {
                                  return;
                              }

                              [modalActivityIndicator dismissWithCompletion:^{
                                  if (!attachment || [attachment hasError]) {
                                      OWSLogError(@"Invalid attachment: %@.",
                                          attachment ? [attachment errorName] : @"Missing data");
                                      [self showErrorAlertForAttachment:attachment];
                                  } else {
                                      [self showApprovalDialogForAttachment:attachment];
                                  }
                              }];
                          })
                          .catch(^(NSError *error) {
                              OWSLogError(@"Error: %@.", error);
                              [self showErrorAlertForAttachment:nil];
                          });
                  }];
}

#pragma mark - Audio

- (void)requestRecordingVoiceMemo
{
    OWSAssertIsOnMainThread();

    NSUUID *voiceMessageUUID = [NSUUID UUID];
    self.voiceMessageUUID = voiceMessageUUID;

    __weak typeof(self) weakSelf = self;
    [self ows_askForMicrophonePermissions:^(BOOL granted) {
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (strongSelf.voiceMessageUUID != voiceMessageUUID) {
            // This voice message recording has been cancelled
            // before recording could begin.
            return;
        }

        if (granted) {
            [strongSelf startRecordingVoiceMemo];
        } else {
            OWSLogInfo(@"we do not have recording permission.");
            [strongSelf cancelVoiceMemo];
            [self ows_showNoMicrophonePermissionActionSheet];
        }
    }];
}

- (void)startRecordingVoiceMemo
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"startRecordingVoiceMemo");

    // Cancel any ongoing audio playback.
    [self.audioPlayer stopAll];

    NSString *temporaryDirectory = OWSTemporaryDirectory();
    NSString *filename = [NSString stringWithFormat:@"%lld.m4a", [NSDate ows_millisecondTimeStamp]];
    NSString *filepath = [temporaryDirectory stringByAppendingPathComponent:filename];
    NSURL *fileURL = [NSURL fileURLWithPath:filepath];

    // Setup audio session
    BOOL configuredAudio = [self.audioSession startAudioActivity:self.recordVoiceNoteAudioActivity];
    if (!configuredAudio) {
        OWSFailDebug(@"Couldn't configure audio session");
        [self cancelVoiceMemo];
        return;
    }

    NSError *error;
    // Initiate and prepare the recorder
    self.audioRecorder = [[AVAudioRecorder alloc] initWithURL:fileURL
                                                     settings:@{
                                                         AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                                         AVSampleRateKey : @(44100),
                                                         AVNumberOfChannelsKey : @(2),
                                                         AVEncoderBitRateKey : @(128 * 1024),
                                                     }
                                                        error:&error];
    if (error) {
        OWSFailDebug(@"Couldn't create audioRecorder: %@", error);
        [self cancelVoiceMemo];
        return;
    }

    self.audioRecorder.meteringEnabled = YES;

    if (![self.audioRecorder prepareToRecord]) {
        OWSFailDebug(@"audioRecorder couldn't prepareToRecord.");
        [self cancelVoiceMemo];
        return;
    }

    if (![self.audioRecorder record]) {
        OWSFailDebug(@"audioRecorder couldn't record.");
        [self cancelVoiceMemo];
        return;
    }
}

- (void)endRecordingVoiceMemo
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"endRecordingVoiceMemo");

    self.voiceMessageUUID = nil;

    if (!self.audioRecorder) {
        // No voice message recording is in progress.
        // We may be cancelling before the recording could begin.
        OWSLogError(@"Missing audioRecorder");
        return;
    }

    NSTimeInterval durationSeconds = self.audioRecorder.currentTime;

    [self stopRecording];

    const NSTimeInterval kMinimumRecordingTimeSeconds = 1.f;
    if (durationSeconds < kMinimumRecordingTimeSeconds) {
        OWSLogInfo(@"Discarding voice message; too short.");
        self.audioRecorder = nil;

        [self dismissKeyBoard];

        [OWSActionSheets
            showActionSheetWithTitle:
                NSLocalizedString(@"VOICE_MESSAGE_TOO_SHORT_ALERT_TITLE",
                    @"Title for the alert indicating the 'voice message' needs to be held to be held down to record.")
                             message:NSLocalizedString(@"VOICE_MESSAGE_TOO_SHORT_ALERT_MESSAGE",
                                         @"Message for the alert indicating the 'voice message' needs to be held to be "
                                         @"held "
                                         @"down to record.")];
        return;
    }

    NSError *error;
    _Nullable id<DataSource> dataSource = [DataSourcePath dataSourceWithURL:self.audioRecorder.url
                                                 shouldDeleteOnDeallocation:YES
                                                                      error:&error];
    self.audioRecorder = nil;

    if (error != nil) {
        OWSFailDebug(@"Couldn't load audioRecorder data: %@", error);
        self.audioRecorder = nil;
        return;
    }

    NSString *filename = [NSString stringWithFormat:@"%@ %@.%@",
                                   NSLocalizedString(@"VOICE_MESSAGE_FILE_NAME", @"Filename for voice messages."),
                                   [NSDateFormatter localizedStringFromDate:[NSDate new]
                                                                  dateStyle:NSDateFormatterShortStyle
                                                                  timeStyle:NSDateFormatterShortStyle],
                                   @"m4a"];
    [dataSource setSourceFilename:filename];
    SignalAttachment *attachment =
        [SignalAttachment voiceMessageAttachmentWithDataSource:dataSource dataUTI:(NSString *)kUTTypeMPEG4Audio];
    OWSLogVerbose(@"voice memo duration: %f, file size: %zd", durationSeconds, [dataSource dataLength]);
    if (!attachment || [attachment hasError]) {
        OWSLogWarn(@"Invalid attachment: %@.", attachment ? [attachment errorName] : @"Missing data");
        [self showErrorAlertForAttachment:attachment];
    } else {
        [self tryToSendAttachments:@[ attachment ] messageBody:nil];
    }
}

- (void)stopRecording
{
    [self.audioRecorder stop];
    [self.audioSession endAudioActivity:self.recordVoiceNoteAudioActivity];
}

- (void)cancelRecordingVoiceMemo
{
    OWSAssertIsOnMainThread();
    OWSLogDebug(@"cancelRecordingVoiceMemo");

    [self stopRecording];
    self.audioRecorder = nil;
    self.voiceMessageUUID = nil;
}

- (void)setAudioRecorder:(nullable AVAudioRecorder *)audioRecorder
{
    // Prevent device from sleeping while recording a voice message.
    if (audioRecorder) {
        [DeviceSleepManager.shared addBlockWithBlockObject:audioRecorder];
    } else if (_audioRecorder) {
        [DeviceSleepManager.shared removeBlockWithBlockObject:_audioRecorder];
    }

    _audioRecorder = audioRecorder;
}

#pragma mark Accessory View

- (void)cameraButtonPressed
{
    OWSAssertIsOnMainThread();

    [self takePictureOrVideo];
}

- (void)galleryButtonPressed
{
    OWSAssertIsOnMainThread();

    [self chooseFromLibraryAsMedia];
}

- (void)gifButtonPressed
{
    OWSAssertIsOnMainThread();

    [self showGifPicker];
}

- (void)fileButtonPressed
{
    OWSAssertIsOnMainThread();

    [self showAttachmentDocumentPickerMenu];
}

- (void)contactButtonPressed
{
    OWSAssertIsOnMainThread();

    [self chooseContactForSending];
}

- (void)locationButtonPressed
{
    OWSAssertIsOnMainThread();

    LocationPicker *locationPicker = [LocationPicker new];
    locationPicker.delegate = self;

    OWSNavigationController *navigationController =
        [[OWSNavigationController alloc] initWithRootViewController:locationPicker];
    [self dismissKeyBoard];
    [self presentFormSheetViewController:navigationController animated:YES completion:nil];
}

- (void)didSelectRecentPhotoWithAsset:(PHAsset *)asset attachment:(SignalAttachment *)attachment
{
    OWSAssertIsOnMainThread();

    [self dismissKeyBoard];

    SendMediaNavigationController *pickerModal =
        [SendMediaNavigationController showingApprovalWithPickedLibraryMediaAsset:asset
                                                                       attachment:attachment
                                                                         delegate:self];

    [self presentFullScreenViewController:pickerModal animated:true completion:nil];
}

- (void)setLastSortIdMarkedRead:(uint64_t)lastSortIdMarkedRead
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.isMarkingAsRead);
    _lastSortIdMarkedRead = lastSortIdMarkedRead;
}

- (void)markVisibleMessagesAsRead
{
    OWSAssertIsOnMainThread();
    if (self.presentedViewController) {
        return;
    }
    if (OWSWindowManager.shared.shouldShowCallView) {
        return;
    }
    if (self.navigationController.topViewController != self) {
        return;
    }

    // Always clear the thread unread flag
    [self clearThreadUnreadFlagIfNecessary];

    uint64_t lastVisibleSortId = [self lastVisibleSortId];
    BOOL isShowingUnreadMessage = (lastVisibleSortId > [self lastSortIdMarkedRead]);
    if (!self.isMarkingAsRead && isShowingUnreadMessage) {
        self.isMarkingAsRead = YES;
        [self clearUnreadMessageFlagIfNecessary];

        [BenchManager benchAsyncWithTitle:@"marking as read"
                                    block:^(void (^_Nonnull benchCompletion)(void)) {
                                        [[OWSReadReceiptManager shared]
                                            markAsReadLocallyBeforeSortId:lastVisibleSortId
                                                                   thread:self.thread
                                                 hasPendingMessageRequest:self.threadViewModel.hasPendingMessageRequest
                                                               completion:^{
                                                                   OWSAssertIsOnMainThread();
                                                                   [self setLastSortIdMarkedRead:lastVisibleSortId];
                                                                   self.isMarkingAsRead = NO;

                                                                   // If -markVisibleMessagesAsRead wasn't invoked on a
                                                                   // timer, we'd want to double check that the current
                                                                   // -lastVisibleSortId hasn't incremented since we
                                                                   // started the read receipt request. But we have a
                                                                   // timer, so if it has changed, this method will just
                                                                   // be reinvoked in <100ms.

                                                                   benchCompletion();
                                                               }];
                                    }];
    }
}

- (void)conversationSettingsDidUpdate
{
    OWSAssertIsOnMainThread();

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        // We updated the group, so if there was a pending message request we should accept it.
        [ThreadUtil addThreadToProfileWhitelistIfEmptyOrPendingRequest:self.thread transaction:transaction];
    });
}

#pragma mark - Drafts

- (void)saveDraft
{
    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    if (!self.inputToolbar.hidden) {
        TSThread *thread = self.thread;
        MessageBody *currentDraft = [self.inputToolbar messageBody];

        DatabaseStorageAsyncWrite(self.databaseStorage,
            ^(SDSAnyWriteTransaction *transaction) { [thread updateWithDraft:currentDraft transaction:transaction]; });
    }
}

#pragma mark - ConversationHeaderViewDelegate

- (void)didTapConversationHeaderView:(ConversationHeaderView *)conversationHeaderView
{
    [self showConversationSettings];
}

#ifdef USE_DEBUG_UI
- (void)navigationTitleLongPressed:(UIGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        [DebugUITableViewController presentDebugUIForThread:self.thread fromViewController:self];
    }
}
#endif

#pragma mark - ConversationInputTextViewDelegate

- (void)textViewDidChange:(UITextView *)textView
{
    if (textView.text.length > 0) {
        [self.typingIndicators didStartTypingOutgoingInputInThread:self.thread];
    }
}

- (void)inputTextViewSendMessagePressed
{
    [self sendButtonPressed];
}

- (void)didPasteAttachment:(SignalAttachment *_Nullable)attachment
{
    // If the thing we pasted is sticker-like, send it immediately
    // and render it borderless.
    if (attachment.isBorderless) {
        [self tryToSendAttachments:@[ attachment ] messageBody:nil];
    } else {
        [self showApprovalDialogForAttachment:attachment];
    }
}

- (void)showApprovalDialogForAttachment:(SignalAttachment *_Nullable)attachment
{
    if (attachment == nil) {
        OWSFailDebug(@"attachment was unexpectedly nil");
        [self showErrorAlertForAttachment:nil];
        return;
    }
    [self showApprovalDialogForAttachments:@[ attachment ]];
}

- (void)showApprovalDialogForAttachments:(NSArray<SignalAttachment *> *)attachments
{
    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    OWSNavigationController *modal =
        [AttachmentApprovalViewController wrappedInNavControllerWithAttachments:attachments
                                                             initialMessageBody:self.inputToolbar.messageBody
                                                               approvalDelegate:self];

    [self presentFullScreenViewController:modal animated:YES completion:nil];
}

- (void)tryToSendAttachments:(NSArray<SignalAttachment *> *)attachments messageBody:(MessageBody *_Nullable)messageBody
{
    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    DispatchMainThreadSafe(^{
        __weak ConversationViewController *weakSelf = self;
        if ([self isBlockedConversation]) {
            [self showUnblockConversationUI:^(BOOL isBlocked) {
                if (!isBlocked) {
                    [weakSelf tryToSendAttachments:attachments messageBody:messageBody];
                }
            }];
            return;
        }

        BOOL didShowSNAlert =
            [self showSafetyNumberConfirmationIfNecessaryWithConfirmationText:[SafetyNumberStrings confirmSendButton]
                                                                   completion:^(BOOL didConfirmIdentity) {
                                                                       if (didConfirmIdentity) {
                                                                           [weakSelf tryToSendAttachments:attachments
                                                                                              messageBody:messageBody];
                                                                       }
                                                                   }];
        if (didShowSNAlert) {
            return;
        }

        for (SignalAttachment *attachment in attachments) {
            if ([attachment hasError]) {
                OWSLogWarn(@"Invalid attachment: %@.", attachment ? [attachment errorName] : @"Missing data");
                [self showErrorAlertForAttachment:attachment];
                return;
            }
        }

        BOOL didAddToProfileWhitelist =
            [ThreadUtil addThreadToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction:self.thread];

        __block TSOutgoingMessage *message;
        [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
            message = [ThreadUtil enqueueMessageWithBody:messageBody
                                        mediaAttachments:attachments
                                                  thread:self.thread
                                        quotedReplyModel:self.inputToolbar.quotedReply
                                        linkPreviewDraft:nil
                                             transaction:transaction];
        }];

        [self messageWasSent:message];

        if (didAddToProfileWhitelist) {
            [self ensureBannerState];
        }
    });
}

- (void)updateThemeIfNecessary
{
    OWSAssertIsOnMainThread();

    if (self.isDarkThemeEnabled == Theme.isDarkThemeEnabled) {
        return;
    }
    self.isDarkThemeEnabled = Theme.isDarkThemeEnabled;

    [self applyTheme];

    [self updateConversationStyle];
}

- (void)applyTheme
{
    OWSAssertIsOnMainThread();

    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return;
    }

    // make sure toolbar extends below iPhoneX home button.
    self.view.backgroundColor = Theme.toolbarBackgroundColor;
    self.collectionView.backgroundColor = Theme.backgroundColor;

    [self updateNavigationTitle];
    [self updateNavigationBarSubtitleLabel];

    [self updateInputToolbar];
    [self updateInputToolbarLayout];
    [self updateBarButtonItems];
    [self ensureBannerState];

    // Re-styling the message actions is tricky,
    // since this happens rarely just dismiss
    [self dismissMessageActionsAnimated:NO];
    [self dismissReactionsDetailSheetAnimated:NO];
}

- (void)reloadCollectionView
{
    if (!self.hasAppearedAndHasAppliedFirstLoad) {
        return;
    }
    @try {
        [self.collectionView reloadData];
        [self.layout invalidateLayout];
    } @catch (NSException *exception) {
        OWSLogWarn(@"currentRenderStateDebugDescription: %@", self.currentRenderStateDebugDescription);
        OWSFailDebug(@"exception: %@ of type: %@ with reason: %@, user info: %@.",
            exception.description,
            exception.name,
            exception.reason,
            exception.userInfo);
        @throw exception;
    }
}

#pragma mark - AttachmentApprovalViewControllerDelegate

- (void)attachmentApprovalDidAppear:(AttachmentApprovalViewController *)attachmentApproval
{
    // no-op
}

- (void)attachmentApproval:(AttachmentApprovalViewController *)attachmentApproval
     didApproveAttachments:(NSArray<SignalAttachment *> *)attachments
               messageBody:(MessageBody *_Nullable)messageBody
{
    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    [self tryToSendAttachments:attachments messageBody:messageBody];
    [self.inputToolbar clearTextMessageAnimated:NO];
    [self dismissViewControllerAnimated:YES completion:nil];

    // We always want to scroll to the bottom of the conversation after the local user
    // sends a message.  Normally, this is taken care of in yapDatabaseModified:, but
    // we don't listen to db modifications when this view isn't visible, i.e. when the
    // attachment approval view is presented.
    [self scrollToBottomOfConversationAnimated:NO];
}

- (void)attachmentApprovalDidCancel:(AttachmentApprovalViewController *)attachmentApproval
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)attachmentApproval:(AttachmentApprovalViewController *)attachmentApproval
      didChangeMessageBody:(nullable MessageBody *)newMessageBody
{
    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    [self.inputToolbar setMessageBody:newMessageBody animated:NO];
}

- (nullable NSString *)attachmentApprovalTextInputContextIdentifier
{
    return self.textInputContextIdentifier;
}

- (NSArray<NSString *> *)attachmentApprovalRecipientNames
{
    return @[ [self.contactsManager displayNameForThreadWithSneakyTransaction:self.thread] ];
}

- (NSArray<SignalServiceAddress *> *)attachmentApprovalMentionableAddresses
{
    if (!self.supportsMentions) {
        return @[];
    }

    return self.thread.recipientAddresses;
}

#pragma mark -

- (void)showErrorAlertForAttachment:(SignalAttachment *_Nullable)attachment
{
    OWSAssertDebug(attachment == nil || [attachment hasError]);

    NSString *errorMessage
        = (attachment ? [attachment localizedErrorDescription] : [SignalAttachment missingDataErrorMessage]);

    OWSLogError(@": %@", errorMessage);

    [OWSActionSheets showActionSheetWithTitle:NSLocalizedString(@"ATTACHMENT_ERROR_ALERT_TITLE",
                                                  @"The title of the 'attachment error' alert.")
                                      message:errorMessage];
}

- (CGFloat)safeContentHeight
{
    // Don't use self.collectionView.contentSize.height as the collection view's
    // content size might not be set yet.
    //
    // We can safely call prepareLayout to ensure the layout state is up-to-date
    // since our layout uses a dirty flag internally to debounce redundant work.
    return [self.collectionView.collectionViewLayout collectionViewContentSize].height;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    // Constantly try to update the lastKnownDistanceFromBottom.
    [self updateLastKnownDistanceFromBottom];

    [self configureScrollDownButtons];

    [self scheduleScrollUpdateTimer];
}

- (void)scheduleScrollUpdateTimer
{
    OWSAssertIsOnMainThread();

    if (self.scrollUpdateTimer != nil) {
        return;
    }

    OWSLogVerbose(@"");

    // We need to manually schedule this timer using NSRunLoopCommonModes
    // or it won't fire during scrolling.
    self.scrollUpdateTimer = [NSTimer weakTimerWithTimeInterval:0.1f
                                                         target:self
                                                       selector:@selector(scrollUpdateTimerDidFire)
                                                       userInfo:nil
                                                        repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:self.scrollUpdateTimer forMode:NSRunLoopCommonModes];
}

- (void)scrollUpdateTimerDidFire
{
    OWSAssertIsOnMainThread();

    [self.scrollUpdateTimer invalidate];
    self.scrollUpdateTimer = nil;

    if (!self.viewHasEverAppeared) {
        return;
    }

    [self autoLoadMoreIfNecessary];

    if (!self.isUserScrolling) {
        [self saveLastVisibleSortIdAndOnScreenPercentage];
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    self.userHasScrolled = YES;
    self.isUserScrolling = YES;
    [self scrollingAnimationDidStart];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)willDecelerate
{
    if (!willDecelerate) {
        [self scrollingAnimationDidComplete];
    }

    if (!self.isUserScrolling) {
        return;
    }

    self.isUserScrolling = NO;

    if (willDecelerate) {
        self.isWaitingForDeceleration = willDecelerate;
    } else {
        [self scheduleScrollUpdateTimer];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    [self scrollingAnimationDidComplete];

    if (!self.isWaitingForDeceleration) {
        return;
    }

    self.isWaitingForDeceleration = NO;

    [self scheduleScrollUpdateTimer];
}

- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView
{

    [self scrollingAnimationDidStart];

    return YES;
}

- (void)scrollViewDidScrollToTop:(UIScrollView *)scrollView
{
    [self scrollingAnimationDidComplete];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
    [self scrollingAnimationDidComplete];
}

#pragma mark - ConversationCollectionViewDelegate

- (void)collectionViewWillChangeSizeFrom:(CGSize)oldSize to:(CGSize)newSize
{
    OWSAssertIsOnMainThread();
}

- (void)collectionViewDidChangeSizeFrom:(CGSize)oldSize to:(CGSize)newSize
{
    OWSAssertIsOnMainThread();

    if (oldSize.width != newSize.width) {
        [self resetForSizeOrOrientationChange];
    }
}

- (void)collectionViewWillAnimate
{
    [self scrollingAnimationDidStart];
}

- (void)scrollingAnimationDidStart
{
    OWSAssertIsOnMainThread();

    // scrollingAnimationStartDate blocks landing of loads, so we must ensure
    // that it is always cleared in a timely way, even if the animation
    // is cancelled. Wait no more than N seconds.
    [self.scrollingAnimationCompletionTimer invalidate];
    self.scrollingAnimationCompletionTimer =
        [NSTimer weakScheduledTimerWithTimeInterval:5
                                             target:self
                                           selector:@selector(scrollingAnimationCompletionTimerDidFire:)
                                           userInfo:nil
                                            repeats:NO];
}

- (void)scrollingAnimationCompletionTimerDidFire:(NSTimer *)timer
{
    OWSAssertIsOnMainThread();

    OWSFailDebug(@"Scrolling animation did not complete in a timely way.");

    // scrollingAnimationCompletionTimer should already have been cleared,
    // but we need to ensure that it is cleared in a timely way.
    [self scrollingAnimationDidComplete];
}

- (void)scrollingAnimationDidComplete
{
    OWSAssertIsOnMainThread();

    [self.scrollingAnimationCompletionTimer invalidate];
    self.scrollingAnimationCompletionTimer = nil;

    [self autoLoadMoreIfNecessary];
}

#pragma mark - ConversationSettingsViewDelegate

- (void)conversationColorWasUpdated
{
    [self updateConversationStyle];
    [self.headerView updateAvatar];
}

- (void)popAllConversationSettingsViewsWithCompletion:(void (^_Nullable)(void))completionBlock
{
    if (self.presentedViewController) {
        [self.presentedViewController dismissViewControllerAnimated:YES
                                                         completion:^{
                                                             [self.navigationController
                                                                 popToViewController:self
                                                                            animated:YES
                                                                          completion:completionBlock];
                                                         }];
    } else {
        [self.navigationController popToViewController:self animated:YES completion:completionBlock];
    }
}

#pragma mark - Conversation Search

- (void)conversationSettingsDidRequestConversationSearch
{
    self.uiMode = ConversationUIMode_Search;
    [self popAllConversationSettingsViewsWithCompletion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.searchController.uiSearchController.searchBar becomeFirstResponder];
        });
    }];
}

#pragma mark ConversationSearchControllerDelegate

- (void)didDismissSearchController:(UISearchController *)searchController
{
    OWSLogVerbose(@"");
    OWSAssertIsOnMainThread();
    // This method is called not only when the user taps "cancel" in the searchController, but also
    // called when the searchController was dismissed because we switched to another uiMode, like
    // "selection". We only want to revert to "normal" in the former case - when the user tapped
    // "cancel" in the search controller. Otherwise, if we're already in another mode, like
    // "selection", we want to stay in that mode.
    if (self.uiMode == ConversationUIMode_Search) {
        self.uiMode = ConversationUIMode_Normal;
    }
}

- (void)conversationSearchController:(ConversationSearchController *)conversationSearchController
              didUpdateSearchResults:(nullable ConversationScreenSearchResultSet *)conversationScreenSearchResultSet
{
    OWSAssertIsOnMainThread();

    OWSLogVerbose(@"conversationScreenSearchResultSet: %@", conversationScreenSearchResultSet.debugDescription);
    self.lastSearchedText = conversationScreenSearchResultSet.searchText;
    [self.loadCoordinator enqueueReload];
    if (conversationScreenSearchResultSet) {
        [BenchManager completeEventWithEventId:self.lastSearchedText];
    }
}

- (void)conversationSearchController:(ConversationSearchController *)conversationSearchController
                  didSelectMessageId:(NSString *)messageId
{
    OWSLogDebug(@"messageId: %@", messageId);
    [self ensureInteractionLoadedThenScrollToInteraction:messageId
                                      onScreenPercentage:1
                                               alignment:ScrollAlignmentCenterIfNotEntirelyOnScreen
                                              isAnimated:YES];
    [BenchManager completeEventWithEventId:[NSString stringWithFormat:@"Conversation Search Nav: %@", messageId]];
}

#pragma mark - ConversationInputToolbarDelegate

- (void)sendButtonPressed
{
    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    [BenchManager startEventWithTitle:@"Send Message" eventId:@"message-send"];
    [BenchManager startEventWithTitle:@"Send Message milestone: clearTextMessageAnimated completed"
                              eventId:@"fromSendUntil_clearTextMessageAnimated"];
    [BenchManager startEventWithTitle:@"Send Message milestone: toggleDefaultKeyboard completed"
                              eventId:@"fromSendUntil_toggleDefaultKeyboard"];

    [self.inputToolbar acceptAutocorrectSuggestion];
    [self tryToSendTextMessage:self.inputToolbar.messageBody updateKeyboardState:YES];
}

- (void)tryToSendTextMessage:(MessageBody *)messageBody updateKeyboardState:(BOOL)updateKeyboardState
{
    OWSAssertIsOnMainThread();

    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    __weak ConversationViewController *weakSelf = self;
    if ([self isBlockedConversation]) {
        [self showUnblockConversationUI:^(BOOL isBlocked) {
            if (!isBlocked) {
                [weakSelf tryToSendTextMessage:messageBody updateKeyboardState:NO];
            }
        }];
        return;
    }

    BOOL didShowSNAlert =
        [self showSafetyNumberConfirmationIfNecessaryWithConfirmationText:[SafetyNumberStrings confirmSendButton]
                                                               completion:^(BOOL didConfirmIdentity) {
                                                                   if (didConfirmIdentity) {
                                                                       [weakSelf resetVerificationStateToDefault];
                                                                       [weakSelf tryToSendTextMessage:messageBody
                                                                                  updateKeyboardState:NO];
                                                                   }
                                                               }];
    if (didShowSNAlert) {
        return;
    }

    if (messageBody.text.length < 1) {
        return;
    }

    BOOL didAddToProfileWhitelist =
        [ThreadUtil addThreadToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction:self.thread];
    __block TSOutgoingMessage *message;

    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        message = [ThreadUtil enqueueMessageWithBody:messageBody
                                              thread:self.thread
                                    quotedReplyModel:self.inputToolbar.quotedReply
                                    linkPreviewDraft:self.inputToolbar.linkPreviewDraft
                                         transaction:transaction];
    }];
    [self.loadCoordinator clearUnreadMessagesIndicator];
    // TODO: Audit optimistic insertion.
    [self.loadCoordinator appendUnsavedOutgoingTextMessage:message];
    [self messageWasSent:message];

    // Clearing the text message is a key part of the send animation.
    // It takes 10-15ms, but we do it inline rather than dispatch async
    // since the send can't feel "complete" without it.
    [BenchManager benchWithTitle:@"clearTextMessageAnimated"
                           block:^{ [self.inputToolbar clearTextMessageAnimated:YES]; }];
    [BenchManager completeEventWithEventId:@"fromSendUntil_clearTextMessageAnimated"];

    dispatch_async(dispatch_get_main_queue(), ^{
        // After sending we want to return from the numeric keyboard to the
        // alphabetical one. Because this is so slow (40-50ms), we prefer it
        // happens async, after any more essential send UI work is done.
        [BenchManager benchWithTitle:@"toggleDefaultKeyboard" block:^{ [self.inputToolbar toggleDefaultKeyboard]; }];
        [BenchManager completeEventWithEventId:@"fromSendUntil_toggleDefaultKeyboard"];
    });

    TSThread *thread = self.thread;
    DatabaseStorageAsyncWrite(self.databaseStorage,
        ^(SDSAnyWriteTransaction *transaction) { [thread updateWithDraft:nil transaction:transaction]; });

    if (didAddToProfileWhitelist) {
        [self ensureBannerState];
    }
}

- (void)sendSticker:(StickerInfo *)stickerInfo
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(stickerInfo);

    OWSLogVerbose(@"Sending sticker.");

    TSOutgoingMessage *message = [ThreadUtil enqueueMessageWithInstalledSticker:stickerInfo thread:self.thread];
    [self messageWasSent:message];
}

- (void)presentManageStickersView
{
    OWSAssertIsOnMainThread();

    ManageStickersViewController *manageStickersView = [ManageStickersViewController new];
    OWSNavigationController *navigationController =
        [[OWSNavigationController alloc] initWithRootViewController:manageStickersView];
    [self presentFormSheetViewController:navigationController animated:YES completion:nil];
}

- (void)updateToolbarHeight
{
    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    [self updateInputAccessoryPlaceholderHeight];
    [self updateBottomBarPosition];

    [self updateContentInsetsAnimated:NO];
}

- (void)voiceMemoGestureDidStart
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"voiceMemoGestureDidStart");

    const CGFloat kIgnoreMessageSendDoubleTapDurationSeconds = 2.f;
    if (self.lastMessageSentDate &&
        [[NSDate new] timeIntervalSinceDate:self.lastMessageSentDate] < kIgnoreMessageSendDoubleTapDurationSeconds) {
        // If users double-taps the message send button, the second tap can look like a
        // very short voice message gesture.  We want to ignore such gestures.
        [self.inputToolbar cancelVoiceMemoIfNecessary];
        [self.inputToolbar hideVoiceMemoUI:NO];
        [self cancelRecordingVoiceMemo];
        return;
    }

    [self.inputToolbar showVoiceMemoUI];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    [self requestRecordingVoiceMemo];
}

- (void)voiceMemoGestureDidComplete
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    [self.inputToolbar hideVoiceMemoUI:YES];
    [self endRecordingVoiceMemo];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)voiceMemoGestureDidLock
{
    OWSAssertIsOnMainThread();
    OWSLogInfo(@"");

    [self.inputToolbar lockVoiceMemoUI];
}

- (void)voiceMemoGestureDidCancel
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"voiceMemoGestureDidCancel");

    [self.inputToolbar hideVoiceMemoUI:NO];
    [self cancelRecordingVoiceMemo];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)voiceMemoGestureDidUpdateCancelWithRatioComplete:(CGFloat)cancelAlpha
{
    OWSAssertIsOnMainThread();

    [self.inputToolbar setVoiceMemoUICancelAlpha:cancelAlpha];
}

- (void)cancelVoiceMemo
{
    OWSAssertIsOnMainThread();

    [self.inputToolbar cancelVoiceMemoIfNecessary];
    [self.inputToolbar hideVoiceMemoUI:NO];
    [self cancelRecordingVoiceMemo];
}

#pragma mark - Database Observation

- (BOOL)isViewVisible
{
    return self.viewState.isViewVisible;
}

- (void)setIsViewVisible:(BOOL)isViewVisible
{
    self.viewState.isViewVisible = isViewVisible;

    [self updateCellsVisible];
}

- (void)updateCellsVisible
{
    BOOL isAppInBackground = CurrentAppContext().isInBackground;
    BOOL isCellVisible = self.isViewVisible && !isAppInBackground;
    for (CVCell *cell in self.collectionView.visibleCells) {
        cell.isCellVisible = isCellVisible;
    }
}

#pragma mark - ContactsPickerDelegate

- (void)contactsPickerDidCancel:(ContactsPicker *)contactsPicker
{
    OWSLogDebug(@"");
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)contactsPicker:(ContactsPicker *)contactsPicker contactFetchDidFail:(NSError *)error
{
    OWSLogDebug(@"with error %@", error);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)contactsPicker:(ContactsPicker *)contactsPicker didSelectContact:(Contact *)contact
{
    OWSAssertDebug(contact);
    OWSAssertDebug(contact.cnContactId);

    CNContact *_Nullable cnContact = [self.contactsManager cnContactWithId:contact.cnContactId];
    if (!cnContact) {
        OWSFailDebug(@"Could not load system contact.");
        return;
    }

    OWSLogDebug(@"with contact: %@", contact);

    OWSContact *_Nullable contactShareRecord = [OWSContacts contactForSystemContact:cnContact];
    if (!contactShareRecord) {
        OWSFailDebug(@"Could not convert system contact.");
        return;
    }

    BOOL isProfileAvatar = NO;
    __block NSData *_Nullable avatarImageData = [self.contactsManager avatarDataForCNContactId:cnContact.identifier];
    for (SignalServiceAddress *address in contact.registeredAddresses) {
        if (avatarImageData) {
            break;
        }
        avatarImageData = [self.contactsManager profileImageDataForAddressWithSneakyTransaction:address];
        if (avatarImageData) {
            isProfileAvatar = YES;
        }
    }
    contactShareRecord.isProfileAvatar = isProfileAvatar;

    ContactShareViewModel *contactShare = [[ContactShareViewModel alloc] initWithContactShareRecord:contactShareRecord
                                                                                    avatarImageData:avatarImageData];

    ContactShareApprovalViewController *approveContactShare =
        [[ContactShareApprovalViewController alloc] initWithContactShare:contactShare];
    approveContactShare.delegate = self;
    OWSAssertDebug(contactsPicker.navigationController);
    [contactsPicker.navigationController pushViewController:approveContactShare animated:YES];
}

- (void)contactsPicker:(ContactsPicker *)contactsPicker didSelectMultipleContacts:(NSArray<Contact *> *)contacts
{
    OWSFailDebug(@"with contacts: %@", contacts);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)contactsPicker:(ContactsPicker *)contactsPicker shouldSelectContact:(Contact *)contact
{
    // Any reason to preclude contacts?
    return YES;
}

#pragma mark - ContactShareApprovalViewControllerDelegate

- (void)approveContactShare:(ContactShareApprovalViewController *)approveContactShare
     didApproveContactShare:(ContactShareViewModel *)contactShare
{
    OWSLogInfo(@"");

    [self dismissViewControllerAnimated:YES completion:^{ [self sendContactShare:contactShare]; }];
}

- (void)approveContactShare:(ContactShareApprovalViewController *)approveContactShare
      didCancelContactShare:(ContactShareViewModel *)contactShare
{
    OWSLogInfo(@"");

    [self dismissViewControllerAnimated:YES completion:nil];
}

- (nullable NSString *)contactApprovalCustomTitle:(ContactShareApprovalViewController *)contactApproval
{
    return nil;
}

- (nullable NSString *)contactApprovalRecipientsDescription:(ContactShareApprovalViewController *)contactApproval
{
    OWSLogInfo(@"");

    __block NSString *result;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.contactsManager displayNameForThread:self.thread transaction:transaction];
    }];
    return result;
}

- (ApprovalMode)contactApprovalMode:(ContactShareApprovalViewController *)contactApproval
{
    OWSLogInfo(@"");

    return ApprovalModeSend;
}

#pragma mark - ContactShareViewHelperDelegate

- (void)didCreateOrEditContact
{
    OWSLogInfo(@"");
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Toast

- (void)presentMissingQuotedReplyToast
{
    OWSLogInfo(@"");

    NSString *toastText = NSLocalizedString(@"QUOTED_REPLY_ORIGINAL_MESSAGE_DELETED",
        @"Toast alert text shown when tapping on a quoted message which we cannot scroll to because the local copy of "
        @"the message was since deleted.");

    ToastController *toastController = [[ToastController alloc] initWithText:toastText];

    CGFloat bottomInset = kToastInset + self.collectionView.contentInset.bottom + self.view.layoutMargins.bottom;

    [toastController presentToastViewFromBottomOfView:self.view inset:bottomInset];
}

- (void)presentRemotelySourcedQuotedReplyToast
{
    OWSLogInfo(@"");

    NSString *toastText = NSLocalizedString(@"QUOTED_REPLY_ORIGINAL_MESSAGE_REMOTELY_SOURCED",
        @"Toast alert text shown when tapping on a quoted message which we cannot scroll to because the local copy of "
        @"the message didn't exist when the quote was received.");

    ToastController *toastController = [[ToastController alloc] initWithText:toastText];

    CGFloat bottomInset = kToastInset + self.collectionView.contentInset.bottom + self.view.layoutMargins.bottom;

    [toastController presentToastViewFromBottomOfView:self.view inset:bottomInset];
}

- (void)presentViewOnceAlreadyViewedToast
{
    OWSLogInfo(@"");

    NSString *toastText = NSLocalizedString(@"VIEW_ONCE_ALREADY_VIEWED_TOAST",
        @"Toast alert text shown when tapping on a view-once message that has already been viewed.");

    ToastController *toastController = [[ToastController alloc] initWithText:toastText];

    CGFloat bottomInset = kToastInset + self.collectionView.contentInset.bottom + self.view.layoutMargins.bottom;

    [toastController presentToastViewFromBottomOfView:self.view inset:bottomInset];
}

- (void)presentViewOnceOutgoingToast
{
    OWSLogInfo(@"");

    NSString *toastText = NSLocalizedString(
        @"VIEW_ONCE_OUTGOING_TOAST", @"Toast alert text shown when tapping on a view-once message that you have sent.");

    ToastController *toastController = [[ToastController alloc] initWithText:toastText];

    CGFloat bottomInset = kToastInset + self.collectionView.contentInset.bottom + self.view.layoutMargins.bottom;

    [toastController presentToastViewFromBottomOfView:self.view inset:bottomInset];
}

#pragma mark - CollectionView updates

- (void)performBatchUpdates:(void (^_Nonnull)(void))batchUpdates
                 completion:(void (^_Nonnull)(BOOL))completion
            logFailureBlock:(void (^_Nonnull)(void))logFailureBlock
       shouldAnimateUpdates:(BOOL)shouldAnimateUpdates
{
    @try {
        void (^updateBlock)(void) = ^{
            [self.layout willPerformBatchUpdates];
            [self.collectionView performBatchUpdates:batchUpdates completion:completion];
            [self.layout didPerformBatchUpdates];

            // AFAIK the collection view layout should reflect the old layout
            // until performBatchUpdates(), then we need to invalidate and prepare
            // the (new) layout just _after_ performBatchUpdates.
            //
            // Moreover it's important that the (old) layout is prepared when
            // performBatchUpdates() is called.  We ensure this in
            // willUpdateWithNewRenderState().
            //
            // Otherwise UICollectionView can throw (crashing) exceptions like this:
            //
            // UICollectionView received layout attributes for a cell with an index path that does not exist...
            [self.layout invalidateLayout];
            [BenchManager completeEventWithEventId:@"message-send"];
        };

        if (shouldAnimateUpdates) {
            updateBlock();
        } else {
            // HACK: We use `UIView.animateWithDuration:0` rather than `UIView.performWithAnimation` to work around a
            // UIKit Crash like:
            //
            //     *** Assertion failure in -[ConversationViewLayout prepareForCollectionViewUpdates:],
            //     /BuildRoot/Library/Caches/com.apple.xbs/Sources/UIKit_Sim/UIKit-3600.7.47/UICollectionViewLayout.m:760
            //     *** Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'While
            //     preparing update a visible view at <NSIndexPath: 0xc000000011c00016> {length = 2, path = 0 - 142}
            //     wasn't found in the current data model and was not in an update animation. This is an internal
            //     error.'
            //
            // I'm unclear if this is a bug in UIKit, or if we're doing something crazy in
            // ConversationViewLayout#prepareLayout. To reproduce, rapidily insert and delete items into the
            // conversation. See `DebugUIMessages#thrashCellsInThread:`
            [UIView animateWithDuration:0.0 animations:updateBlock];
        }
    } @catch (NSException *exception) {
        OWSFailDebug(@"exception: %@ of type: %@ with reason: %@, user info: %@.",
            exception.description,
            exception.name,
            exception.reason,
            exception.userInfo);

        logFailureBlock();

        @throw exception;
    }
}

#pragma mark - Orientation

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    OWSAssertIsOnMainThread();

    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    [self dismissMessageActionsAnimated:NO];
    [self dismissReactionsDetailSheetAnimated:NO];

    self.scrollContinuity = ScrollContinuityBottom;

    if (!self.hasAppearedAndHasAppliedFirstLoad) {
        return;
    }

    [self setScrollActionForSizeTransition];

    __weak ConversationViewController *weakSelf = self;
    [coordinator
        animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {}
        completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            [weakSelf clearScrollActionForSizeTransition];
        }];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];

    [self ensureBannerState];
    [self updateBarButtonItems];
    [self updateNavigationBarSubtitleLabel];
}

- (void)resetForSizeOrOrientationChange
{
    [self updateConversationStyle];

    self.scrollContinuity = ScrollContinuityBottom;
}

- (void)viewSafeAreaInsetsDidChange
{
    [super viewSafeAreaInsetsDidChange];

    [self updateContentInsetsAnimated:NO];
    [self updateInputToolbarLayout];
    [self viewSafeAreaInsetsDidChangeForLoad];
    [self updateConversationStyle];
}

#pragma mark - LocationPickerDelegate

- (void)didPickLocation:(LocationPicker *)locationPicker location:(Location *)location
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(location);

    OWSLogVerbose(@"Sending location share.");

    __weak ConversationViewController *weakSelf = self;

    [location prepareAttachmentObjc].then(^(SignalAttachment *attachment) {
        OWSAssertIsOnMainThread();
        OWSAssertDebug([attachment isKindOfClass:[SignalAttachment class]]);

        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        __block TSOutgoingMessage *message;

        [strongSelf.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
            message = [ThreadUtil enqueueMessageWithBody:[[MessageBody alloc] initWithText:location.messageText
                                                                                    ranges:MessageBodyRanges.empty]
                                        mediaAttachments:@[ attachment ]
                                                  thread:strongSelf.thread
                                        quotedReplyModel:nil
                                        linkPreviewDraft:nil
                                             transaction:transaction];
        }];

        [strongSelf messageWasSent:message];
    });
}

#pragma mark - InputAccessoryViewPlaceholderDelegate

- (void)inputAccessoryPlaceholderKeyboardIsDismissingInteractively
{
    // No animation, just follow along with the keyboard.
    self.isDismissingInteractively = YES;
    [self updateBottomBarPosition];
    self.isDismissingInteractively = NO;
}

- (void)inputAccessoryPlaceholderKeyboardIsDismissingWithAnimationDuration:(NSTimeInterval)animationDuration
                                                            animationCurve:(UIViewAnimationCurve)animationCurve
{
    [self handleKeyboardStateChange:animationDuration animationCurve:animationCurve];
}

- (void)inputAccessoryPlaceholderKeyboardDidDismiss
{
    [self updateBottomBarPosition];
    [self updateContentInsetsAnimated:NO];
}

- (void)inputAccessoryPlaceholderKeyboardIsPresentingWithAnimationDuration:(NSTimeInterval)animationDuration
                                                            animationCurve:(UIViewAnimationCurve)animationCurve
{
    [self handleKeyboardStateChange:animationDuration animationCurve:animationCurve];
}

- (void)inputAccessoryPlaceholderKeyboardDidPresent
{
    [self updateBottomBarPosition];
    [self updateContentInsetsAnimated:NO];
}

- (void)handleKeyboardStateChange:(NSTimeInterval)animationDuration animationCurve:(UIViewAnimationCurve)animationCurve
{
    if (self.shouldAnimateKeyboardChanges && animationDuration > 0) {
        // The animation curve provided by the keyboard notifications
        // is a private value not represented in UIViewAnimationOptions.
        // We don't use a block based animation here because it's not
        // possible to pass a curve directly to block animations.
        [UIView beginAnimations:@"keyboardStateChange" context:nil];
        [UIView setAnimationBeginsFromCurrentState:YES];
        [UIView setAnimationCurve:animationCurve];
        [UIView setAnimationDuration:animationDuration];
        [self updateBottomBarPosition];
        [UIView commitAnimations];
        [self updateContentInsetsAnimated:YES];
    } else {
        [self updateBottomBarPosition];
        [self updateContentInsetsAnimated:NO];
    }
}

#pragma mark - Keyboard Shortcuts

- (void)focusInputToolbar
{
    OWSAssertIsOnMainThread();

    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    [self.inputToolbar clearDesiredKeyboard];
    [self popKeyBoard];
}

- (void)openAllMedia
{
    OWSAssertIsOnMainThread();

    [self showConversationSettingsAndShowAllMedia];
}

- (void)openStickerKeyboard
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.inputToolbar != nil);


    [self.inputToolbar showStickerKeyboard];
}

- (void)openAttachmentKeyboard
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.inputToolbar != nil);

    [self.inputToolbar showAttachmentKeyboard];
}

- (void)openGifSearch
{
    OWSAssertIsOnMainThread();

    [self showGifPicker];
}

- (ConversationInputToolbar *)buildInputToolbar:(ConversationStyle *)conversationStyle
                                   messageDraft:(nullable MessageBody *)messageDraft
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.hasViewWillAppearEverBegun);

    ConversationInputToolbar *inputToolbar =
        [[ConversationInputToolbar alloc] initWithConversationStyle:conversationStyle
                                                       messageDraft:messageDraft
                                               inputToolbarDelegate:self
                                              inputTextViewDelegate:self
                                                    mentionDelegate:self];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, inputToolbar);
    return inputToolbar;
}

#pragma mark - CVComponentDelegate

- (void)cvc_didTapShowGroupMigrationLearnMoreActionSheetWithInfoMessage:(TSInfoMessage *)infoMessage
                                                          oldGroupModel:(TSGroupModel *)oldGroupModel
                                                          newGroupModel:(TSGroupModel *)newGroupModel
{
    OWSAssertIsOnMainThread();

    if (![self.thread isKindOfClass:[TSGroupThread class]]) {
        OWSFailDebug(@"Invalid thread.");
        return;
    }

    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    GroupMigrationActionSheet *actionSheet =
        [GroupMigrationActionSheet actionSheetForMigratedGroupWithGroupThread:groupThread
                                                                oldGroupModel:oldGroupModel
                                                                newGroupModel:newGroupModel];
    [actionSheet presentFromViewController:self];
}

- (void)cvc_didTapGroupInviteLinkPromotionWithGroupModel:(TSGroupModel *)groupModel
{
    OWSAssertIsOnMainThread();

    [self showGroupLinkPromotionActionSheet];
}

- (void)cvc_didTapShowUpgradeAppUI
{
    OWSAssertIsOnMainThread();

    NSString *url = @"https://itunes.apple.com/us/app/signal-private-messenger/id874139669?mt=8";
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil];
}

- (void)cvc_didTapUpdateSystemContact:(SignalServiceAddress *)address
                    newNameComponents:(NSPersonNameComponents *)newNameComponents
{
    OWSAssertIsOnMainThread();

    if (!self.contactsManager.supportsContactEditing) {
        OWSFailDebug(@"Contact editing unexpectedly unsupported");
        return;
    }

    CNContactViewController *contactViewController =
        [self.contactsViewHelper contactViewControllerForAddress:address
                                                 editImmediately:YES
                                          addToExistingCnContact:nil
                                           updatedNameComponents:newNameComponents];
    contactViewController.delegate = self;

    [self.navigationController pushViewController:contactViewController animated:YES];
}

- (void)cvc_didTapIndividualCall:(TSCall *)call
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(call);
    OWSAssertDebug(self.inputToolbar != nil);

    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFailDebug(@"unexpected thread: %@", self.thread);
        return;
    }

    TSContactThread *contactThread = (TSContactThread *)self.thread;
    NSString *displayName = [self.contactsManager displayNameForAddress:contactThread.contactAddress];

    ActionSheetController *alert = [[ActionSheetController alloc]
        initWithTitle:[CallStrings callBackAlertTitle]
              message:[NSString stringWithFormat:[CallStrings callBackAlertMessageFormat], displayName]];

    __weak ConversationViewController *weakSelf = self;
    ActionSheetAction *callAction =
        [[ActionSheetAction alloc] initWithTitle:[CallStrings callBackAlertCallButton]
                         accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"call_back")
                                           style:ActionSheetActionStyleDefault
                                         handler:^(ActionSheetAction *action) {
                                             switch (call.offerType) {
                                                 case TSRecentCallOfferTypeAudio:
                                                     [weakSelf startIndividualAudioCall];
                                                     break;
                                                 case TSRecentCallOfferTypeVideo:
                                                     [weakSelf startIndividualVideoCall];
                                                     break;
                                             }
                                         }];
    [alert addAction:callAction];
    [alert addAction:[OWSActionSheets cancelAction]];

    [self.inputToolbar clearDesiredKeyboard];
    [self dismissKeyBoard];
    [self presentActionSheet:alert];
}

- (void)cvc_didTapGroupCall
{
    OWSAssertIsOnMainThread();

    [self showGroupLobbyOrActiveCall];
}

- (BOOL)isCurrentCallForThread
{
    TSThread *currentCallThread = self.callService.currentCall.thread;
    return [self.thread.uniqueId isEqualToString:currentCallThread.uniqueId];
}

- (BOOL)isCallingSupported
{
    return [self canCall];
}

- (void)cvc_didLongPressTextViewItem:(CVCell *)cell
                       itemViewModel:(CVItemViewModelImpl *)itemViewModel
                    shouldAllowReply:(BOOL)shouldAllowReply
{
    OWSAssertIsOnMainThread();

    NSArray<MessageAction *> *messageActions = [MessageActions textActionsWithItemViewModel:itemViewModel
                                                                           shouldAllowReply:shouldAllowReply
                                                                                   delegate:self];
    [self presentMessageActions:messageActions withFocusedCell:cell itemViewModel:itemViewModel];
}

- (void)cvc_didLongPressMediaViewItem:(CVCell *)cell
                        itemViewModel:(CVItemViewModelImpl *)itemViewModel
                     shouldAllowReply:(BOOL)shouldAllowReply
{
    OWSAssertIsOnMainThread();

    NSArray<MessageAction *> *messageActions = [MessageActions mediaActionsWithItemViewModel:itemViewModel
                                                                            shouldAllowReply:shouldAllowReply
                                                                                    delegate:self];
    [self presentMessageActions:messageActions withFocusedCell:cell itemViewModel:itemViewModel];
}

- (void)cvc_didLongPressQuote:(CVCell *)cell
                itemViewModel:(CVItemViewModelImpl *)itemViewModel
             shouldAllowReply:(BOOL)shouldAllowReply
{
    OWSAssertIsOnMainThread();

    NSArray<MessageAction *> *messageActions = [MessageActions quotedMessageActionsWithItemViewModel:itemViewModel
                                                                                    shouldAllowReply:shouldAllowReply
                                                                                            delegate:self];
    [self presentMessageActions:messageActions withFocusedCell:cell itemViewModel:itemViewModel];
}

- (void)cvc_didLongPressSystemMessage:(CVCell *)cell itemViewModel:(CVItemViewModelImpl *)itemViewModel
{
    OWSAssertIsOnMainThread();

    NSArray<MessageAction *> *messageActions = [MessageActions infoMessageActionsWithItemViewModel:itemViewModel
                                                                                          delegate:self];
    [self presentMessageActions:messageActions withFocusedCell:cell itemViewModel:itemViewModel];
}

- (void)cvc_didLongPressSticker:(CVCell *)cell
                  itemViewModel:(CVItemViewModelImpl *)itemViewModel
               shouldAllowReply:(BOOL)shouldAllowReply
{
    OWSAssertIsOnMainThread();

    NSArray<MessageAction *> *messageActions = [MessageActions mediaActionsWithItemViewModel:itemViewModel
                                                                            shouldAllowReply:shouldAllowReply
                                                                                    delegate:self];
    [self presentMessageActions:messageActions withFocusedCell:cell itemViewModel:itemViewModel];
}

- (void)cvc_didTapReplyToItem:(CVItemViewModelImpl *)itemViewModel
{
    OWSAssertIsOnMainThread();

    [self populateReplyForMessage:itemViewModel];
}

- (void)cvc_didTapSenderAvatar:(TSInteraction *)interaction
{
    OWSAssertIsOnMainThread();

    if (interaction.interactionType != OWSInteractionType_IncomingMessage) {
        OWSFailDebug(@"not an incoming message.");
        return;
    }

    TSIncomingMessage *incomingMessage = (TSIncomingMessage *)interaction;
    GroupViewHelper *groupViewHelper = [[GroupViewHelper alloc] initWithThreadViewModel:self.threadViewModel];
    groupViewHelper.delegate = self;
    MemberActionSheet *actionSheet = [[MemberActionSheet alloc] initWithAddress:incomingMessage.authorAddress
                                                                groupViewHelper:groupViewHelper];
    [actionSheet presentFromViewController:self];
}

- (BOOL)cvc_shouldAllowReplyForItem:(CVItemViewModelImpl *)itemViewModel
{
    OWSAssertIsOnMainThread();

    if (self.thread.isGroupThread && !self.thread.isLocalUserFullMemberOfThread) {
        return NO;
    }
    if (self.threadViewModel.hasPendingMessageRequest) {
        return NO;
    }

    TSInteraction *interaction = itemViewModel.interaction;
    if ([interaction isKindOfClass:[TSMessage class]]) {
        TSMessage *message = (TSMessage *)interaction;
        if (message.wasRemotelyDeleted) {
            return NO;
        }
    }

    if (interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)interaction;
        if (outgoingMessage.messageState == TSOutgoingMessageStateFailed) {
            // Don't allow "delete" or "reply" on "failed" outgoing messages.
            return NO;
        } else if (outgoingMessage.messageState == TSOutgoingMessageStateSending) {
            // Don't allow "delete" or "reply" on "sending" outgoing messages.
            return NO;
        }
    }

    return YES;
}

- (void)cvc_didChangeLongpress:(CVItemViewModelImpl *)itemViewModel
{
    OWSAssertIsOnMainThread();

    if (![self.messageActionsViewController.focusedInteraction.uniqueId
            isEqualToString:itemViewModel.interaction.uniqueId]) {
        OWSFailDebug(@"Received longpress update for unexpected cell");
        return;
    }

    [self.messageActionsViewController didChangeLongpress];
}

- (void)cvc_didEndLongpress:(CVItemViewModelImpl *)itemViewModel
{
    OWSAssertIsOnMainThread();

    if (![self.messageActionsViewController.focusedInteraction.uniqueId
            isEqualToString:itemViewModel.interaction.uniqueId]) {
        OWSFailDebug(@"Received longpress update for unexpected cell");
        return;
    }

    [self.messageActionsViewController didEndLongpress];
}

- (void)cvc_didCancelLongpress:(CVItemViewModelImpl *)itemViewModel
{
    OWSAssertIsOnMainThread();

    if (![self.messageActionsViewController.focusedInteraction.uniqueId
            isEqualToString:itemViewModel.interaction.uniqueId]) {
        OWSFailDebug(@"Received longpress update for unexpected cell");
        return;
    }

    // TODO: Port.
    //    [self.messageActionsViewController didCancelLongpress];
}

- (void)cvc_didTapReactionsWithReactionState:(InteractionReactionState *)reactionState message:(TSMessage *)message
{
    OWSAssertIsOnMainThread();

    if (!reactionState.hasReactions) {
        OWSFailDebug(@"missing reaction state");
        return;
    }

    ReactionsDetailSheet *detailSheet = [[ReactionsDetailSheet alloc] initWithReactionState:reactionState
                                                                                    message:message];
    [self presentViewController:detailSheet animated:YES completion:nil];
    self.reactionsDetailSheet = detailSheet;
}

- (BOOL)cvc_hasPendingMessageRequest
{
    OWSAssertIsOnMainThread();

    return self.threadViewModel.hasPendingMessageRequest;
}

- (void)cvc_didTapTruncatedTextMessage:(CVItemViewModelImpl *)itemViewModel
{
    OWSAssertIsOnMainThread();

    [self expandTruncatedTextOrPresentLongTextView:itemViewModel];
}

- (void)cvc_didTapFailedOrPendingDownloads:(TSMessage *)message
{
    OWSAssertIsOnMainThread();

    [self handleTapOnFailedOrPendingDownloads:message];
}

- (void)cvc_didTapBodyMediaWithItemViewModel:(CVItemViewModelImpl *)itemViewModel
                            attachmentStream:(TSAttachmentStream *)attachmentStream
                                   imageView:(UIView *)imageView
{
    OWSAssertIsOnMainThread();

    [self dismissKeyBoard];

    MediaPageViewController *pageVC = [[MediaPageViewController alloc] initWithInitialMediaAttachment:attachmentStream
                                                                                               thread:self.thread];
    [self presentViewController:pageVC animated:YES completion:nil];
}

- (void)cvc_didTapGenericAttachment:(CVComponentGenericAttachment *_Nonnull)attachment
{
    OWSAssertIsOnMainThread();

    QLPreviewController *previewController = [[QLPreviewController alloc] init];
    previewController.dataSource = attachment;
    [self presentViewController:previewController animated:YES completion:nil];
}

- (void)cvc_didTapQuotedReply:(OWSQuotedReplyModel *)quotedReply
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(quotedReply);
    OWSAssertDebug(quotedReply.timestamp > 0);
    OWSAssertDebug(quotedReply.authorAddress.isValid);

    [self scrollToQuotedMessage:quotedReply isAnimated:YES];
}

- (void)cvc_didTapLinkPreview:(OWSLinkPreview *)linkPreview
{
    OWSAssertIsOnMainThread();

    NSURL *_Nullable url = [NSURL URLWithString:linkPreview.urlString];
    if (!url) {
        OWSFailDebug(@"Invalid link preview URL.");
        return;
    }

    if ([StickerPackInfo isStickerPackShareUrl:url]) {
        StickerPackInfo *_Nullable stickerPackInfo = [StickerPackInfo parseStickerPackShareUrl:url];

        if (stickerPackInfo == nil) {
            OWSFailDebug(@"Could not parse sticker pack share URL: %@", url);
        } else {
            StickerPackViewController *packView =
                [[StickerPackViewController alloc] initWithStickerPackInfo:stickerPackInfo];

            [packView presentFrom:self animated:YES];
            return;
        }
    }

    if ([GroupManager isPossibleGroupInviteLink:url]) {
        [self cvc_didTapGroupInviteLinkWithUrl:url];
        return;
    }

    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)cvc_didTapContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();

    ContactViewController *view = [[ContactViewController alloc] initWithContactShare:contactShare];
    [self.navigationController pushViewController:view animated:YES];
}

- (void)cvc_didTapSendMessageToContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();

    [self.contactShareViewHelper sendMessageWithContactShare:contactShare fromViewController:self];
}

- (void)cvc_didTapSendInviteToContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();

    [self.contactShareViewHelper showInviteContactWithContactShare:contactShare fromViewController:self];
}

- (void)cvc_didTapAddToContactsWithContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();

    [self.contactShareViewHelper showAddToContactsWithContactShare:contactShare fromViewController:self];
}

- (void)cvc_didTapStickerPack:(StickerPackInfo *)stickerPackInfo
{
    OWSAssertIsOnMainThread();

    StickerPackViewController *packView = [[StickerPackViewController alloc] initWithStickerPackInfo:stickerPackInfo];
    [packView presentFrom:self animated:YES];
}

- (void)cvc_didTapGroupInviteLinkWithUrl:(NSURL *)url
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug([GroupManager isPossibleGroupInviteLink:url]);

    [GroupInviteLinksUI openGroupInviteLink:url fromViewController:self];
}

- (void)cvc_didTapMention:(Mention *)mention
{
    OWSAssertIsOnMainThread();

    [ImpactHapticFeedback impactOccuredWithStyle:UIImpactFeedbackStyleLight];
    GroupViewHelper *groupViewHelper = [[GroupViewHelper alloc] initWithThreadViewModel:self.threadViewModel];
    groupViewHelper.delegate = self;
    MemberActionSheet *actionSheet = [[MemberActionSheet alloc] initWithAddress:mention.address
                                                                groupViewHelper:groupViewHelper];
    [actionSheet presentFromViewController:self];
}

#pragma mark - Selection

// TODO: Move these methods to +Selection.swift
- (BOOL)cvc_isMessageSelected:(TSInteraction *)interaction
{
    return [self isMessageSelected:interaction];
}

// TODO: Move these methods to +Selection.swift
- (void)cvc_didSelectViewItem:(CVItemViewModelImpl *)itemViewModel
{
    [self didSelectMessage:itemViewModel];
}

// TODO: Move these methods to +Selection.swift
- (void)cvc_didDeselectViewItem:(CVItemViewModelImpl *)itemViewModel
{
    [self didDeselectMessage:itemViewModel];
}

#pragma mark - System Cell

- (void)cvc_didTapNonBlockingIdentityChange:(SignalServiceAddress *)address
{
    OWSAssertIsOnMainThread();

    if (address == nil) {
        if (self.thread.isGroupThread) {
            // Before 2.13 we didn't track the recipient id in the identity change error.
            OWSLogWarn(@"Ignoring tap on legacy nonblocking identity change since it has no signal id");
            return;

        } else {
            TSContactThread *thread = (TSContactThread *)self.thread;
            OWSLogInfo(@"Assuming tap on legacy nonblocking identity change corresponds to current contact thread: %@",
                thread.contactAddress);
            address = thread.contactAddress;
        }
    }

    [self showFingerprintWithAddress:address];
}

- (void)cvc_didTapInvalidIdentityKeyErrorMessage:(TSInvalidIdentityKeyErrorMessage *)errorMessage
{
    OWSAssertIsOnMainThread();

    NSString *keyOwner = [self.contactsManager displayNameForAddress:errorMessage.theirSignalAddress];
    NSString *titleFormat = NSLocalizedString(@"SAFETY_NUMBERS_ACTIONSHEET_TITLE", @"Action sheet heading");
    NSString *titleText = [NSString stringWithFormat:titleFormat, keyOwner];

    ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:titleText message:nil];

    [actionSheet addAction:[OWSActionSheets cancelAction]];

    ActionSheetAction *showSafteyNumberAction =
        [[ActionSheetAction alloc] initWithTitle:NSLocalizedString(@"SHOW_SAFETY_NUMBER_ACTION", @"Action sheet item")
                         accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"show_safety_number")
                                           style:ActionSheetActionStyleDefault
                                         handler:^(ActionSheetAction *action) {
                                             OWSLogInfo(@"Remote Key Changed actions: Show fingerprint display");
                                             [self showFingerprintWithAddress:errorMessage.theirSignalAddress];
                                         }];
    [actionSheet addAction:showSafteyNumberAction];

    ActionSheetAction *acceptSafetyNumberAction = [[ActionSheetAction alloc]
                  initWithTitle:NSLocalizedString(@"ACCEPT_NEW_IDENTITY_ACTION", @"Action sheet item")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"accept_safety_number")
                          style:ActionSheetActionStyleDefault
                        handler:^(ActionSheetAction *action) {
                            OWSLogInfo(@"Remote Key Changed actions: Accepted new identity key");

        // DEPRECATED: we're no longer creating these incoming SN error's per message,
        // but there will be some legacy ones in the wild, behind which await
        // as-of-yet-undecrypted messages
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                            if ([errorMessage isKindOfClass:[TSInvalidIdentityKeyReceivingErrorMessage class]]) {
                                // Deliberately crash if the user fails to explicitly accept the new identity
                                // key. In practice we haven't been creating these messages in over a year.
                                [errorMessage throws_acceptNewIdentityKey];
#pragma clang diagnostic pop
                            }
                        }];
    [actionSheet addAction:acceptSafetyNumberAction];

    [self dismissKeyBoard];
    [self presentActionSheet:actionSheet];
}

- (void)cvc_didTapCorruptedMessage:(TSErrorMessage *)errorMessage
{
    OWSAssertIsOnMainThread();

    __block NSString *threadName;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        threadName = [self.contactsManager displayNameForThread:self.thread transaction:transaction];
    }];
    NSString *alertMessage = [NSString
        stringWithFormat:NSLocalizedString(@"CORRUPTED_SESSION_DESCRIPTION", @"ActionSheet title"), threadName];

    ActionSheetController *alert = [[ActionSheetController alloc] initWithTitle:nil message:alertMessage];

    [alert addAction:[OWSActionSheets cancelAction]];

    ActionSheetAction *resetSessionAction = [[ActionSheetAction alloc]
                  initWithTitle:NSLocalizedString(@"FINGERPRINT_SHRED_KEYMATERIAL_BUTTON", @"")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"reset_session")
                          style:ActionSheetActionStyleDefault
                        handler:^(ActionSheetAction *action) {
                            if (![self.thread isKindOfClass:[TSContactThread class]]) {
                                // Corrupt Message errors only appear in contact threads.
                                OWSLogError(@"Unexpected request to reset session in group thread. Refusing");
                                return;
                            }
                            TSContactThread *contactThread = (TSContactThread *)self.thread;
                            DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                                [self.sessionResetJobQueue addContactThread:contactThread transaction:transaction];
                            });
                        }];
    [alert addAction:resetSessionAction];

    [self dismissKeyBoard];
    [self presentActionSheet:alert];
}

- (void)cvc_didTapSessionRefreshMessage:(TSErrorMessage *)message
{
    [self dismissKeyBoard];

    UIImageView *headerImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"chat-session-refresh"]];

    UIView *headerView = [UIView new];
    [headerView addSubview:headerImageView];
    [headerImageView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:22];
    [headerImageView autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [headerImageView autoHCenterInSuperview];
    [headerImageView autoSetDimension:ALDimensionWidth toSize:200];
    [headerImageView autoSetDimension:ALDimensionHeight toSize:110];

    [ContactSupportAlert
        presentAlertWithTitle:NSLocalizedString(@"SESSION_REFRESH_ALERT_TITLE", @"Title for the session refresh alert")
                      message:NSLocalizedString(
                                  @"SESSION_REFRESH_ALERT_MESSAGE", @"Description for the session refresh alert")
           emailSupportFilter:@"Signal iOS Session Refresh"
           fromViewController:self
            additionalActions:@[ [[ActionSheetAction alloc]
                                            initWithTitle:CommonStrings.okayButton
                                  accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"okay")
                                                    style:ActionSheetActionStyleDefault
                                                  handler:^(ActionSheetAction *action) {}] ]
                 customHeader:headerView
                   showCancel:NO];
}

- (void)cvc_didTapResendGroupUpdateForErrorMessage:(TSErrorMessage *)message
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug([self.thread isKindOfClass:[TSGroupThread class]]);
    OWSAssertDebug(message);

    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    [GroupManager sendGroupUpdateMessageObjcWithThread:groupThread].thenOn(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            OWSLogInfo(@"Group updated, removing group creation error.");

            DatabaseStorageWrite(self.databaseStorage,
                ^(SDSAnyWriteTransaction *transaction) { [message anyRemoveWithTransaction:transaction]; });
        });
}

- (void)cvc_didTapShowFingerprint:(SignalServiceAddress *)address
{
    OWSAssertIsOnMainThread();

    [self showFingerprintWithAddress:address];
}

- (void)showFingerprintWithAddress:(SignalServiceAddress *)address
{
    // Ensure keyboard isn't hiding the "safety numbers changed" interaction when we
    // return from FingerprintViewController.
    [self dismissKeyBoard];

    [FingerprintViewController presentFromViewController:self address:address];
}

- (void)cvc_didTapShowConversationSettings
{
    OWSAssertIsOnMainThread();

    [self showConversationSettings];
}

- (void)cvc_didTapShowConversationSettingsAndShowMemberRequests
{
    OWSAssertIsOnMainThread();

    [self showConversationSettingsAndShowMemberRequests];
}

- (void)cvc_didTapFailedOutgoingMessage:(TSOutgoingMessage *)message
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(message);

    [self resendFailedOutgoingMessage:message];
}

- (void)cvc_didTapViewOnceAttachment:(TSInteraction *)interaction
{
    OWSAssertIsOnMainThread();

    [ViewOnceMessageViewController tryToPresentWithInteraction:interaction from:self];
}

- (void)cvc_didTapViewOnceExpired:(TSInteraction *)interaction
{
    OWSAssertIsOnMainThread();

    if ([interaction isKindOfClass:[TSOutgoingMessage class]]) {
        [self presentViewOnceOutgoingToast];
    } else {
        [self presentViewOnceAlreadyViewedToast];
    }
}

#pragma mark -

- (id<CVComponentDelegate>)componentDelegate
{
    return self;
}

- (BOOL)isShowingSelectionUI
{
    return self.viewState.isShowingSelectionUI;
}

#pragma mark - Group Call Tooltip

- (void)showGroupCallTooltipIfNecessary
{
    [self removeGroupCallTooltip];

    if (!self.canCall || !self.isGroupConversation) {
        return;
    }

    if (self.preferences.wasGroupCallTooltipShown) {
        return;
    }

    // We only want to increment once per CVC lifecycle, since
    // we may tear down and rebuild the tooltip multiple times
    // as the navbar items change.
    if (!self.hasIncrementedGroupCallTooltipShownCount) {
        [self.preferences incrementGroupCallTooltipShownCount];
        self.hasIncrementedGroupCallTooltipShownCount = YES;
    }

    if (self.threadViewModel.groupCallInProgress) {
        return;
    }

    UIView *tailReferenceView = [UIView new];
    tailReferenceView.userInteractionEnabled = NO;
    [self.view addSubview:tailReferenceView];
    self.groupCallTooltipTailReferenceView = tailReferenceView;

    __weak ConversationViewController *weakSelf = self;
    GroupCallTooltip *tooltip = [GroupCallTooltip presentFromView:self.view
                                               widthReferenceView:self.view
                                                tailReferenceView:tailReferenceView
                                                   wasTappedBlock:^{ [weakSelf showGroupLobbyOrActiveCall]; }];
    self.groupCallTooltip = tooltip;

    // This delay is unfortunate, but the bar button item is not always
    // ready to use as a position reference right away after it is set
    // on the navigation item. So we wait a short amount of time for it
    // to hopefully be ready since there's unfortunately not a simple
    // way to monitor when the navigation bar layout has finished (without
    // subclassing navigation bar). Since the stakes are low here (the
    // tooltip just won't be visible), it's not worth doing that for.

    self.groupCallTooltip.hidden = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self positionGroupCallTooltip];
    });
}

- (void)positionGroupCallTooltip
{
    if (!self.groupCallTooltipTailReferenceView) {
        return;
    }

    if (!self.groupCallBarButtonItem) {
        return;
    }

    UIView *_Nullable barButtonView = [self.groupCallBarButtonItem valueForKey:@"view"];
    if (!barButtonView) {
        return;
    }

    if (![barButtonView isKindOfClass:[UIView class]]) {
        OWSFailDebug(@"Unexpected view type for bar button");
        return;
    }

    self.groupCallTooltipTailReferenceView.frame = [self.view convertRect:barButtonView.frame
                                                                 fromView:barButtonView.superview];
    self.groupCallTooltip.hidden = NO;
}

- (void)removeGroupCallTooltip
{
    [self.groupCallTooltip removeFromSuperview];
    self.groupCallTooltip = nil;
    [self.groupCallTooltipTailReferenceView removeFromSuperview];
    self.groupCallTooltipTailReferenceView = nil;
}

@end

NS_ASSUME_NONNULL_END
