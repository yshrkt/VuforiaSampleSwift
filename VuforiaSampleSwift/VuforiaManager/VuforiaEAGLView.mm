//
//  VuforiaEAGLView.m
//  VuforiaSampleSwift
//
//  Created by Yoshihiro Kato on 2016/07/02.
//  Copyright © 2016年 Yoshihiro Kato. All rights reserved.
//

#import "VuforiaEAGLView.h"

#import <SceneKit/SceneKit.h>
#import <SpriteKit/SpriteKit.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <sys/time.h>

#import <Vuforia/Vuforia.h>
#import <Vuforia/State.h>
#import <Vuforia/Tool.h>
#import <Vuforia/Renderer.h>
#import <Vuforia/TrackableResult.h>
#import <Vuforia/VideoBackgroundConfig.h>

#import "VuforiaShaderUtils.h"


namespace VuforiaEAGLViewUtils
{
    // Print a 4x4 matrix
    void printMatrix(const float* matrix);
    
    // Print GL error information
    void checkGlError(const char* operation);
    
    // Set the rotation components of a 4x4 matrix
    void setRotationMatrix(float angle, float x, float y, float z,
                           float *nMatrix);
    
    // Set the translation components of a 4x4 matrix
    void translatePoseMatrix(float x, float y, float z,
                             float* nMatrix = NULL);
    
    // Apply a rotation
    void rotatePoseMatrix(float angle, float x, float y, float z,
                          float* nMatrix = NULL);
    
    // Apply a scaling transformation
    void scalePoseMatrix(float x, float y, float z,
                         float* nMatrix = NULL);
    
    // Multiply the two matrices A and B and write the result to C
    void multiplyMatrix(float *matrixA, float *matrixB,
                        float *matrixC);
    
    void setOrthoMatrix(float nLeft, float nRight, float nBottom, float nTop,
                        float nNear, float nFar, float *nProjMatrix);
    
    void screenCoordToCameraCoord(int screenX, int screenY, int screenDX, int screenDY,
                                  int screenWidth, int screenHeight, int cameraWidth, int cameraHeight,
                                  int * cameraX, int* cameraY, int * cameraDX, int * cameraDY);
}


//******************************************************************************
// *** OpenGL ES thread safety ***
//
// OpenGL ES on iOS is not thread safe.  We ensure thread safety by following
// this procedure:
// 1) Create the OpenGL ES context on the main thread.
// 2) Start the Vuforia camera, which causes Vuforia to locate our EAGLView and start
//    the render thread.
// 3) Vuforia calls our renderFrameVuforia method periodically on the render thread.
//    The first time this happens, the defaultFramebuffer does not exist, so it
//    is created with a call to createFramebuffer.  createFramebuffer is called
//    on the main thread in order to safely allocate the OpenGL ES storage,
//    which is shared with the drawable layer.  The render (background) thread
//    is blocked during the call to createFramebuffer, thus ensuring no
//    concurrent use of the OpenGL ES context.
//
//******************************************************************************

@interface VuforiaEAGLView (PrivateMethods)

- (void)initShaders;
- (void)createFramebuffer;
- (void)deleteFramebuffer;
- (void)setFramebuffer;
- (BOOL)presentFramebuffer;

@end


@implementation VuforiaEAGLView {
    __weak VuforiaManager* _manager;
    
    // OpenGL ES context
    EAGLContext* _context;
    
    // The OpenGL ES names for the framebuffer and renderbuffers used to render
    // to this view
    GLuint _defaultFramebuffer;
    GLuint _colorRenderbuffer;
    GLuint _depthRenderbuffer;
    
    
    BOOL _offTargetTrackingEnabled;
    
    SCNRenderer* _renderer; // Renderer
    SCNNode* _cameraNode; // Camera Node
    CFAbsoluteTime _startTime; // Start Time
    
    SCNNode* _currentTouchNode;
    
    SCNMatrix4 _projectionTransform;
}

// You must implement this method, which ensures the view's underlying layer is
// of type CAEAGLLayer
+ (Class)layerClass
{
    return [CAEAGLLayer class];
}


//------------------------------------------------------------------------------
#pragma mark - Lifecycle

