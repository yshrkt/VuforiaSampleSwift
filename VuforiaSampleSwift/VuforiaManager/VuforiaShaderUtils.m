//
//  VuforiaShaderUtils.m
//  VuforiaSampleSwift
//
//  Created by Yoshihiro Kato on 2016/07/03.
//  Copyright © 2016年 Yoshihiro Kato. All rights reserved.
//

#import "VuforiaShaderUtils.h"
#import <OpenGLES/ES2/glext.h>

@implementation VuforiaShaderUtils

+ (GLuint)compileShader:(NSString*)shaderFileName withDefs:(NSString *) defs withType:(GLenum)shaderType {
    NSString* shaderName = [[shaderFileName lastPathComponent] stringByDeletingPathExtension];
    NSString* shaderFileType = [shaderFileName pathExtension];
    
    NSLog(@"debug: shaderName=(%@), shaderFileTYpe=(%@)", shaderName, shaderFileType);
    
    // 1
    NSString* shaderPath = [[NSBundle mainBundle] pathForResource:shaderName ofType:shaderFileType];
    NSLog(@"debug: shaderPath=(%@)", shaderPath);
    NSError* error;
    NSString* shaderString = [NSString stringWithContentsOfFile:shaderPath encoding:NSUTF8StringEncoding error:&error];
    if (!shaderString) {
        NSLog(@"Error loading shader (%@): %@", shaderFileName, error.localizedDescription);
        return 0;
    }
    
    // 2
    GLuint shaderHandle = glCreateShader(shaderType);
    
    // 3
    const char * shaderStringUTF8 = [shaderString UTF8String];
    GLint shaderStringLength = (GLint)[shaderString length];
    
    if (defs == nil) {
        glShaderSource(shaderHandle, 1, &shaderStringUTF8, &shaderStringLength);
    } else {
        const char* finalShader[2] = {[defs UTF8String],shaderStringUTF8};
        GLint finalShaderSizes[2] = {(GLint)[defs length], shaderStringLength};
        glShaderSource(shaderHandle, 2, finalShader, finalShaderSizes);
    }
    
    // 4
    glCompileShader(shaderHandle);
    
    // 5
    GLint compileSuccess;
    glGetShaderiv(shaderHandle, GL_COMPILE_STATUS, &compileSuccess);
    if (compileSuccess == GL_FALSE) {
        GLchar messages[256];
        glGetShaderInfoLog(shaderHandle, sizeof(messages), 0, &messages[0]);
        NSString *messageString = [NSString stringWithUTF8String:messages];
        NSLog(@"Error compiling shader (%@): %@", shaderFileName, messageString);
        return 0;
    }
    
    return shaderHandle;
    
}

+ (int)createProgramWithVertexShaderFileName:(NSString*) vertexShaderFileName
                      fragmentShaderFileName:(NSString *) fragmentShaderFileName {
    return [self createProgramWithVertexShaderFileName:vertexShaderFileName
                                                          withVertexShaderDefs:nil
                                                        fragmentShaderFileName:fragmentShaderFileName
                                                        withFragmentShaderDefs:nil];
}

+ (int)createProgramWithVertexShaderFileName:(NSString*) vertexShaderFileName
                        withVertexShaderDefs:(NSString *) vertexShaderDefs
                      fragmentShaderFileName:(NSString *) fragmentShaderFileName
                      withFragmentShaderDefs:(NSString *) fragmentShaderDefs {
    GLuint vertexShader = [self compileShader:vertexShaderFileName withDefs:vertexShaderDefs withType:GL_VERTEX_SHADER];
    GLuint fragmentShader = [self compileShader:fragmentShaderFileName withDefs:fragmentShaderDefs withType:GL_FRAGMENT_SHADER];
    
    if ((vertexShader == 0) || (fragmentShader == 0)) {
        NSLog(@"Error: error compiling shaders");
        return 0;
    }
    
    GLuint programHandle = glCreateProgram();
    
    if (programHandle == 0) {
        NSLog(@"Error: can't create programe");
        return 0;
    }
    glAttachShader(programHandle, vertexShader);
    glAttachShader(programHandle, fragmentShader);
    glLinkProgram(programHandle);
    
    GLint linkSuccess;
    glGetProgramiv(programHandle, GL_LINK_STATUS, &linkSuccess);
    if (linkSuccess == GL_FALSE) {
        GLchar messages[256];
        glGetProgramInfoLog(programHandle, sizeof(messages), 0, &messages[0]);
        NSString *messageString = [NSString stringWithUTF8String:messages];
        NSLog(@"Error linkink shaders (%@) and (%@): %@", vertexShaderFileName, fragmentShaderFileName, messageString);
        return 0;
    }
    return programHandle;
}


@end
