//
//  VuforiaManager.m
//  VuforiaSample
//
//  Created by Yoshihiro Kato on 2016/07/02.
//  Copyright © 2016年 Yoshihiro Kato. All rights reserved.
//

#import "VuforiaManager.h"
#import <Vuforia/Vuforia.h>
#import <Vuforia/Vuforia_iOS.h>
#import <Vuforia/TrackerManager.h>
#import <Vuforia/ObjectTracker.h>
#import <Vuforia/Tool.h>
#import <Vuforia/Renderer.h>
#import <Vuforia/CameraDevice.h>
#import <Vuforia/VideoBackgroundConfig.h>
#import <Vuforia/UpdateCallback.h>
#import <Vuforia/DataSet.h>
#import <Vuforia/Trackable.h>

#define DEBUG_SAMPLE_APP 1

@interface VuforiaFrame ()
- (instancetype)initWithFrame:(Vuforia::Frame)frame;
@end

@interface VuforiaTrackable ()
- (instancetype)initWithTrackable:(const Vuforia::Trackable*)trackable;
@end

@interface VuforiaTrackableResult ()
- (instancetype)initWithTrackableResult:(const Vuforia::TrackableResult*)result;
@end

@interface VuforiaState ()
- (instancetype)initWithState:(Vuforia::State*)state;
@end

@interface VuforiaEAGLView ()
- (void)setProjectionMatrix:(Vuforia::Matrix44F)matrix;
@end


namespace {
    // --- Data private to this unit ---
    
    // instance of the seesion
    // used to support the Vuforia callback
    // there should be only one instance of a session
    // at any given point of time
    VuforiaManager* instance = nil;
    
    // Vuforia initialisation flags (passed to Vuforia before initialising)
    int mVuforiaInitFlags = Vuforia::GL_20;
    
    // camera to use for the session
    Vuforia::CameraDevice::CAMERA_DIRECTION mCamera = Vuforia::CameraDevice::CAMERA_DIRECTION_DEFAULT;
    
    // class used to support the Vuforia callback mechanism
    class VuforiaApplication_UpdateCallback : public Vuforia::UpdateCallback {
        virtual void Vuforia_onUpdate(Vuforia::State& state);
    } vuforiaUpdate;
    
    // NSerror domain for errors coming from the Sample application template classes
    NSString* VUFORIA_MANAGER_ERROR_DOMAIN = @"vuforia_manager";
}

#pragma mark - VuforiaManager
@implementation VuforiaManager {
    NSString* _licenseKey;
    NSString* _dataSetFile;
    
    Vuforia::DataSet*  _dataSet;
    
    BOOL _isCameraActive;
    BOOL _isCameraStarted;
    BOOL _isRetinaDisplay;
    UIInterfaceOrientation _arViewOrientation;
    BOOL _isActivityInPortraitMode;
    
    BOOL _extendedTrackingEnabled;
    BOOL _continuousAutofocusEnabled;
    BOOL _flashEnabled;
    BOOL _frontCameraEnabled;
    
    Vuforia::Matrix44F _projectionMatrix;
    
    CGRect _viewport;
    
    VuforiaEAGLView* _eaglView;
}

@synthesize viewport = _viewport;

- (instancetype)init {
    [NSException raise:NSGenericException
                format:@"Disabled. Use +[[%@ alloc] %@] instead",
     NSStringFromClass([self class]),
     NSStringFromSelector(@selector(initWithLicenseKey:dataSetFile:))];
    return nil;
}

