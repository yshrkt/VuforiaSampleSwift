//
//  VuforiaShaderUtils.h
//  VuforiaSampleSwift
//
//  Created by Yoshihiro Kato on 2016/07/03.
//  Copyright © 2016年 Yoshihiro Kato. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface VuforiaShaderUtils : NSObject

+ (int)createProgramWithVertexShaderFileName:(NSString*) vertexShaderFileName
                      fragmentShaderFileName:(NSString*) fragmentShaderFileName;

+ (int)createProgramWithVertexShaderFileName:(NSString*) vertexShaderFileName
                        withVertexShaderDefs:(NSString *) vertexShaderDefs
                      fragmentShaderFileName:(NSString *) fragmentShaderFileName
                      withFragmentShaderDefs:(NSString *) fragmentShaderDefs;


@end
