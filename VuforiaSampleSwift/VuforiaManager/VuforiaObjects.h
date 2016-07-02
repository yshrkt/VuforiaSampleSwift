//
//  VuforiaObjects.h
//  VuforiaSampleSwift
//
//  Created by Yoshihiro Kato on 2016/07/02.
//  Copyright © 2016年 Yoshihiro Kato. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, VuforiaTrackableResultStatus) {
    VuforiaTrackableResultStatus_Unknown,            ///< The state of the TrackableResult is unknown
    VuforiaTrackableResultStatus_Undefined,          ///< The state of the TrackableResult is not defined
    ///< (this TrackableResult does not have a state)
    VuforiaTrackableResultStatus_Detected,           ///< The TrackableResult was detected
    VuforiaTrackableResultStatus_Tracked,            ///< The TrackableResult was tracked
    VuforiaTrackableResultStatus_Extended_tracked    ///< The Trackable Result was extended tracked
};

@interface VuforiaFrame : NSObject
@end

@interface VuforiaTrackable : NSObject

@property (nonatomic, readonly)NSInteger identifier;
@property (nonatomic, readonly)NSString* name;

@end

@interface VuforiaTrackableResult : NSObject

@property (nonatomic, readonly)NSTimeInterval timeStamp;
@property (nonatomic, readonly)VuforiaTrackableResultStatus status;
@property (nonatomic, readonly)VuforiaTrackable* trackable;

@end

@interface VuforiaState : NSObject

@property (nonatomic, readonly)VuforiaFrame* frame;
@property (nonatomic, readonly)int numberOfTrackables;
@property (nonatomic, readonly)int numberOfTrackableResults;


- (VuforiaTrackable*)trackableAtIndex:(int)index;
- (VuforiaTrackableResult*)trackableResultAtIndex:(int)index;

@end

