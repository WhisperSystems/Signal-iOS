//
//  PrivacySettingsTableViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 05/01/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "PrivacySettingsTableViewController.h"

#import "Environment.h"
#import "PropertyListPreferences.h"
#import "TouchIDManager.h"
#import "UIUtil.h"
#import <25519/Curve25519.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PrivacySettingsTableViewControllerSectionIndex) {
    PrivacySettingsTableViewControllerSectionIndexSecurity,
    PrivacySettingsTableViewControllerSectionIndexHistoryLog,
    PrivacySettingsTableViewControllerSectionIndexBlockOnIdentityChange
};

/// A row in `PrivacySettingsTableViewControllerSectionIndexSecurity`.
typedef NS_ENUM(NSInteger, PrivacySettingsTableViewControllerSecurityRowIndex) {
    PrivacySettingsTableViewControllerSecurityRowIndexTouchID,
    PrivacySettingsTableViewControllerSecurityRowIndexScreen
};

@interface PrivacySettingsTableViewController ()

@property (nonatomic, strong) UITableViewCell *enableTouchIDSecurityCell;
@property (nonatomic, strong) UISwitch *enableTouchIDSecuritySwitch;
@property (nonatomic, strong) UITableViewCell *enableScreenSecurityCell;
@property (nonatomic, strong) UISwitch *enableScreenSecuritySwitch;
@property (nonatomic, strong) UITableViewCell *blockOnIdentityChangeCell;
@property (nonatomic, strong) UISwitch *blockOnIdentityChangeSwitch;
@property (nonatomic, strong) UITableViewCell *clearHistoryLogCell;

@end

@implementation PrivacySettingsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)loadView {
    [super loadView];

    self.title = NSLocalizedString(@"SETTINGS_PRIVACY_TITLE", @"");
    
    // TouchID Cell
    self.enableTouchIDSecurityCell = [[UITableViewCell alloc] init];
    self.enableTouchIDSecurityCell.textLabel.text = NSLocalizedString(@"SETTINGS_TOUCHID_SECURITY", @"");
    
    self.enableTouchIDSecuritySwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.enableTouchIDSecuritySwitch.enabled = NO; // Disable until we verify
    [self.enableTouchIDSecuritySwitch addTarget:self
                                         action:@selector(didToggleTouchIDSwitch:)
                               forControlEvents:UIControlEventTouchUpInside];
    
    // Enable Screen Security Cell
    self.enableScreenSecurityCell                = [[UITableViewCell alloc] init];
    self.enableScreenSecurityCell.textLabel.text = NSLocalizedString(@"SETTINGS_SCREEN_SECURITY", @"");
    self.enableScreenSecuritySwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.enableScreenSecurityCell.accessoryView          = self.enableScreenSecuritySwitch;
    self.enableScreenSecurityCell.userInteractionEnabled = YES;
    [self.enableScreenSecuritySwitch setOn:[Environment.preferences screenSecurityIsEnabled]];
    [self.enableScreenSecuritySwitch addTarget:self
                                        action:@selector(didToggleScreenSecuritySwitch:)
                              forControlEvents:UIControlEventTouchUpInside];

    // Clear History Log Cell
    self.clearHistoryLogCell                = [[UITableViewCell alloc] init];
    self.clearHistoryLogCell.textLabel.text = NSLocalizedString(@"SETTINGS_CLEAR_HISTORY", @"");
    self.clearHistoryLogCell.accessoryType  = UITableViewCellAccessoryDisclosureIndicator;

    // Block Identity on KeyChange
    self.blockOnIdentityChangeCell = [UITableViewCell new];
    self.blockOnIdentityChangeCell.textLabel.text
        = NSLocalizedString(@"SETTINGS_BLOCK_ON_IDENTITY_CHANGE_TITLE", @"Table cell label");
    self.blockOnIdentityChangeSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.blockOnIdentityChangeCell.accessoryView = self.blockOnIdentityChangeSwitch;
    [self.blockOnIdentityChangeSwitch setOn:[Environment.preferences shouldBlockOnIdentityChange]];
    [self.blockOnIdentityChangeSwitch addTarget:self
                                         action:@selector(didToggleBlockOnIdentityChangeSwitch:)
                               forControlEvents:UIControlEventTouchUpInside];
        
    self.enableTouchIDSecurityCell.accessoryView = self.enableTouchIDSecuritySwitch;
    self.enableTouchIDSecurityCell.userInteractionEnabled = YES;
    
    //Clear History Log Cell
    self.clearHistoryLogCell = [[UITableViewCell alloc]init];
    self.clearHistoryLogCell.textLabel.text = NSLocalizedString(@"SETTINGS_CLEAR_HISTORY", @"");
    self.clearHistoryLogCell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    [self detectTouchID];
    [self validateSecuritySwitches];
}

