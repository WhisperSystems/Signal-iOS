//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "EncodedAudioPacket.h"

@implementation EncodedAudioPacket

@synthesize audioData, sequenceNumber;

+ (EncodedAudioPacket *)encodedAudioPacketWithAudioData:(NSData *)audioData andSequenceNumber:(uint16_t)sequenceNumber {
    ows_require(audioData != nil);
    EncodedAudioPacket *p = [EncodedAudioPacket new];
    p->audioData          = audioData;
    p->sequenceNumber     = sequenceNumber;
    return p;
}

@end