- (instancetype)initWithLicenseKey:(NSString *)licenseKey dataSetFile:(NSString *)path {
    if(self = [super init]) {
        _licenseKey = licenseKey;
        _dataSetFile = path;
        instance = self;
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveDidEnterBackgroundNotification:)
                                                     name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (VuforiaEAGLView*)eaglView {
    if(!_eaglView) {
        CGSize size = [self preferredARFrameSize];
        _eaglView = [[VuforiaEAGLView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height) manager:self];
    }
    return _eaglView;
}

- (CGSize)preferredARFrameSize
{
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    CGRect viewFrame = screenBounds;
    
    // If this device has a retina display, scale the view bounds
    // for the AR (OpenGL) view
    if ([self isRetinaDisplay]) {
        viewFrame.size.width *= [UIScreen mainScreen].nativeScale;
        viewFrame.size.height *= [UIScreen mainScreen].nativeScale;
    }
    return viewFrame.size;
}

- (BOOL)extendedTrackingEnabled {
    return _extendedTrackingEnabled;
}

- (BOOL)setExtendedTrackingEnabled:(BOOL)enabled {
    BOOL result = [self setExtendedTrackingForDataSet:_dataSet start:enabled];
    if (result) {
        [_eaglView setOffTargetTrackingMode:enabled];
    }
    _extendedTrackingEnabled = enabled && result;
    return result;
}

- (BOOL)continuousAutofocusEnabled {
    return _continuousAutofocusEnabled;
}

- (BOOL)setContinuousAutofocusEnabled:(BOOL)enabled {
    int focusMode = enabled ? Vuforia::CameraDevice::FOCUS_MODE_CONTINUOUSAUTO : Vuforia::CameraDevice::FOCUS_MODE_NORMAL;
    BOOL result = Vuforia::CameraDevice::getInstance().setFocusMode(focusMode);
    _continuousAutofocusEnabled = enabled && result;
    return result;
}

- (BOOL)flashEnabled {
    return _flashEnabled;
}

- (BOOL)setFlashEnabled:(BOOL)enabled {
    BOOL result = Vuforia::CameraDevice::getInstance().setFlashTorchMode(enabled);
    _flashEnabled = enabled && result;
    return result;
}

- (BOOL)frontCameraEnabled {
    return _frontCameraEnabled;
}

- (BOOL)setFrontCameraEnabled:(BOOL)enabled {
    NSError* error = nil;
    if ([self stopCamera:&error]) {
        Vuforia::CameraDevice::CAMERA_DIRECTION camera = enabled ? Vuforia::CameraDevice::CAMERA_DIRECTION_FRONT : Vuforia::CameraDevice::CAMERA_DIRECTION_BACK;
        BOOL result = [self startWithCamera:camera error:&error];
        _frontCameraEnabled = result;
        if (_frontCameraEnabled) {
            // Switch Flash toggle OFF, in case it was previously ON,
            // as the front camera does not support flash
            _flashEnabled = NO;
        }
        return result;
    } else {
        return NO;
    }
}


#pragma mark - build a NSError
- (NSError*) buildErrorWithCode:(int) code {
    return [NSError errorWithDomain:VUFORIA_MANAGER_ERROR_DOMAIN code:code userInfo:nil];
}

- (NSError*) buildErrorWithCode:(NSString *) description code:(NSInteger)code {
    NSDictionary *userInfo = @{
                               NSLocalizedDescriptionKey: description
                               };
    return [NSError errorWithDomain:VUFORIA_MANAGER_ERROR_DOMAIN
                               code:code
                           userInfo:userInfo];
}

- (NSError*) buildErrorWithCode:(int) code error:(NSError **) error{
    if (error != NULL) {
        *error = [self buildErrorWithCode:code];
        return *error;
    }
    return nil;
}

// Determine whether the device has a retina display
- (BOOL)isRetinaDisplay
{
    // If UIScreen mainScreen responds to selector
    // displayLinkWithTarget:selector: and the scale property is larger than 1.0, then this
    // is a retina display
    return ([[UIScreen mainScreen] respondsToSelector:@selector(displayLinkWithTarget:selector:)] && 1.0 < [UIScreen mainScreen].scale);
}

#pragma mark - Prepare
- (void) prepareWithOrientation:(UIInterfaceOrientation)orientation {
    _isCameraActive = NO;
    _isCameraStarted = NO;
    _isRetinaDisplay = [self isRetinaDisplay];
    _arViewOrientation = orientation;
    
    // Initialising Vuforia is a potentially lengthy operation, so perform it on a
    // background thread
    [self performSelectorInBackground:@selector(prepareInBackground) withObject:nil];
}

// Setup Vuforia
// (Performed on a background thread)
- (void)prepareInBackground
{
    // Background thread must have its own autorelease pool
    @autoreleasepool {
        Vuforia::setInitParameters(mVuforiaInitFlags, [_licenseKey cStringUsingEncoding:NSUTF8StringEncoding]);
        
        // Vuforia::init() will return positive numbers up to 100 as it progresses
        // towards success.  Negative numbers indicate error conditions
        NSInteger initSuccess = 0;
        do {
            initSuccess = Vuforia::init();
        } while (0 <= initSuccess && 100 > initSuccess);
        
        if (100 == initSuccess) {
            // We can now continue the initialization of Vuforia
            // (on the main thread)
            [self performSelectorOnMainThread:@selector(prepareAR) withObject:nil waitUntilDone:NO];
        }
        else {
            NSError* error = nil;
            switch(initSuccess) {
                case Vuforia::INIT_LICENSE_ERROR_NO_NETWORK_TRANSIENT:
                    error = [self buildErrorWithCode:NSLocalizedString(@"VUFORIA_ERROR_NO_NETWORK_TRANSIENT", nil) code:initSuccess];
                    break;
                    
                case Vuforia::INIT_LICENSE_ERROR_NO_NETWORK_PERMANENT:
                    error = [self buildErrorWithCode:NSLocalizedString(@"VUFORIA_ERROR_NO_NETWORK_PERMANENT", nil) code:initSuccess];
                    break;
                    
                case Vuforia::INIT_LICENSE_ERROR_INVALID_KEY:
                    error = [self buildErrorWithCode:NSLocalizedString(@"VUFORIA_ERROR_INVALID_KEY", nil) code:initSuccess];
                    break;
                    
                case Vuforia::INIT_LICENSE_ERROR_CANCELED_KEY:
                    error = [self buildErrorWithCode:NSLocalizedString(@"VUFORIA_ERROR_CANCELED_KEY", nil) code:initSuccess];
                    break;
                    
                case Vuforia::INIT_LICENSE_ERROR_MISSING_KEY:
                    error = [self buildErrorWithCode:NSLocalizedString(@"VUFORIA_ERROR_MISSING_KEY", nil) code:initSuccess];
                    break;
                    
                case Vuforia::INIT_LICENSE_ERROR_PRODUCT_TYPE_MISMATCH:
                    error = [self buildErrorWithCode:NSLocalizedString(@"VUFORIA_ERROR_PRODUCT_TYPE_MISMATCH", nil) code:initSuccess];
                    break;
                    
                default:
                    error = [self buildErrorWithCode:NSLocalizedString(@"VUFORIA_ERROR_UNKNOWN", nil) code:initSuccess];
                    break;
                    
            }
            // Vuforia initialization error
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate vuforiaManager:self didFailToPreparingWithError:error];
            });
        }
    }
}