- (id)initWithFrame:(CGRect)frame manager:(VuforiaManager *)manager
{
    self = [super initWithFrame:frame];
    
    if (self) {
        _manager = manager;
        // Enable retina mode if available on this device
        if (YES == [_manager isRetinaDisplay]) {
            [self setContentScaleFactor:[UIScreen mainScreen].nativeScale];
        }
        
        // Create the OpenGL ES context
        _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        
        // The EAGLContext must be set for each thread that wishes to use it.
        // Set it the first time this method is called (on the main thread)
        if (_context != [EAGLContext currentContext]) {
            [EAGLContext setCurrentContext:_context];
        }
        
        _offTargetTrackingEnabled = NO;
        _objectScale = 50.0f;
    }
    
    return self;
}


- (void)dealloc
{
    [self deleteFramebuffer];
    
    // Tear down context
    if ([EAGLContext currentContext] == _context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)setupRenderer {
    _renderer = [SCNRenderer rendererWithContext:_context options:nil];
    _renderer.autoenablesDefaultLighting = YES;
    _renderer.playing = YES;
    _renderer.showsStatistics = YES;
    
    if (_sceneSource != nil) {
        [self setNeedsChangeSceneWithUserInfo:nil];
    }
    
}

- (void)setNeedsChangeSceneWithUserInfo: (NSDictionary*)userInfo {
    SCNScene* scene = [self.sceneSource sceneForEAGLView:self userInfo:userInfo];
    if (scene == nil) {
        return;
    }
    
    SCNCamera* camera = [SCNCamera camera];
    _cameraNode = [SCNNode node];
    _cameraNode.camera = camera;
    _cameraNode.camera.projectionTransform = _projectionTransform;
    [scene.rootNode addChildNode:_cameraNode];
    
    _renderer.scene = scene;
    _renderer.pointOfView = _cameraNode;
}


- (void)finishOpenGLESCommands
{
    // Called in response to applicationWillResignActive.  The render loop has
    // been stopped, so we now make sure all OpenGL ES commands complete before
    // we (potentially) go into the background
    if (_context) {
        [EAGLContext setCurrentContext:_context];
        glFinish();
    }
}


- (void)freeOpenGLESResources
{
    // Called in response to applicationDidEnterBackground.  Free easily
    // recreated OpenGL ES resources
    [self deleteFramebuffer];
    glFinish();
}

- (void) setOffTargetTrackingMode:(BOOL) enabled {
    _offTargetTrackingEnabled = enabled;
}

// Convert Vuforia's matrix to SceneKit's matrix
- (SCNMatrix4)SCNMatrix4FromVuforiaMatrix44:(Vuforia::Matrix44F)matrix {
    GLKMatrix4 glkMatrix;
    
    for(int i=0; i<16; i++) {
        glkMatrix.m[i] = matrix.data[i];
    }
    
    return SCNMatrix4FromGLKMatrix4(glkMatrix);
    
}

// Set camera node matrix
- (void)setCameraMatrix:(Vuforia::Matrix44F)matrix {
    SCNMatrix4 extrinsic = [self SCNMatrix4FromVuforiaMatrix44:matrix];
    SCNMatrix4 inverted = SCNMatrix4Invert(extrinsic);
    _cameraNode.transform = inverted;
    
    //NSLog(@"position = %lf, %lf, %lf", _cameraNode.position.x, _cameraNode.position.y, _cameraNode.position.z); // デバッグ用
}

- (void)setProjectionMatrix:(Vuforia::Matrix44F)matrix {
    _projectionTransform = [self SCNMatrix4FromVuforiaMatrix44:matrix];
    _cameraNode.camera.projectionTransform = _projectionTransform;
}

//------------------------------------------------------------------------------
#pragma mark - UIGLViewProtocol methods

// Draw the current frame using OpenGL
//
// This method is called by Vuforia when it wishes to render the current frame to
// the screen.
//
// *** Vuforia will call this method periodically on a background thread ***
- (void)renderFrameVuforia
{
    [self setFramebuffer];
    
    // Clear colour and depth buffers
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    // Render video background and retrieve tracking state
    Vuforia::State state = Vuforia::Renderer::getInstance().begin();
    Vuforia::Renderer::getInstance().drawVideoBackground();
    
    glEnable(GL_DEPTH_TEST);
    // We must detect if background reflection is active and adjust the culling direction.
    // If the reflection is active, this means the pose matrix has been reflected as well,
    // therefore standard counter clockwise face culling will result in "inside out" models.
    if (_offTargetTrackingEnabled) {
        glDisable(GL_CULL_FACE);
    } else {
        glEnable(GL_CULL_FACE);
    }

    glCullFace(GL_BACK);
    if(Vuforia::Renderer::getInstance().getVideoBackgroundConfig().mReflection == Vuforia::VIDEO_BACKGROUND_REFLECTION_ON)
        glFrontFace(GL_CW);  //Front camera
    else
        glFrontFace(GL_CCW);   //Back camera
    
    // Set the viewport
    glViewport((GLint)_manager.viewport.origin.x, (GLint)_manager.viewport.origin.y,
               (GLsizei)_manager.viewport.size.width, (GLsizei)_manager.viewport.size.height);
    
    for (int i = 0; i < state.getNumTrackableResults(); ++i) {
        // Get the trackable
        const Vuforia::TrackableResult* result = state.getTrackableResult(i);
        //const Vuforia::Trackable& trackable = result->getTrackable();
        Vuforia::Matrix44F modelViewMatrix = Vuforia::Tool::convertPose2GLMatrix(result->getPose()); // get model view matrix
        
        VuforiaEAGLViewUtils::translatePoseMatrix(0.0f, 0.0f, _objectScale, &modelViewMatrix.data[0]);
        VuforiaEAGLViewUtils::scalePoseMatrix(_objectScale,  _objectScale,  _objectScale, &modelViewMatrix.data[0]);
        
        [self setCameraMatrix:modelViewMatrix]; // SCNCameraにセット
        [_renderer renderAtTime:CFAbsoluteTimeGetCurrent() - _startTime]; // render using SCNRenderer
        
        VuforiaEAGLViewUtils::checkGlError("EAGLView renderFrameVuforia");
    }
    
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    
    Vuforia::Renderer::getInstance().end();
    [self presentFramebuffer];
}

#pragma mark Touch Evnets

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint pos = [touches.anyObject locationInView:self];
    pos.x *= [[UIScreen mainScreen] nativeScale];
    pos.y *= [[UIScreen mainScreen] nativeScale];
    pos.y = _manager.viewport.size.height - pos.y;
    NSArray* results = [_renderer hitTest:pos options:nil];
    SCNNode* result = [[results firstObject] node];
    if(result){
        _currentTouchNode = result;
        [self.delegate vuforiaEAGLView:self didTouchDownNode:result];
    }
    
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if(!_currentTouchNode) {
        return;
    }
    
    CGPoint pos = [touches.anyObject locationInView:self];
    pos.x *= [[UIScreen mainScreen] nativeScale];
    pos.y *= [[UIScreen mainScreen] nativeScale];
    pos.y = _manager.viewport.size.height - pos.y;
    NSArray* results = [_renderer hitTest:pos options:nil];
    SCNNode* result = [[results firstObject] node];
    if(_currentTouchNode == result){
        [self.delegate vuforiaEAGLView:self didTouchUpNode:result];
    }else {
        [self.delegate vuforiaEAGLView:self didTouchCancelNode:_currentTouchNode];
    }
    _currentTouchNode = nil;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if(_currentTouchNode) {
        [self.delegate vuforiaEAGLView:self didTouchCancelNode:_currentTouchNode];
    }
    _currentTouchNode = nil;
}

