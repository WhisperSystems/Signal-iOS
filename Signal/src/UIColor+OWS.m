//
//  UIColor+UIColor_OWS.m
//  Signal
//
//  Created by Dylan Bourgeois on 25/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "UIColor+OWS.h"
#import "Cryptography.h"

@implementation UIColor (OWS)


+ (UIColor*) ows_materialBlueColor {
    // blue: #2090EA
    return [UIColor colorWithRed:32.f/255.f green:144.f/255.f blue:234.f/255.f  alpha:1.f];
}

+ (UIColor*) ows_blackColor {
    // black: #080A00
    return [UIColor colorWithRed:8.f/255.f green:10.f/255.f blue:0./255.f  alpha:1.f];
}


+ (UIColor*) ows_darkGrayColor {
    return [UIColor colorWithRed:81.f/255.f green:81.f/255.f blue:81.f/255.f alpha:1.f];
}

+ (UIColor*) ows_darkBackgroundColor {
    return [UIColor colorWithRed:35.f/255.f green:31.f/255.f blue:32.f/255.f alpha:1.f];
}

+ (UIColor *) ows_fadedBlueColor {
    // blue: #B6DEF4
    return [UIColor colorWithRed:182.f/255.f green:222.f/255.f blue:244.f/255.f  alpha:1.f];
}

+ (UIColor *) ows_yellowColor {
    // gold: #FFBB5C
    return [UIColor colorWithRed:245.f/255.f green:186.f/255.f blue:98.f/255.f alpha:1.f];
}

+ (UIColor *) ows_greenColor {
    // green: #92FF8A
    return [UIColor colorWithRed:146.f/255.f green:255.f/255.f blue:138.f/255.f alpha:1.f];
}

+ (UIColor *) ows_redColor {
    // red: #FF3867
    return [UIColor colorWithRed:255./255.f green:56.f/255.f blue:103.f/255.f alpha:1.f];
}

+ (UIColor *) ows_lightBackgroundColor {
    return [UIColor colorWithRed:242.f/255.f green:242.f/255.f blue:242.f/255.f alpha:1.f];
}

+ (UIColor*) backgroundColorForContact:(NSString*)contactIdentifier {
    NSArray *colors = @[[UIColor colorWithRed:213.f/255.f green:190.f/255.f blue:112.f/255.f alpha:1.f],
                        [UIColor colorWithRed:18.f/255.f green:211.f/255.f blue:102.f/255.f alpha:1.f],
                        [UIColor colorWithRed:32.f/255.f green:144.f/255.f blue:234.f/255.f alpha:1.f],
                        [UIColor colorWithRed:180.f/255.f green:138.f/255.f blue:255.f/255.f alpha:1.f],
                        [UIColor colorWithRed:255.f/255.f green:145.f/255.f blue:81.f/255.f alpha:1.f]];
    NSData *contactData = [contactIdentifier dataUsingEncoding:NSUTF8StringEncoding];
    NSData *hashData = [Cryptography  computeSHA256:contactData  truncatedToBytes:1];
    unsigned int choose;
    [hashData getBytes:&choose range:NSMakeRange(0, 1)];
    return [colors objectAtIndex:(choose % 5)];
}


@end

