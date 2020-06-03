//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSConversationSettingsViewDelegate.h"
#import "OWSTableViewController.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class ThreadViewModel;

// GroupsV2 TODO: Remove this VC.
@interface OWSConversationSettingsViewController : OWSTableViewController

@property (nonatomic, weak) id<OWSConversationSettingsViewDelegate> conversationSettingsViewDelegate;

@property (nonatomic) BOOL showVerificationOnAppear;

- (void)configureWithThreadViewModel:(ThreadViewModel *)threadViewModel;

@end

NS_ASSUME_NONNULL_END
