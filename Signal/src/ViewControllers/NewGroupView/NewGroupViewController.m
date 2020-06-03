//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "NewGroupViewController.h"
#import "AvatarViewHelper.h"
#import "OWSNavigationController.h"
#import "Signal-Swift.h"
#import "SignalApp.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalMessaging/BlockListUIUtils.h>
#import <SignalMessaging/ContactTableViewCell.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSTableViewController.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalMessaging/UIView+OWS.h>
#import <SignalMessaging/UIViewController+OWS.h>
#import <SignalServiceKit/FunctionalUtil.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSOutgoingMessage.h>

NS_ASSUME_NONNULL_BEGIN

@interface NewGroupViewController () <UIImagePickerControllerDelegate,
    UITextFieldDelegate,
    AvatarViewHelperDelegate,
    RecipientPickerDelegate,
    OWSNavigationView>

@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) AvatarViewHelper *avatarViewHelper;

@property (nonatomic, readonly) RecipientPickerViewController *recipientPicker;
@property (nonatomic, readonly) AvatarImageView *avatarView;
@property (nonatomic, readonly) UIImageView *cameraImageView;
@property (nonatomic, readonly) UITextField *groupNameTextField;

@property (nonatomic, readonly) NewGroupSeed *groupSeed;

@property (nonatomic, nullable) UIImage *groupAvatar;
@property (nonatomic) NSMutableSet<PickedRecipient *> *memberRecipients;

@property (nonatomic) BOOL hasUnsavedChanges;
@property (nonatomic) BOOL hasAppeared;

@end

#pragma mark -

@implementation NewGroupViewController

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (void)commonInit
{
    _groupSeed = [NewGroupSeed new];

    _messageSender = SSKEnvironment.shared.messageSender;
    _avatarViewHelper = [AvatarViewHelper new];
    _avatarViewHelper.delegate = self;

    self.memberRecipients = [NSMutableSet new];
}

- (void)generateNewSeed
{
    _groupSeed = [NewGroupSeed new];

    [self updateAvatarView];
}

#pragma mark - View Lifecycle

- (void)loadView
{
    [super loadView];

    self.title = [MessageStrings newGroupDefaultTitle];

    self.view.backgroundColor = Theme.backgroundColor;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"NEW_GROUP_CREATE_BUTTON",
                                                   @"The title for the 'create group' button.")
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(createNewGroup)
                       accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"create")];
    self.navigationItem.rightBarButtonItem.imageInsets = UIEdgeInsetsMake(0, -10, 0, 10);
    self.navigationItem.rightBarButtonItem.accessibilityLabel
        = NSLocalizedString(@"FINISH_GROUP_CREATION_LABEL", @"Accessibility label for finishing new group");

    // First section.

    UIView *firstSection = [self firstSectionHeader];
    [self.view addSubview:firstSection];
    [firstSection autoSetDimension:ALDimensionHeight toSize:100.f];
    [firstSection autoPinWidthToSuperview];
    [firstSection autoPinToTopLayoutGuideOfViewController:self withInset:0];

    _recipientPicker = [RecipientPickerViewController new];
    self.recipientPicker.delegate = self;
    self.recipientPicker.shouldShowGroups = NO;
    self.recipientPicker.allowsSelectingUnregisteredPhoneNumbers = NO;
    self.recipientPicker.shouldShowAlphabetSlider = NO;

    [self addChildViewController:self.recipientPicker];
    [self.view addSubview:self.recipientPicker.view];
    [self.recipientPicker.view autoPinEdgeToSuperviewSafeArea:ALEdgeLeading];
    [self.recipientPicker.view autoPinEdgeToSuperviewSafeArea:ALEdgeTrailing];
    [self.recipientPicker.view autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:firstSection];
    [self.recipientPicker.view autoPinEdgeToSuperviewEdge:ALEdgeBottom];
}