/// Enables or disables the TouchID switch based on hardware availability.
- (void)detectTouchID {
    if (TouchIDManager.shared.isTouchIDAvailable) {
        self.enableTouchIDSecuritySwitch.enabled = YES;
    } else {
        // Cannot use touchID at this time / on this device
        self.enableTouchIDSecuritySwitch.enabled = NO;
    }
    
#if DEBUG
    // Always Show TouchID controls for debugging!
    self.enableTouchIDSecuritySwitch.enabled = YES;
#endif
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ((PrivacySettingsTableViewControllerSectionIndex)section) {
        case PrivacySettingsTableViewControllerSectionIndexSecurity:
            return 2; // TouchID and Screen Security
        case PrivacySettingsTableViewControllerSectionIndexHistoryLog:
            return 1;
        case PrivacySettingsTableViewControllerSectionIndexBlockOnIdentityChange:
            return 1;
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    switch ((PrivacySettingsTableViewControllerSectionIndex)section) {
        case PrivacySettingsTableViewControllerSectionIndexSecurity:
            return NSLocalizedString(@"SETTINGS_SCREEN_SECURITY_DETAIL", nil);
        case PrivacySettingsTableViewControllerSectionIndexBlockOnIdentityChange:
            return NSLocalizedString(
                @"SETTINGS_BLOCK_ON_IDENITY_CHANGE_DETAIL", @"User settings section footer, a detailed explanation");
        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case PrivacySettingsTableViewControllerSectionIndexSecurity:
            switch ((PrivacySettingsTableViewControllerSecurityRowIndex)indexPath.row) {
                case PrivacySettingsTableViewControllerSecurityRowIndexTouchID:
                    return self.enableTouchIDSecurityCell;
                case PrivacySettingsTableViewControllerSecurityRowIndexScreen:
                    return self.enableScreenSecurityCell;
            }
        case PrivacySettingsTableViewControllerSectionIndexHistoryLog:
            return self.clearHistoryLogCell;
        case PrivacySettingsTableViewControllerSectionIndexBlockOnIdentityChange:
            return self.blockOnIdentityChangeCell;
        default: {
            DDLogError(@"%@ Requested unknown table view cell for row at indexPath: %@", self.tag, indexPath);
            return [UITableViewCell new];
        }
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case PrivacySettingsTableViewControllerSectionIndexSecurity:
            return NSLocalizedString(@"SETTINGS_SECURITY_TITLE", @"Section header");
        case PrivacySettingsTableViewControllerSectionIndexHistoryLog:
            return NSLocalizedString(@"SETTINGS_HISTORYLOG_TITLE", @"Section header");
        case PrivacySettingsTableViewControllerSectionIndexBlockOnIdentityChange:
            return NSLocalizedString(@"SETTINGS_PRIVACY_VERIFICATION_TITLE", @"Section header");
        default:
            return nil;
    }
}

-(BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    switch ((PrivacySettingsTableViewControllerSectionIndex)indexPath.section) {
        case PrivacySettingsTableViewControllerSectionIndexHistoryLog:
            return YES;
        case PrivacySettingsTableViewControllerSectionIndexSecurity:
        case PrivacySettingsTableViewControllerSectionIndexBlockOnIdentityChange:
            return NO;
    }
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    switch ((PrivacySettingsTableViewControllerSectionIndex)indexPath.section) {
        case PrivacySettingsTableViewControllerSectionIndexHistoryLog: {
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil
                                                                                     message:NSLocalizedString(@"SETTINGS_DELETE_HISTORYLOG_CONFIRMATION", @"Alert message before user confirms clearing history")
                                                                              preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                                    style:UIAlertActionStyleCancel
                                                                  handler:nil];
            [alertController addAction:dismissAction];

            UIAlertAction *deleteAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"SETTINGS_DELETE_HISTORYLOG_CONFIRMATION_BUTTON", @"")
                                                                   style:UIAlertActionStyleDestructive
                                                                 handler:^(UIAlertAction * _Nonnull action) {
                                                                     [[TSStorageManager sharedManager] deleteThreadsAndMessages];
                                                                 }];
            [alertController addAction:deleteAction];

            [self presentViewController:alertController animated:true completion:nil];
            break;
        }
        case PrivacySettingsTableViewControllerSectionIndexSecurity:
        case PrivacySettingsTableViewControllerSectionIndexBlockOnIdentityChange:
            // These cells aren't tappable
            break;
    }
}

