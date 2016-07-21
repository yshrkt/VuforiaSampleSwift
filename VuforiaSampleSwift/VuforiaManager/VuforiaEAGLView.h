//
//  VuforiaEAGLView.h
//  VuforiaSampleSwift
//
//  Created by Yoshihiro Kato on 2016/07/02.
//  Copyright © 2016年 Yoshihiro Kato. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <SceneKit/SceneKit.h>
#import <Vuforia/UIGLViewProtocol.h>

#import "VuforiaManager.h"

@class VuforiaManager;
@class VuforiaEAGLView;

@protocol VuforiaEAGLViewSceneSource <NSObject>

- (SCNScene *)sceneForEAGLView:(VuforiaEAGLView *)view userInfo:(NSDictionary<NSString*, id>*)userInfo;

@end

@protocol VuforiaEAGLViewDelegate <NSObject>

- (void)vuforiaEAGLView:(VuforiaEAGLView*)view didTouchDownNode:(SCNNode *)node;
- (void)vuforiaEAGLView:(VuforiaEAGLView*)view didTouchUpNode:(SCNNode *)node;
- (void)vuforiaEAGLView:(VuforiaEAGLView*)view didTouchCancelNode:(SCNNode *)node;

@end


// EAGLView is a subclass of UIView and conforms to the informal protocol
// UIGLViewProtocol
@interface VuforiaEAGLView : UIView <UIGLViewProtocol>

@property (weak, nonatomic)id<VuforiaEAGLViewSceneSource> sceneSource;
@property (weak, nonatomic)id<VuforiaEAGLViewDelegate> delegate;
@property (nonatomic, assign)CGFloat objectScale;

- (id)initWithFrame:(CGRect)frame manager:(VuforiaManager *) manager;

- (void)setupRenderer;
- (void)setNeedsChangeSceneWithUserInfo: (NSDictionary*)userInfo;

- (void)finishOpenGLESCommands;
- (void)freeOpenGLESResources;

- (void)setOffTargetTrackingMode:(BOOL) enabled;
@end