- (UIView *)firstSectionHeader
{
    UIView *firstSectionHeader = [UIView new];
    firstSectionHeader.userInteractionEnabled = YES;
    [firstSectionHeader
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(headerWasTapped:)]];
    firstSectionHeader.backgroundColor = Theme.backgroundColor;
    UIView *threadInfoView = [UIView new];
    [firstSectionHeader addSubview:threadInfoView];
    [threadInfoView autoPinWidthToSuperviewWithMargin:16.f];
    [threadInfoView autoPinHeightToSuperviewWithMargin:16.f];

    AvatarImageView *avatarView = [AvatarImageView new];
    _avatarView = avatarView;

    [threadInfoView addSubview:avatarView];
    [avatarView autoVCenterInSuperview];
    [avatarView autoPinLeadingToSuperviewMargin];
    [avatarView autoSetDimension:ALDimensionWidth toSize:kMediumAvatarSize];
    [avatarView autoSetDimension:ALDimensionHeight toSize:kMediumAvatarSize];

    UIImageView *cameraImageView = [UIImageView new];
    [cameraImageView setTemplateImageName:@"camera-outline-24" tintColor:Theme.secondaryTextAndIconColor];
    [threadInfoView addSubview:cameraImageView];

    [cameraImageView autoSetDimensionsToSize:CGSizeMake(32, 32)];
    cameraImageView.contentMode = UIViewContentModeCenter;
    cameraImageView.backgroundColor = Theme.backgroundColor;
    cameraImageView.layer.cornerRadius = 16;
    cameraImageView.layer.shadowColor =
        [(Theme.isDarkThemeEnabled ? Theme.darkThemeWashColor : Theme.primaryTextColor) CGColor];
    cameraImageView.layer.shadowOffset = CGSizeMake(1, 1);
    cameraImageView.layer.shadowOpacity = 0.5;
    cameraImageView.layer.shadowRadius = 4;

    [cameraImageView autoPinTrailingToEdgeOfView:avatarView];
    [cameraImageView autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:avatarView];
    _cameraImageView = cameraImageView;

    [self updateAvatarView];

    [avatarView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                             action:@selector(avatarTouched:)]];
    avatarView.userInteractionEnabled = YES;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, avatarView);

    UITextField *groupNameTextField = [OWSTextField new];
    _groupNameTextField = groupNameTextField;
    groupNameTextField.textColor = Theme.primaryTextColor;
    groupNameTextField.font = [UIFont ows_dynamicTypeTitle2Font];
    groupNameTextField.attributedPlaceholder =
        [[NSAttributedString alloc] initWithString:NSLocalizedString(@"NEW_GROUP_NAMEGROUP_REQUEST_DEFAULT",
                                                       @"Placeholder text for group name field")
                                        attributes:@{
                                            NSForegroundColorAttributeName : Theme.secondaryTextAndIconColor,
                                        }];
    groupNameTextField.delegate = self;
    [groupNameTextField addTarget:self
                           action:@selector(groupNameDidChange:)
                 forControlEvents:UIControlEventEditingChanged];
    [threadInfoView addSubview:groupNameTextField];
    [groupNameTextField autoVCenterInSuperview];
    [groupNameTextField autoPinTrailingToSuperviewMargin];
    [groupNameTextField autoPinLeadingToTrailingEdgeOfView:avatarView offset:16.f];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, groupNameTextField);

    return firstSectionHeader;
}

- (void)headerWasTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self.groupNameTextField becomeFirstResponder];
    }
}

- (void)avatarTouched:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self showChangeAvatarUI];
    }
}

- (void)removeRecipient:(PickedRecipient *)recipient
{
    [self.memberRecipients removeObject:recipient];
    self.recipientPicker.pickedRecipients = self.memberRecipients.allObjects;
}

- (void)addRecipient:(PickedRecipient *)recipient
{
    [self.memberRecipients addObject:recipient];
    self.hasUnsavedChanges = YES;
    self.recipientPicker.pickedRecipients = self.memberRecipients.allObjects;
}