- (void)prepareAR  {
    // we register for the Vuforia callback
    Vuforia::registerCallback(&vuforiaUpdate);
    
    // Tell Vuforia we've created a drawing surface
    Vuforia::onSurfaceCreated();
    
    CGSize viewBoundsSize = self.preferredARFrameSize;
    int smallerSize = MIN(viewBoundsSize.width, viewBoundsSize.height);
    int largerSize = MAX(viewBoundsSize.width, viewBoundsSize.height);
    
    // Frames from the camera are always landscape, no matter what the
    // orientation of the device.  Tell Vuforia to rotate the video background (and
    // the projection matrix it provides to us for rendering our augmentation)
    // by the proper angle in order to match the EAGLView orientation
    if (_arViewOrientation == UIInterfaceOrientationPortrait)
    {
        Vuforia::onSurfaceChanged(smallerSize, largerSize);
        Vuforia::setRotation(Vuforia::ROTATE_IOS_90);
        
        _isActivityInPortraitMode = YES;
    }
    else if (_arViewOrientation == UIInterfaceOrientationPortraitUpsideDown)
    {
        Vuforia::onSurfaceChanged(smallerSize, largerSize);
        Vuforia::setRotation(Vuforia::ROTATE_IOS_270);
        
        _isActivityInPortraitMode = YES;
    }
    else if (_arViewOrientation == UIInterfaceOrientationLandscapeLeft)
    {
        Vuforia::onSurfaceChanged(largerSize, smallerSize);
        Vuforia::setRotation(Vuforia::ROTATE_IOS_180);
        
        _isActivityInPortraitMode = NO;
    }
    else if (_arViewOrientation == UIInterfaceOrientationLandscapeRight)
    {
        Vuforia::onSurfaceChanged(largerSize, smallerSize);
        Vuforia::setRotation(Vuforia::ROTATE_IOS_0);
        
        _isActivityInPortraitMode = NO;
    }
    
    [self initTracker];
}

