//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWS2FAManager.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSRequestFactory.h"
#import "TSNetworkManager.h"
#import "TSStorageManager.h"
#import "YapDatabaseConnection+OWS.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const NSNotificationName_2FAStateDidChange = @"NSNotificationName_2FAStateDidChange";

NSString *const kOWS2FAManager_Collection = @"kOWS2FAManager_Collection";
NSString *const kOWS2FAManager_IsEnabledKey = @"kOWS2FAManager_IsEnabledKey";
NSString *const kOWS2FAManager_LastSuccessfulReminderDateKey = @"kOWS2FAManager_LastSuccessfulReminderDateKey";
NSString *const kOWS2FAManager_PinCode = @"kOWS2FAManager_PinCode";
NSString *const kOWS2FAManager_RepetitionInterval = @"kOWS2FAManager_RepetitionInterval";

const NSUInteger kHourSecs = 60 * 60;
const NSUInteger kDaySecs = kHourSecs * 24;

@interface OWS2FAManager ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) TSNetworkManager *networkManager;

@end

#pragma mark -

@implementation OWS2FAManager

+ (instancetype)sharedManager
{
    static OWS2FAManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    TSNetworkManager *networkManager = [TSNetworkManager sharedManager];

    return [self initWithStorageManager:storageManager networkManager:networkManager];
}

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
                        networkManager:(TSNetworkManager *)networkManager
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(storageManager);
    OWSAssert(networkManager);

    _dbConnection = storageManager.newDatabaseConnection;
    _networkManager = networkManager;

    OWSSingletonAssert();

    return self;
}

- (BOOL)is2FAEnabled
{
    return [self.dbConnection boolForKey:kOWS2FAManager_IsEnabledKey
                            inCollection:kOWS2FAManager_Collection
                            defaultValue:NO];
}

- (void)setIs2FAEnabled:(BOOL)value
{
    [self.dbConnection setBool:value forKey:kOWS2FAManager_IsEnabledKey inCollection:kOWS2FAManager_Collection];

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:NSNotificationName_2FAStateDidChange
                                                             object:nil
                                                           userInfo:nil];
}

- (void)mark2FAAsEnabledWithPin:(NSString *)pin
{
    [self setIs2FAEnabled:YES];
    [self storePinCode:pin];
}

- (void)requestEnable2FAWithPin:(NSString *)pin success:(nullable OWS2FASuccess)success failure:(nullable OWS2FAFailure)failure
{
    OWSAssert(pin.length > 0);
    OWSAssert(success);
    OWSAssert(failure);

    TSRequest *request = [OWSRequestFactory enable2FARequestWithPin:pin];
    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            OWSAssertIsOnMainThread();

            [self mark2FAAsEnabledWithPin:pin];
            if (success) {
                success();
            }
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            OWSAssertIsOnMainThread();

            if (failure) {
                failure(error);
            }
        }];
}

- (void)disable2FAWithSuccess:(nullable OWS2FASuccess)success failure:(nullable OWS2FAFailure)failure
{
    TSRequest *request = [OWSRequestFactory disable2FARequest];
    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            OWSAssertIsOnMainThread();

            [self setIs2FAEnabled:NO];

            if (success) {
                success();
            }
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            OWSAssertIsOnMainThread();

            if (failure) {
                failure(error);
            }
        }];
}


#pragma mark - Reminders

- (void)storePinCode:(nullable NSString *)pinCode
{
    [self.dbConnection setObject:pinCode
                          forKey:kOWS2FAManager_PinCode
                    inCollection:kOWS2FAManager_Collection];
}

- (nullable NSString *)pinCode
{
    return [self.dbConnection objectForKey:kOWS2FAManager_PinCode
                              inCollection:kOWS2FAManager_Collection];
}

- (nullable NSDate *)lastSuccessfulReminderDate
{
    return [self.dbConnection dateForKey:kOWS2FAManager_LastSuccessfulReminderDateKey
                            inCollection:kOWS2FAManager_Collection];
}

- (void)setLastSuccessfulReminderDate:(nullable NSDate *)date
{
    DDLogDebug(@"%@ Seting setLastSuccessfulReminderDate:%@", self.logTag, date);
    [self.dbConnection setDate:date
                        forKey:kOWS2FAManager_LastSuccessfulReminderDateKey
                  inCollection:kOWS2FAManager_Collection];
}

- (BOOL)isDueForReminder
{
    if (!self.is2FAEnabled) {
        return NO;
    }
    
    return self.nextReminderDate.timeIntervalSinceNow < 0;
}

- (NSDate *)nextReminderDate
{
    NSDate *lastSuccessfulReminderDate = self.lastSuccessfulReminderDate ?: [NSDate distantPast];
    
    return [lastSuccessfulReminderDate dateByAddingTimeInterval:self.repetitionInterval];
}

- (NSArray<NSNumber *> *)allRepetitionIntervals
{
    // Keep sorted monotonically increasing.
    return  @[
              @(6 * kHourSecs),
              @(12 * kHourSecs),
              @(1 * kDaySecs),
              @(3 * kDaySecs),
              @(7  * kDaySecs),
              ];
}

- (double)defaultRepetitionInterval
{
    return self.allRepetitionIntervals.firstObject.doubleValue;
}

- (NSTimeInterval)repetitionInterval
{
    return [self.dbConnection doubleForKey:kOWS2FAManager_RepetitionInterval
                              inCollection:kOWS2FAManager_Collection
                              defaultValue:self.defaultRepetitionInterval];
}

- (void)updateRepetitionIntervalWithWasSuccessful:(BOOL)wasSuccessful
{
    if (wasSuccessful) {
        self.lastSuccessfulReminderDate = [NSDate new];
    }
    
    NSTimeInterval oldInterval = self.repetitionInterval;
    NSTimeInterval newInterval = [self adjustRepetitionInterval:oldInterval wasSuccessful:wasSuccessful];
    
    DDLogInfo(@"%@ %@ guess. Updating repetition interval: %f -> %f", self.logTag, (wasSuccessful ? @"successful" : @"failed"), oldInterval, newInterval);
    [self.dbConnection setDouble:newInterval
                          forKey:kOWS2FAManager_RepetitionInterval
                    inCollection:kOWS2FAManager_Collection];
}

- (NSTimeInterval)adjustRepetitionInterval:(NSTimeInterval)oldInterval wasSuccessful:(BOOL)wasSuccessful
{
    NSArray<NSNumber *> *allIntervals = self.allRepetitionIntervals;
    
    NSUInteger oldIndex = [allIntervals indexOfObjectPassingTest:^BOOL(NSNumber * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return oldInterval >= (NSTimeInterval)obj.doubleValue;
    }];
    
    NSUInteger newIndex;
    if (wasSuccessful) {
        newIndex = oldIndex + 1;
    } else {
        newIndex = oldIndex - 1;
    }
    
    // clamp to be valid
    newIndex = MAX(0, MIN(allIntervals.count - 1, newIndex));
    
    NSTimeInterval newInterval = allIntervals[newIndex].doubleValue;
    return newInterval;
}

@end

NS_ASSUME_NONNULL_END