//------------------------------------------------------------------------------
#pragma mark - OpenGL ES management

- (void)createFramebuffer
{
    if (_context) {
        // Create default framebuffer object
        glGenFramebuffers(1, &_defaultFramebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, _defaultFramebuffer);
        
        // Create colour renderbuffer and allocate backing store
        glGenRenderbuffers(1, &_colorRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
        
        // Allocate the renderbuffer's storage (shared with the drawable object)
        [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)self.layer];
        GLint framebufferWidth;
        GLint framebufferHeight;
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &framebufferWidth);
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &framebufferHeight);
        
        // Create the depth render buffer and allocate storage
        glGenRenderbuffers(1, &_depthRenderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, _depthRenderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, framebufferWidth, framebufferHeight);
        
        // Attach colour and depth render buffers to the frame buffer
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorRenderbuffer);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _depthRenderbuffer);
        
        // Leave the colour render buffer bound so future rendering operations will act on it
        glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
    }
}


- (void)deleteFramebuffer
{
    if (_context) {
        [EAGLContext setCurrentContext:_context];
        
        if (_defaultFramebuffer) {
            glDeleteFramebuffers(1, &_defaultFramebuffer);
            _defaultFramebuffer = 0;
        }
        
        if (_colorRenderbuffer) {
            glDeleteRenderbuffers(1, &_colorRenderbuffer);
            _colorRenderbuffer = 0;
        }
        
        if (_depthRenderbuffer) {
            glDeleteRenderbuffers(1, &_depthRenderbuffer);
            _depthRenderbuffer = 0;
        }
    }
}