- (void)initTracker {
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::Tracker* trackerBase = trackerManager.initTracker(Vuforia::ObjectTracker::getClassType());
    if (trackerBase == NULL)
    {
        [self.delegate vuforiaManager: self didFailToPreparingWithError:[self buildErrorWithCode:VuforiaError_InitTrackers]];
        return;
    }
    [self loadTrackerData];
}


- (void)loadTrackerData {
    // Loading tracker data is a potentially lengthy operation, so perform it on
    // a background thread
    [self performSelectorInBackground:@selector(loadTrackerDataInBackground) withObject:nil];
}

// *** Performed on a background thread ***
- (void)loadTrackerDataInBackground
{
    // Background thread must have its own autorelease pool
    @autoreleasepool {
        Vuforia::DataSet* dataSet = [self loadObjectTrackerDataSet:_dataSetFile];
        if(dataSet == NULL) {
            [self.delegate vuforiaManager:self didFailToPreparingWithError:[self buildErrorWithCode:VuforiaError_LoadingTrackersData]];
            return;
        }
        
        if(![self activateDataSet:dataSet]) {
            [self.delegate vuforiaManager:self didFailToPreparingWithError:[self buildErrorWithCode:VuforiaError_LoadingTrackersData]];
            return;
        }
    }
    
    [self.delegate vuforiaManagerDidFinishPreparing:self];
}