#pragma mark - Methods

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    if (self.navigationController.viewControllers.count == 1) {
        self.navigationItem.leftBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                          target:self
                                                          action:@selector(dismissPressed)];
    }
}

- (void)dismissPressed
{
    [self.groupNameTextField resignFirstResponder];

    if (!self.hasUnsavedChanges) {
        // If user made no changes, dismiss.
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }

    __weak NewGroupViewController *weakSelf = self;
    [OWSActionSheets showPendingChangesActionSheetWithDiscardAction:^{
        [weakSelf dismissViewControllerAnimated:YES completion:nil];
    }];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    if (!self.hasAppeared) {
        [self.groupNameTextField becomeFirstResponder];
        self.hasAppeared = YES;
    }
}

#pragma mark - Actions

- (void)createNewGroup
{
    OWSAssertIsOnMainThread();

    [self.groupNameTextField acceptAutocorrectSuggestion];

    NSMutableArray<SignalServiceAddress *> *members =
        [[self.memberRecipients.allObjects map:^(PickedRecipient *recipient) {
            OWSAssertDebug(recipient.address.isValid);
            return recipient.address;
        }] mutableCopy];
    [members addObject:[self.recipientPicker.contactsViewHelper localAddress]];

    NSString *groupName = self.groupNameTextField.text;

    [self createGroupThreadWithName:groupName avatarImage:self.groupAvatar members:members newGroupSeed:self.groupSeed];
}

#pragma mark - Group Avatar

- (void)showChangeAvatarUI
{
    [self.avatarViewHelper showChangeAvatarUI];
}

- (void)setGroupAvatar:(nullable UIImage *)groupAvatar
{
    OWSAssertIsOnMainThread();

    _groupAvatar = groupAvatar;

    self.hasUnsavedChanges = YES;

    [self updateAvatarView];
}

- (void)updateAvatarView
{
    UIImage *_Nullable groupAvatar = self.groupAvatar;
    self.cameraImageView.hidden = groupAvatar != nil;

    if (!groupAvatar) {
        NSData *groupId = self.groupSeed.possibleGroupId;
        NSString *conversationColorName = [TSGroupThread defaultConversationColorNameForGroupId:groupId];
        groupAvatar = [OWSGroupAvatarBuilder defaultAvatarForGroupId:groupId
                                               conversationColorName:conversationColorName
                                                            diameter:kMediumAvatarSize];
    }

    self.avatarView.image = groupAvatar;
}

#pragma mark - Event Handling

- (void)backButtonPressed
{
    [self.groupNameTextField resignFirstResponder];

    if (!self.hasUnsavedChanges) {
        // If user made no changes, return to 'compose' view.
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    __weak NewGroupViewController *weakSelf = self;
    [OWSActionSheets showPendingChangesActionSheetWithDiscardAction:^{
        [weakSelf.navigationController popViewControllerAnimated:YES];
    }];
}

- (void)groupNameDidChange:(id)sender
{
    self.hasUnsavedChanges = YES;
}

#pragma mark - Text Field Delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self.groupNameTextField resignFirstResponder];
    return NO;
}
#pragma mark - AvatarViewHelperDelegate

- (nullable NSString *)avatarActionSheetTitle
{
    return NSLocalizedString(
        @"NEW_GROUP_ADD_PHOTO_ACTION", @"Action Sheet title prompting the user for a group avatar");
}

- (void)avatarDidChange:(UIImage *)image
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(image);

    self.groupAvatar = image;
}

- (UIViewController *)fromViewController
{
    return self;
}

- (BOOL)hasClearAvatarAction
{
    return NO;
}

#pragma mark - RecipientPickerDelegate