- (void)setFramebuffer
{
    // The EAGLContext must be set for each thread that wishes to use it.  Set
    // it the first time this method is called (on the render thread)
    if (_context != [EAGLContext currentContext]) {
        [EAGLContext setCurrentContext:_context];
    }
    
    if (!_defaultFramebuffer) {
        // Perform on the main thread to ensure safe memory allocation for the
        // shared buffer.  Block until the operation is complete to prevent
        // simultaneous access to the OpenGL context
        [self performSelectorOnMainThread:@selector(createFramebuffer) withObject:self waitUntilDone:YES];
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, _defaultFramebuffer);
}


- (BOOL)presentFramebuffer
{
    // setFramebuffer must have been called before presentFramebuffer, therefore
    // we know the context is valid and has been set for this (render) thread
    
    // Bind the colour render buffer and present it
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
    
    return [_context presentRenderbuffer:GL_RENDERBUFFER];
}


@end

namespace VuforiaEAGLViewUtils
{
    // Print a 4x4 matrix
    void
    printMatrix(const float* mat)
    {
        for (int r = 0; r < 4; r++, mat += 4) {
            printf("%7.3f %7.3f %7.3f %7.3f", mat[0], mat[1], mat[2], mat[3]);
        }
    }
    
    
    // Print GL error information
    void
    checkGlError(const char* operation)
    {
        for (GLint error = glGetError(); error; error = glGetError()) {
            printf("after %s() glError (0x%x)\n", operation, error);
        }
    }
    
    
    // Set the rotation components of a 4x4 matrix
    void
    setRotationMatrix(float angle, float x, float y, float z,
                      float *matrix)
    {
        double radians, c, s, c1, u[3], length;
        int i, j;
        
        radians = (angle * M_PI) / 180.0;
        
        c = cos(radians);
        s = sin(radians);
        
        c1 = 1.0 - cos(radians);
        
        length = sqrt(x * x + y * y + z * z);
        
        u[0] = x / length;
        u[1] = y / length;
        u[2] = z / length;
        
        for (i = 0; i < 16; i++) {
            matrix[i] = 0.0;
        }
        
        matrix[15] = 1.0;
        
        for (i = 0; i < 3; i++) {
            matrix[i * 4 + (i + 1) % 3] = u[(i + 2) % 3] * s;
            matrix[i * 4 + (i + 2) % 3] = -u[(i + 1) % 3] * s;
        }
        
        for (i = 0; i < 3; i++) {
            for (j = 0; j < 3; j++) {
                matrix[i * 4 + j] += c1 * u[i] * u[j] + (i == j ? c : 0.0);
            }
        }
    }
    
    
    // Set the translation components of a 4x4 matrix
    void
    translatePoseMatrix(float x, float y, float z, float* matrix)
    {
        if (matrix) {
            // matrix * translate_matrix
            matrix[12] += (matrix[0] * x + matrix[4] * y + matrix[8]  * z);
            matrix[13] += (matrix[1] * x + matrix[5] * y + matrix[9]  * z);
            matrix[14] += (matrix[2] * x + matrix[6] * y + matrix[10] * z);
            matrix[15] += (matrix[3] * x + matrix[7] * y + matrix[11] * z);
        }
    }
    
    
    // Apply a rotation
    void
    rotatePoseMatrix(float angle, float x, float y, float z,
                     float* matrix)
    {
        if (matrix) {
            float rotate_matrix[16];
            setRotationMatrix(angle, x, y, z, rotate_matrix);
            
            // matrix * scale_matrix
            multiplyMatrix(matrix, rotate_matrix, matrix);
        }
    }
    
    
    // Apply a scaling transformation
    void
    scalePoseMatrix(float x, float y, float z, float* matrix)
    {
        if (matrix) {
            // matrix * scale_matrix
            matrix[0]  *= x;
            matrix[1]  *= x;
            matrix[2]  *= x;
            matrix[3]  *= x;
            
            matrix[4]  *= y;
            matrix[5]  *= y;
            matrix[6]  *= y;
            matrix[7]  *= y;
            
            matrix[8]  *= z;
            matrix[9]  *= z;
            matrix[10] *= z;
            matrix[11] *= z;
        }
    }
    
    
    // Multiply the two matrices A and B and write the result to C
    void
    multiplyMatrix(float *matrixA, float *matrixB, float *matrixC)
    {
        int i, j, k;
        float aTmp[16];
        
        for (i = 0; i < 4; i++) {
            for (j = 0; j < 4; j++) {
                aTmp[j * 4 + i] = 0.0;
                
                for (k = 0; k < 4; k++) {
                    aTmp[j * 4 + i] += matrixA[k * 4 + i] * matrixB[j * 4 + k];
                }
            }
        }
        
        for (i = 0; i < 16; i++) {
            matrixC[i] = aTmp[i];
        }
    }
    
