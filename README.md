# VuforiaSampleSwift

Vuforia sample code with SceneKit using Swift.

## Requirement

* Xcode 8
* iOS 9.3
* Vuforia SDK for iOS v6.0.112

## Setup

* Download Vuforia SDK for iOS.  
  [Vuforia SDK](https://developer.vuforia.com/downloads/sdk)
* Put the SDK on your path as like bellow:  
  `VuforiaSampleSwift/VuforiaSampleSwift/vuforia-sdk-ios-6-0-112`
* Download Vuforiat Sample Targets.  
  [Vuforiat Sample](https://developer.vuforia.com/downloads/samples)
* Put your targets on your path as like bellow:  
  `VuforiaSampleSwift/VuforiaSampleSwift/VuforiaAssets/ImageTargets`
* If you needs to fix to links to these files and settings in project, fix it.  
  If you failed to build, check `Header Search Paths` and `Libarary Search Paths` in Build Settings.
* Set your `lincenseKey` and `dataSetFile` in ViewController.swift.


## Usage

See ViewController.swift.

``` swift

vuforiaManager = VuforiaManager(licenseKey: "your license key", dataSetFile: "your target xml file")
if let manager = vuforiaManager {
    manager.delegate = self
    manager.eaglView.sceneSource = self
    manager.eaglView.delegate = self
    manager.eaglView.setupRenderer()
    self.view = manager.eaglView
}

vuforiaManager?.prepareWithOrientation(.Portrait)

...

do {
    try vuforiaManager?.start()
}catch let error {
    print("\(error)")
}

```

## ScreenShot

![screenshot](https://github.com/yshrkt/VuforiaSampleSwift/blob/master/screenshot.jpg)

## Thanks

I am referring to the following page.

* [Making Augmented Reality app easily with Scenekit + Vuforia (in English)](http://qiita.com/akira108/items/a743138fca532ee193fe)
