//
//  ViewController.swift
//  VuforiaSample
//
//  Created by Yoshihiro Kato on 2016/07/02.
//  Copyright © 2016年 Yoshihiro Kato. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    let vuforiaLicenseKey = "Your License Key"
    let vuforiaDataSetFile = "Target XML File"
    
    var vuforiaManager: VuforiaManager? = nil
    
    let boxMaterial = SCNMaterial()
    fileprivate var lastSceneName: String? = nil
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        prepare()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        do {
            try vuforiaManager?.stop()
        }catch let error {
            print("\(error)")
        }
    }
}

private extension ViewController {
    func prepare() {
        vuforiaManager = VuforiaManager(licenseKey: vuforiaLicenseKey, dataSetFile: vuforiaDataSetFile)
        if let manager = vuforiaManager {
            manager.delegate = self
            manager.eaglView.sceneSource = self
            manager.eaglView.delegate = self
            manager.eaglView.setupRenderer()
            self.view = manager.eaglView
        }
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(didRecieveWillResignActiveNotification),
                                       name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
        
        notificationCenter.addObserver(self, selector: #selector(didRecieveDidBecomeActiveNotification),
                                       name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)
        
        vuforiaManager?.prepare(with: .portrait)
    }
    
    func pause() {
        do {
            try vuforiaManager?.pause()
        }catch let error {
            print("\(error)")
        }
    }
    
    func resume() {
        do {
            try vuforiaManager?.resume()
        }catch let error {
            print("\(error)")
        }
    }
}

extension ViewController {
    func didRecieveWillResignActiveNotification(_ notification: Notification) {
        pause()
    }
    
    func didRecieveDidBecomeActiveNotification(_ notification: Notification) {
        resume()
    }
}

extension ViewController: VuforiaManagerDelegate {
    func vuforiaManagerDidFinishPreparing(_ manager: VuforiaManager!) {
        print("did finish preparing\n")
        
        do {
            try vuforiaManager?.start()
            vuforiaManager?.setContinuousAutofocusEnabled(true)
        }catch let error {
            print("\(error)")
        }
    }
    
    func vuforiaManager(_ manager: VuforiaManager!, didFailToPreparingWithError error: Error!) {
        print("did faid to preparing \(error)\n")
    }
    
    func vuforiaManager(_ manager: VuforiaManager!, didUpdateWith state: VuforiaState!) {
        for index in 0 ..< state.numberOfTrackableResults {
            let result = state.trackableResult(at: index)
            let trackerableName = result?.trackable.name
            //print("\(trackerableName)")
            if trackerableName == "stones" {
                boxMaterial.diffuse.contents = UIColor.red
                
                if lastSceneName != "stones" {
                    manager.eaglView.setNeedsChangeSceneWithUserInfo(["scene" : "stones"])
                    lastSceneName = "stones"
                }
            }else {
                boxMaterial.diffuse.contents = UIColor.blue
                
                if lastSceneName != "chips" {
                    manager.eaglView.setNeedsChangeSceneWithUserInfo(["scene" : "chips"])
                    lastSceneName = "chips"
                }
            }
            
        }
    }
}

extension ViewController: VuforiaEAGLViewSceneSource, VuforiaEAGLViewDelegate {
    
    func scene(for view: VuforiaEAGLView!, userInfo: [String : Any]?) -> SCNScene! {
        guard let userInfo = userInfo else {
            print("default scene")
            return createStonesScene(with: view)
        }
        
        if let sceneName = userInfo["scene"] as? String , sceneName == "stones" {
            print("stones scene")
            return createStonesScene(with: view)
        }else {
            print("chips scene")
            return createChipsScene(with: view)
        }
        
    }
    
    fileprivate func createStonesScene(with view: VuforiaEAGLView) -> SCNScene {
        let scene = SCNScene()
        
        boxMaterial.diffuse.contents = UIColor.lightGray
        
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.color = UIColor.lightGray
        lightNode.position = SCNVector3(x:0, y:10, z:10)
        scene.rootNode.addChildNode(lightNode)
        
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light?.type = .ambient
        ambientLightNode.light?.color = UIColor.darkGray
        scene.rootNode.addChildNode(ambientLightNode)
        
        let planeNode = SCNNode()
        planeNode.name = "plane"
        planeNode.geometry = SCNPlane(width: 247.0/view.objectScale, height: 173.0/view.objectScale)
        planeNode.position = SCNVector3Make(0, 0, -1)
        let planeMaterial = SCNMaterial()
        planeMaterial.diffuse.contents = UIColor.green
        planeMaterial.transparency = 0.6
        planeNode.geometry?.firstMaterial = planeMaterial
        scene.rootNode.addChildNode(planeNode)
        
        let boxNode = SCNNode()
        boxNode.name = "box"
        boxNode.geometry = SCNBox(width:1, height:1, length:1, chamferRadius:0.0)
        boxNode.geometry?.firstMaterial = boxMaterial
        scene.rootNode.addChildNode(boxNode)
        
        return scene
    }
    
    fileprivate func createChipsScene(with view: VuforiaEAGLView) -> SCNScene {
        let scene = SCNScene()
        
        boxMaterial.diffuse.contents = UIColor.lightGray
        
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.color = UIColor.lightGray
        lightNode.position = SCNVector3(x:0, y:10, z:10)
        scene.rootNode.addChildNode(lightNode)
        
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light?.type = .ambient
        ambientLightNode.light?.color = UIColor.darkGray
        scene.rootNode.addChildNode(ambientLightNode)
        
        let planeNode = SCNNode()
        planeNode.name = "plane"
        planeNode.geometry = SCNPlane(width: 247.0/view.objectScale, height: 173.0/view.objectScale)
        planeNode.position = SCNVector3Make(0, 0, -1)
        let planeMaterial = SCNMaterial()
        planeMaterial.diffuse.contents = UIColor.red
        planeMaterial.transparency = 0.6
        planeNode.geometry?.firstMaterial = planeMaterial
        scene.rootNode.addChildNode(planeNode)
        
        let boxNode = SCNNode()
        boxNode.name = "box"
        boxNode.geometry = SCNBox(width:1, height:1, length:1, chamferRadius:0.0)
        boxNode.geometry?.firstMaterial = boxMaterial
        scene.rootNode.addChildNode(boxNode)
        
        return scene
    }
    
    func vuforiaEAGLView(_ view: VuforiaEAGLView!, didTouchDownNode node: SCNNode!) {
        print("touch down \(node.name)\n")
        boxMaterial.transparency = 0.6
    }
    
    func vuforiaEAGLView(_ view: VuforiaEAGLView!, didTouchUp node: SCNNode!) {
        print("touch up \(node.name)\n")
        boxMaterial.transparency = 1.0
    }
    
    func vuforiaEAGLView(_ view: VuforiaEAGLView!, didTouchCancel node: SCNNode!) {
        print("touch cancel \(node.name)\n")
        boxMaterial.transparency = 1.0
    }
}