#pragma mark - Toggle

- (void)didToggleScreenSecuritySwitch:(UISwitch *)sender
{
    BOOL enabled = self.enableScreenSecuritySwitch.isOn;
    DDLogInfo(@"%@ toggled screen security: %@", self.tag, enabled ? @"ON" : @"OFF");
    [Environment.preferences setScreenSecurity:enabled];
    [self validateSecuritySwitches];
}

- (void)didToggleTouchIDSwitch:(UISwitch *)sender
{
    // Make the user verify with TouchID when enabling/disabling.
    BOOL enabled = self.enableTouchIDSecuritySwitch.isOn;
    DDLogInfo(@"%@ toggled touchID: %@", self.tag, enabled ? @"ON" : @"OFF");
    __weak typeof(self) weakSelf = self;
    [TouchIDManager.shared authenticateViaTouchIDCompletion:^(TouchIDAuthResult result) {
        switch (result) {
            case TouchIDAuthResultUnavailable:
            case TouchIDAuthResultUserCanceled:
            case TouchIDAuthResultFailed:
                // restore switch state
                weakSelf.enableTouchIDSecuritySwitch.on = !enabled;
                break;
            case TouchIDAuthResultSuccess:
                [Environment.preferences setTouchIDEnabled:enabled];
                if (enabled) {
                    // If TouchID is on, Screen Security must also be on.
                    [Environment.preferences setScreenSecurity:YES];
                }
                break;
        }
        [weakSelf validateSecuritySwitches];
    }];
}

/// Ensures that security switches reflect the user's preferences.
- (void)validateSecuritySwitches
{
    self.enableTouchIDSecuritySwitch.on = Environment.preferences.touchIDIsEnabled;
    // TouchID requires ScreenSecurity to be enabled.
    self.enableScreenSecuritySwitch.enabled = !Environment.preferences.touchIDIsEnabled;
    self.enableScreenSecuritySwitch.on = Environment.preferences.screenSecurityIsEnabled;
}

- (void)didToggleBlockOnIdentityChangeSwitch:(UISwitch *)sender
{
    BOOL enabled = self.blockOnIdentityChangeSwitch.isOn;
    DDLogInfo(@"%@ toggled blockOnIdentityChange: %@", self.tag, enabled ? @"ON" : @"OFF");
    [Environment.preferences setShouldBlockOnIdentityChange:enabled];
}

#pragma mark - Log util

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