    void
    setOrthoMatrix(float nLeft, float nRight, float nBottom, float nTop,
                   float nNear, float nFar, float *nProjMatrix)
    {
        if (!nProjMatrix)
        {
            //         arLogMessage(AR_LOG_LEVEL_ERROR, "PLShadersExample", "Orthographic projection matrix pointer is NULL");
            return;
        }
        
        int i;
        for (i = 0; i < 16; i++)
            nProjMatrix[i] = 0.0f;
        
        nProjMatrix[0] = 2.0f / (nRight - nLeft);
        nProjMatrix[5] = 2.0f / (nTop - nBottom);
        nProjMatrix[10] = 2.0f / (nNear - nFar);
        nProjMatrix[12] = -(nRight + nLeft) / (nRight - nLeft);
        nProjMatrix[13] = -(nTop + nBottom) / (nTop - nBottom);
        nProjMatrix[14] = (nFar + nNear) / (nFar - nNear);
        nProjMatrix[15] = 1.0f;
    }
    
    // Transforms a screen pixel to a pixel onto the camera image,
    // taking into account e.g. cropping of camera image to fit different aspect ratio screen.
    // for the camera dimensions, the width is always bigger than the height (always landscape orientation)
    // Top left of screen/camera is origin
    void
    screenCoordToCameraCoord(int screenX, int screenY, int screenDX, int screenDY,
                             int screenWidth, int screenHeight, int cameraWidth, int cameraHeight,
                             int * cameraX, int* cameraY, int * cameraDX, int * cameraDY)
    {
        
        printf("screenCoordToCameraCoord:%d,%d %d,%d, %d,%d, %d,%d",screenX, screenY, screenDX, screenDY,
               screenWidth, screenHeight, cameraWidth, cameraHeight );
        
        
        bool isPortraitMode = (screenWidth < screenHeight);
        float videoWidth, videoHeight;
        videoWidth = (float)cameraWidth;
        videoHeight = (float)cameraHeight;
        if (isPortraitMode)
        {
            // the width and height of the camera are always
            // based on a landscape orientation
            // videoWidth = (float)cameraHeight;
            // videoHeight = (float)cameraWidth;
            
            
            // as the camera coordinates are always in landscape
            // we convert the inputs into a landscape based coordinate system
            int tmp = screenX;
            screenX = screenY;
            screenY = screenWidth - tmp;
            
            tmp = screenDX;
            screenDX = screenDY;
            screenDY = tmp;
            
            tmp = screenWidth;
            screenWidth = screenHeight;
            screenHeight = tmp;
            
        }
        else
        {
            videoWidth = (float)cameraWidth;
            videoHeight = (float)cameraHeight;
        }
        
        float videoAspectRatio = videoHeight / videoWidth;
        float screenAspectRatio = (float) screenHeight / (float) screenWidth;
        
        float scaledUpX;
        float scaledUpY;
        float scaledUpVideoWidth;
        float scaledUpVideoHeight;
        
        if (videoAspectRatio < screenAspectRatio)
        {
            // the video height will fit in the screen height
            scaledUpVideoWidth = (float)screenHeight / videoAspectRatio;
            scaledUpVideoHeight = screenHeight;
            scaledUpX = (float)screenX + ((scaledUpVideoWidth - (float)screenWidth) / 2.0f);
            scaledUpY = (float)screenY;
        }
        else
        {
            // the video width will fit in the screen width
            scaledUpVideoHeight = (float)screenWidth * videoAspectRatio;
            scaledUpVideoWidth = screenWidth;
            scaledUpY = (float)screenY + ((scaledUpVideoHeight - (float)screenHeight)/2.0f);
            scaledUpX = (float)screenX;
        }
        
        if (cameraX)
        {
            *cameraX = (int)((scaledUpX / (float)scaledUpVideoWidth) * videoWidth);
        }
        
        if (cameraY)
        {
            *cameraY = (int)((scaledUpY / (float)scaledUpVideoHeight) * videoHeight);
        }
        
        if (cameraDX)
        {
            *cameraDX = (int)(((float)screenDX / (float)scaledUpVideoWidth) * videoWidth);
        }
        
        if (cameraDY)
        {
            *cameraDY = (int)(((float)screenDY / (float)scaledUpVideoHeight) * videoHeight);
        }
    }
    
    
}
