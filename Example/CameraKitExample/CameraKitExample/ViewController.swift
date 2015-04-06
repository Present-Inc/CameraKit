//
//  ViewController.swift
//  CameraKitExample
//
//  Created by Justin Makaila on 4/5/15.
//  Copyright (c) 2015 Present, Inc. All rights reserved.
//

import UIKit
import CameraKit
import AVFoundation

class ViewController: UIViewController {
    @IBOutlet
    private var cameraPreview: UIView!
    
    private var cameraController: CameraController!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setup()
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        
        cameraController.startCaptureSession()
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        
        cameraController.stopCaptureSession()
    }
}

extension ViewController: CameraControllerDelegate {
    func cameraController(controller: CameraController, didStartRecording recording: Bool) {
        
    }
    
    func cameraController(controller: CameraController, didStopRecording recording: Bool) {
        
    }
    
    func cameraController(controller: CameraController, didCaptureStillImage image: UIImage) {
        
    }
    
    func cameraController(controller: CameraController, didOutputSampleBuffer sampleBuffer: CMSampleBufferRef, type: CameraController.FrameType) {
        let frameType = type == .Video ? "video" : "audio"
        println("Camera controller did output \(frameType) frame")
    }
}

private extension ViewController {
    func setup() {
        cameraPreview.frame = view.bounds
        
        let configuration = CameraControllerConfiguration()
        cameraController = CameraController(configuration: configuration, view: cameraPreview)
        cameraController.delegate = self
    }
}

