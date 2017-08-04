//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSSetProfileRequest.h"
#import "NSData+Base64.h"
#import "TSConstants.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSSetProfileRequest

- (nullable instancetype)initWithProfileName:(NSData *_Nullable)profileNameEncrypted
                                   avatarUrl:(NSString *_Nullable)avatarUrl
                                avatarDigest:(NSData *_Nullable)avatarDigest
{

    self = [super initWithURL:[NSURL URLWithString:textSecureSetProfileAPI]];

    self.HTTPMethod = @"PUT";

    if (profileNameEncrypted.length > 0) {
        self.parameters[@"name"] = [profileNameEncrypted base64EncodedString];
    }
    if (avatarUrl.length > 0) {
        self.parameters[@"avatar"] = [[avatarUrl dataUsingEncoding:NSUTF8StringEncoding] base64EncodedString];
    }
    if (avatarDigest.length > 0) {
        self.parameters[@"avatarDigest"] = [avatarDigest base64EncodedString];
    }

    return self;
}

@end

NS_ASSUME_NONNULL_END