// Load the image tracker data set
- (Vuforia::DataSet *)loadObjectTrackerDataSet:(NSString*)dataFile
{
    NSLog(@"loadObjectTrackerDataSet (%@)", dataFile);
    Vuforia::DataSet* dataSet = NULL;
    
    // Get the Vuforia tracker manager image tracker
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(trackerManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    
    if (NULL == objectTracker) {
        NSLog(@"ERROR: failed to get the ObjectTracker from the tracker manager");
        return NULL;
    } else {
        dataSet = objectTracker->createDataSet();
        
        if (NULL != dataSet) {
            NSLog(@"INFO: successfully loaded data set");
            
            // Load the data set from the app's resources location
            if (!dataSet->load([dataFile cStringUsingEncoding:NSASCIIStringEncoding], Vuforia::STORAGE_APPRESOURCE)) {
                NSLog(@"ERROR: failed to load data set");
                objectTracker->destroyDataSet(dataSet);
                dataSet = NULL;
            }
        }
        else {
            NSLog(@"ERROR: failed to create data set");
        }
    }
    
    return dataSet;
}

- (BOOL)activateDataSet:(Vuforia::DataSet *)theDataSet
{
    // if we've previously recorded an activation, deactivate it
    if (_dataSet != nil)
    {
        [self deactivateDataSet:_dataSet];
    }
    BOOL success = NO;
    
    // Get the image tracker:
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(trackerManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    
    if (objectTracker == NULL) {
        NSLog(@"Failed to load tracking data set because the ObjectTracker has not been initialized.");
    }
    else
    {
        // Activate the data set:
        if (!objectTracker->activateDataSet(theDataSet))
        {
            NSLog(@"Failed to activate data set.");
        }
        else
        {
            NSLog(@"Successfully activated data set.");
            _dataSet = theDataSet;
            success = YES;
        }
    }
    
    // we set the off target tracking mode to the current state
    if (success) {
        [self setExtendedTrackingForDataSet:_dataSet start:_extendedTrackingEnabled];
    }
    
    return success;
}

- (BOOL)deactivateDataSet:(Vuforia::DataSet *)theDataSet
{
    if ((_dataSet == nil) || (theDataSet != _dataSet))
    {
        NSLog(@"Invalid request to deactivate data set.");
        return NO;
    }
    
    BOOL success = NO;
    
    // we deactivate the enhanced tracking
    [self setExtendedTrackingForDataSet:theDataSet start:NO];
    
    // Get the image tracker:
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(trackerManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    
    if (objectTracker == NULL)
    {
        NSLog(@"Failed to unload tracking data set because the ObjectTracker has not been initialized.");
    }
    else
    {
        // Activate the data set:
        if (!objectTracker->deactivateDataSet(theDataSet))
        {
            NSLog(@"Failed to deactivate data set.");
        }
        else
        {
            success = YES;
        }
    }
    
    _dataSet = nil;
    
    return success;
}

- (BOOL)setExtendedTrackingForDataSet:(Vuforia::DataSet *)theDataSet start:(BOOL) start {
    BOOL result = YES;
    for (int tIdx = 0; tIdx < theDataSet->getNumTrackables(); tIdx++) {
        Vuforia::Trackable* trackable = theDataSet->getTrackable(tIdx);
        if (start) {
            if (!trackable->startExtendedTracking())
            {
                NSLog(@"Failed to start extended tracking on: %s", trackable->getName());
                result = false;
            }
        } else {
            if (!trackable->stopExtendedTracking())
            {
                NSLog(@"Failed to stop extended tracking on: %s", trackable->getName());
                result = false;
            }
        }
    }
    return result;
}


// Configure Vuforia with the video background size
- (void)configureVideoBackgroundWithViewWidth:(float)viewWidth andHeight:(float)viewHeight
{
    // Get the default video mode
    Vuforia::CameraDevice& cameraDevice = Vuforia::CameraDevice::getInstance();
    Vuforia::VideoMode videoMode = cameraDevice.getVideoMode(Vuforia::CameraDevice::MODE_DEFAULT);
    
    // Configure the video background
    Vuforia::VideoBackgroundConfig config;
    config.mEnabled = true;
    config.mPosition.data[0] = 0.0f;
    config.mPosition.data[1] = 0.0f;
    
    // Determine the orientation of the view.  Note, this simple test assumes
    // that a view is portrait if its height is greater than its width.  This is
    // not always true: it is perfectly reasonable for a view with portrait
    // orientation to be wider than it is high.  The test is suitable for the
    // dimensions used in this sample
    if (_isActivityInPortraitMode) {
        // --- View is portrait ---
        
        // Compare aspect ratios of video and screen.  If they are different we
        // use the full screen size while maintaining the video's aspect ratio,
        // which naturally entails some cropping of the video
        float aspectRatioVideo = (float)videoMode.mWidth / (float)videoMode.mHeight;
        float aspectRatioView = viewHeight / viewWidth;
        
        if (aspectRatioVideo < aspectRatioView) {
            // Video (when rotated) is wider than the view: crop left and right
            // (top and bottom of video)
            
            // --============--
            // - =          = _
            // - =          = _
            // - =          = _
            // - =          = _
            // - =          = _
            // - =          = _
            // - =          = _
            // - =          = _
            // --============--
            
            config.mSize.data[0] = (int)videoMode.mHeight * (viewHeight / (float)videoMode.mWidth);
            config.mSize.data[1] = (int)viewHeight;
        }
        else {
            // Video (when rotated) is narrower than the view: crop top and
            // bottom (left and right of video).  Also used when aspect ratios
            // match (no cropping)
            
            // ------------
            // -          -
            // -          -
            // ============
            // =          =
            // =          =
            // =          =
            // =          =
            // =          =
            // =          =
            // =          =
            // =          =
            // ============
            // -          -
            // -          -
            // ------------
            
            config.mSize.data[0] = (int)viewWidth;
            config.mSize.data[1] = (int)videoMode.mWidth * (viewWidth / (float)videoMode.mHeight);
        }
        
    }
    else {
        // --- View is landscape ---
        if (viewWidth < viewHeight) {
            // Swap width/height: this is neded on iOS7 and below
            // as the view width is always reported as if in portrait.
            // On IOS 8, the swap is not needed, because the size is
            // orientation-dependent; so, this swap code in practice
            // will only be executed on iOS 7 and below.
            float temp = viewWidth;
            viewWidth = viewHeight;
            viewHeight = temp;
        }
        
        // Compare aspect ratios of video and screen.  If they are different we
        // use the full screen size while maintaining the video's aspect ratio,
        // which naturally entails some cropping of the video
        float aspectRatioVideo = (float)videoMode.mWidth / (float)videoMode.mHeight;
        float aspectRatioView = viewWidth / viewHeight;
        
        if (aspectRatioVideo < aspectRatioView) {
            // Video is taller than the view: crop top and bottom
            
            // --------------------
            // ====================
            // =                  =
            // =                  =
            // =                  =
            // =                  =
            // ====================
            // --------------------
            
            config.mSize.data[0] = (int)viewWidth;
            config.mSize.data[1] = (int)videoMode.mHeight * (viewWidth / (float)videoMode.mWidth);
        }
        else {
            // Video is wider than the view: crop left and right.  Also used
            // when aspect ratios match (no cropping)
            
            // ---====================---
            // -  =                  =  -
            // -  =                  =  -
            // -  =                  =  -
            // -  =                  =  -
            // ---====================---
            
            config.mSize.data[0] = (int)videoMode.mWidth * (viewHeight / (float)videoMode.mHeight);
            config.mSize.data[1] = (int)viewHeight;
        }
        
    }
    
    // Calculate the viewport for the app to use when rendering
    _viewport.origin.x = ((viewWidth - config.mSize.data[0]) / 2) + config.mPosition.data[0];
    _viewport.origin.y = (((int)(viewHeight - config.mSize.data[1])) / (int) 2) + config.mPosition.data[1];
    _viewport.size.width = config.mSize.data[0];
    _viewport.size.height = config.mSize.data[1];
    
#ifdef DEBUG_SAMPLE_APP
    NSLog(@"VideoBackgroundConfig: size: %d,%d", config.mSize.data[0], config.mSize.data[1]);
    NSLog(@"VideoMode:w=%d h=%d", videoMode.mWidth, videoMode.mHeight);
    NSLog(@"width=%7.3f height=%7.3f", viewWidth, viewHeight);
    NSLog(@"ViewPort: X,Y: %0.1f,%0.1f Size X,Y:%0.1f,%0.1f", _viewport.origin.x, _viewport.origin.y, _viewport.size.width, _viewport.size.height);
#endif
    
    // Set the config
    Vuforia::Renderer::getInstance().setVideoBackgroundConfig(config);
}

#pragma mark - Start
- (BOOL)start:(NSError **)error {
    Vuforia::CameraDevice::CAMERA_DIRECTION camera = _frontCameraEnabled ? Vuforia::CameraDevice::CAMERA_DIRECTION_FRONT : Vuforia::CameraDevice::CAMERA_DIRECTION_BACK;
    
    return [self startWithCamera:camera error:error];
}

- (BOOL)startWithCamera:(Vuforia::CameraDevice::CAMERA_DIRECTION)camera error:(NSError**)error {
    CGSize ARViewBoundsSize = self.preferredARFrameSize;
    
    // Start the camera.  This causes Vuforia to locate our EAGLView in the view
    // hierarchy, start a render thread, and then call renderFrameVuforia on the
    // view periodically
    if (! [self startCamera:camera viewWidth:ARViewBoundsSize.width andHeight:ARViewBoundsSize.height error:error]) {
        return NO;
    }
    _isCameraActive = YES;
    _isCameraStarted = YES;
    
    return YES;
}

// Start Vuforia camera with the specified view size
- (BOOL)startCamera:(Vuforia::CameraDevice::CAMERA_DIRECTION)camera viewWidth:(float)viewWidth andHeight:(float)viewHeight error:(NSError **)error
{
    // initialize the camera
    if (! Vuforia::CameraDevice::getInstance().init(camera)) {
        [self buildErrorWithCode:VuforiaError_InitializingCamera error:error];
        return NO;
    }
    
    // select the default video mode
    if(! Vuforia::CameraDevice::getInstance().selectVideoMode(Vuforia::CameraDevice::MODE_DEFAULT)) {
        [self buildErrorWithCode:VuforiaError_InitializingCamera error:error];
        return NO;
    }
    
    // configure Vuforia video background
    [self configureVideoBackgroundWithViewWidth:viewWidth andHeight:viewHeight];
    
    // start the camera
    if (!Vuforia::CameraDevice::getInstance().start()) {
        [self buildErrorWithCode:VuforiaError_StartingCamera error:error];
        return NO;
    }
    
    // we keep track of the current camera to restart this
    // camera when the application comes back to the foreground
    mCamera = camera;
    
    // ask the application to start the tracker(s)
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::Tracker* tracker = trackerManager.getTracker(Vuforia::ObjectTracker::getClassType());
    if(tracker == 0) {
        [self buildErrorWithCode:VuforiaError_StartingTrackers error:error];
        return NO;
    }
    tracker->start();
    
    // Cache the projection matrix
    const Vuforia::CameraCalibration& cameraCalibration = Vuforia::CameraDevice::getInstance().getCameraCalibration();
    _projectionMatrix = Vuforia::Tool::getProjectionGL(cameraCalibration, 2.0f, 5000.0f);
    
    [_eaglView setProjectionMatrix:_projectionMatrix];
    
    return YES;
}

#pragma mark - Stop
// Stop Vuforia camera
- (BOOL)stop:(NSError **)error {
    // Stop the camera
    if (_isCameraActive) {
        // Stop and deinit the camera
        Vuforia::CameraDevice::getInstance().stop();
        Vuforia::CameraDevice::getInstance().deinit();
        _isCameraActive = NO;
    }
    _isCameraStarted = NO;
    
    // Stop the tracker
    if(! [self stopTrackers]) {
        [self buildErrorWithCode:VuforiaError_StoppingTrackers error:error];
        return NO;
    }
    
    // Unload TrackersData
    [self deactivateDataSet: _dataSet];
    _dataSet = nil;
    
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    
    // Get the image tracker:
    Vuforia::ObjectTracker* objectTracker = static_cast<Vuforia::ObjectTracker*>(trackerManager.getTracker(Vuforia::ObjectTracker::getClassType()));
    
    // Destroy the data sets:
    if (!objectTracker->destroyDataSet(_dataSet))
    {
        NSLog(@"Failed to destroy data set");
        [self buildErrorWithCode:VuforiaError_UnloadingTrackersData error:error];
        return NO;
    }
    
    NSLog(@"datasets destroyed");
    
    // Deinit Trackers
    trackerManager.deinitTracker(Vuforia::ObjectTracker::getClassType());
    
    // Pause and deinitialise Vuforia
    Vuforia::onPause();
    Vuforia::deinit();
    
    [_eaglView finishOpenGLESCommands];
    
    return YES;
}

// stop the tracker
- (BOOL) stopTrackers {
    // Stop the tracker
    Vuforia::TrackerManager& trackerManager = Vuforia::TrackerManager::getInstance();
    Vuforia::Tracker* tracker = trackerManager.getTracker(Vuforia::ObjectTracker::getClassType());
    
    if (NULL != tracker) {
        tracker->stop();
        NSLog(@"INFO: successfully stopped tracker");
        return YES;
    }
    else {
        NSLog(@"ERROR: failed to get the tracker from the tracker manager");
        return NO;
    }
}

// stop the camera
- (BOOL) stopCamera:(NSError **)error {
    if (_isCameraActive) {
        // Stop and deinit the camera
        Vuforia::CameraDevice::getInstance().stop();
        Vuforia::CameraDevice::getInstance().deinit();
        _isCameraActive = NO;
    } else {
        [self buildErrorWithCode:VuforiaError_CameraNotStarted error:error];
        return NO;
    }
    _isCameraStarted = NO;
    
    // Stop the trackers
    if(! [self stopTrackers]) {
        [self buildErrorWithCode:VuforiaError_StoppingTrackers error:error];
        return NO;
    }
    
    return YES;
}

#pragma mark - Resume
- (BOOL)resume:(NSError **)error {
    Vuforia::onResume();
    
    // if the camera was previously started, but not currently active, then
    // we restart it
    if ((_isCameraStarted) && (! _isCameraActive)) {
        
        // initialize the camera
        if (! Vuforia::CameraDevice::getInstance().init(mCamera)) {
            [self buildErrorWithCode:VuforiaError_InitializingCamera error:error];
            return NO;
        }
        
        // start the camera
        if (!Vuforia::CameraDevice::getInstance().start()) {
            [self buildErrorWithCode:VuforiaError_StartingCamera error:error];
            return NO;
        }
        
        _isCameraActive = YES;
    }
    return YES;
}


#pragma mark - Pause
- (BOOL)pause:(NSError **)error {
    if (_isCameraActive) {
        // Stop and deinit the camera
        if(! Vuforia::CameraDevice::getInstance().stop()) {
            [self buildErrorWithCode:VuforiaError_StoppingCamera error:error];
            return NO;
        }
        if(! Vuforia::CameraDevice::getInstance().deinit()) {
            [self buildErrorWithCode:VuforiaError_DeinitCamara error:error];
            return NO;
        }
        _isCameraActive = NO;
    }
    Vuforia::onPause();
    return YES;
}

#pragma mark - 
- (void)didReceiveDidEnterBackgroundNotification:(NSNotification*)notification {
    [_eaglView freeOpenGLESResources];
    [_eaglView finishOpenGLESCommands];
}

#pragma mark - Vuforia Callback
- (void) Vuforia_onUpdate:(Vuforia::State *) state {
    if ((self.delegate != nil) && [self.delegate respondsToSelector:@selector(vuforiaManager:didUpdateWithState:)]) {
        [self.delegate vuforiaManager:self didUpdateWithState:[[VuforiaState alloc] initWithState:state]];
    }
}

////////////////////////////////////////////////////////////////////////////////
// Callback function called by the tracker when each tracking cycle has finished
void VuforiaApplication_UpdateCallback::Vuforia_onUpdate(Vuforia::State& state)
{
    if (instance != nil) {
        [instance Vuforia_onUpdate:&state];
    }
}


@end