- (void)recipientPicker:(RecipientPickerViewController *)recipientPickerViewController
     didSelectRecipient:(PickedRecipient *)recipient
{
    OWSAssertDebug(recipient.address.isValid);

    __weak __typeof(self) weakSelf;
    BOOL isCurrentMember = [self.memberRecipients containsObject:recipient];
    BOOL isBlocked = [self.recipientPicker.contactsViewHelper isSignalServiceAddressBlocked:recipient.address];
    if (isCurrentMember) {
        [self removeRecipient:recipient];
    } else if (isBlocked) {
        [BlockListUIUtils showUnblockAddressActionSheet:recipient.address
                                     fromViewController:self
                                        completionBlock:^(BOOL isStillBlocked) {
                                            if (!isStillBlocked) {
                                                [weakSelf addRecipient:recipient];
                                                [weakSelf.navigationController popToViewController:self animated:YES];
                                            }
                                        }];
    } else {
        BOOL didShowSNAlert = [SafetyNumberConfirmationAlert
            presentAlertIfNecessaryWithAddress:recipient.address
                              confirmationText:NSLocalizedString(@"SAFETY_NUMBER_CHANGED_CONFIRM_"
                                                                 @"ADD_TO_GROUP_ACTION",
                                                   @"button title to confirm adding "
                                                   @"a recipient to a group when "
                                                   @"their safety "
                                                   @"number has recently changed")
                                    completion:^(BOOL didConfirmIdentity) {
                                        if (didConfirmIdentity) {
                                            [weakSelf addRecipient:recipient];
                                            [weakSelf.navigationController popToViewController:self animated:YES];
                                        }
                                    }];
        if (didShowSNAlert) {
            return;
        }

        [self addRecipient:recipient];
        [self.navigationController popToViewController:self animated:YES];
    }
}

- (RecipientPickerRecipientState)recipientPicker:(RecipientPickerViewController *)recipientPickerViewController
                              canSelectRecipient:(PickedRecipient *)recipient
{
    return RecipientPickerRecipientStateCanBeSelected;
}

- (void)recipientPicker:(RecipientPickerViewController *)recipientPickerViewController
    willRenderRecipient:(PickedRecipient *)recipient
{
    // Do nothing.
}

- (AnyPromise *)recipientPicker:(RecipientPickerViewController *)recipientPickerViewController
       prepareToSelectRecipient:(PickedRecipient *)recipient
{
    OWSFailDebug(@"This method should not called.");
    return [AnyPromise promiseWithValue:@(1)];
}

- (void)recipientPicker:(RecipientPickerViewController *)recipientPickerViewController
    showInvalidRecipientAlert:(PickedRecipient *)recipient
{
    OWSFailDebug(@"Unexpected error.");
}

- (nullable NSString *)recipientPicker:(RecipientPickerViewController *)recipientPickerViewController
          accessoryMessageForRecipient:(PickedRecipient *)recipient
{
    OWSAssertDebug(recipient.address.isValid);

    BOOL isCurrentMember = [self.memberRecipients containsObject:recipient];
    BOOL isBlocked = [self.recipientPicker.contactsViewHelper isSignalServiceAddressBlocked:recipient.address];

    if (isCurrentMember) {
        // In the "contacts" section, we label members as such when editing an existing
        // group.
        return NSLocalizedString(@"NEW_GROUP_MEMBER_LABEL", @"An indicator that a user is a member of the new group.");
    } else if (isBlocked) {
        return MessageStrings.conversationIsBlocked;
    } else {
        return nil;
    }
}

- (void)recipientPickerTableViewWillBeginDragging:(RecipientPickerViewController *)recipientPickerViewController
{
    [self.groupNameTextField resignFirstResponder];
}

- (void)recipientPickerNewGroupButtonWasPressed
{
    OWSFailDebug(@"Invalid action.");
}

- (NSArray<UIView *> *)recipientPickerCustomHeaderViews
{
    return @[];
}

#pragma mark - OWSNavigationView

- (BOOL)shouldCancelNavigationBack
{
    BOOL result = self.hasUnsavedChanges;
    if (self.hasUnsavedChanges) {
        [self backButtonPressed];
    }
    return result;
}

@end

NS_ASSUME_NONNULL_END
