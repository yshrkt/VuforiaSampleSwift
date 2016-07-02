//
//  VuforiaManager.h
//  VuforiaSample
//
//  Created by Yoshihiro Kato on 2016/07/02.
//  Copyright © 2016年 Yoshihiro Kato. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "VuforiaObjects.h"
#import "VuforiaEAGLView.h"

typedef NS_ENUM(NSInteger, VuforiaError) {
    VuforiaError_InitializeError = -1,     ///< Error during initialization
    VuforiaError_DeviceNotSupported = -2,  ///< The device is not supported
    VuforiaError_NoCameraAccess = -3,                     ///< Cannot access the camera
    VuforiaError_MissingKey = -4,            ///< License key is missing
    VuforiaError_InvalidKey = -5,            ///< Invalid license key passed to SDK
    VuforiaError_NoNetworkPermanent = -6,   ///< Unable to verify license key due to network (Permanent error)
    VuforiaError_NoNetworkTransient = -7,   ///< Unable to verify license key due to network (Transient error)
    VuforiaError_CanceledKey = -8,           ///< Provided key is no longer valid
    VuforiaError_ProductTypeMismatch = -9,  ///< Provided key is not valid for this product
    VuforiaError_DeviceNotDetected = -10,
    
    VuforiaError_InitializingVuforia = 100,
    
    VuforiaError_InitializingCamera = 110,
    VuforiaError_StartingCamera = 111,
    VuforiaError_StoppingCamera = 112,
    VuforiaError_DeinitCamara = 113,
    
    VuforiaError_InitTrackers = 120,
    VuforiaError_LoadingTrackersData = 121,
    VuforiaError_StartingTrackers = 122,
    VuforiaError_StoppingTrackers = 123,
    VuforiaError_UnloadingTrackersData = 124,
    VuforiaError_DeinitTrackers = 125,
    
    VuforiaError_CameraNotStarted = 150,
};

@class VuforiaManager;
@class VuforiaEAGLView;

@protocol VuforiaManagerDelegate <NSObject>

- (void)vuforiaManagerDidFinishPreparing:(VuforiaManager*) manager;
- (void)vuforiaManager:(VuforiaManager*)manager didFailToPreparingWithError:(NSError*)error;
- (void)vuforiaManager:(VuforiaManager *)manager didUpdateWithState:(VuforiaState*)state;

@end

@interface VuforiaManager : NSObject

@property (nonatomic, weak) id<VuforiaManagerDelegate> delegate;
@property (nonatomic, readonly)BOOL isRetinaDisplay;
@property (nonatomic, readonly)BOOL extendedTrackingEnabled;
@property (nonatomic, readonly)BOOL continuousAutofocusEnabled;
@property (nonatomic, readonly)BOOL flashEnabled;
@property (nonatomic, readonly)BOOL frontCameraEnabled;
@property (nonatomic, readonly)CGRect viewport;
@property (nonatomic, readonly)VuforiaEAGLView* eaglView;

- (instancetype)init __attribute__((unavailable("init is not available")));
- (instancetype)initWithLicenseKey:(NSString*)licenseKey dataSetFile:(NSString*)path;

- (CGSize)preferredARFrameSize;


- (void)prepareWithOrientation:(UIInterfaceOrientation)orientation;

- (BOOL)setExtendedTrackingEnabled:(BOOL)enabled;
- (BOOL)setContinuousAutofocusEnabled:(BOOL)enabled;
- (BOOL)setFlashEnabled:(BOOL)enabled;
- (BOOL)setFrontCameraEnabled:(BOOL)enabled;

- (BOOL)resume:(NSError **)error;
- (BOOL)pause:(NSError **)error;

- (BOOL)start:(NSError **)error;
- (BOOL)stop:(NSError **)error;


@end