//
//  ViewController.swift
//  CameraKitExample
//
//  Created by Justin Makaila on 4/5/15.
//  Copyright (c) 2015 Present, Inc. All rights reserved.
//

import UIKit
import CameraKit
import AssetsLibrary

class ViewController: UIViewController {
    @IBOutlet
    private var cameraPreview: UIView!
    
    // Toggle camera button
    @IBOutlet
    private var toggleCameraButton: UIButton!
    
    // Toggle LED button
    @IBOutlet
    private var toggleLEDButton: UIButton!
    
    // Capture still image
    @IBOutlet
    private var captureStillImageButton: UIButton!
    
    // Zoom gesture
    @IBOutlet
    private var zoomGestureRecognizer: UIPinchGestureRecognizer!
    
    // Tap to focus
    @IBOutlet
    private var focusGestureRecognizer: UITapGestureRecognizer!
    
    private var cameraController: CameraController!
    
    private var captureStillImage: Bool = false
    
    private var currentPinchGestureScale: CGFloat = 0.0
    private var currentZoomScale: CGFloat = 1.0

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
    
    @IBAction
    func toggleCamera(sender: UIButton) {
        cameraController.toggleCameraPosition()
    }
    
    @IBAction
    func toggleLED(sender: UIButton) {
        cameraController.toggleLED()
    }
    
    @IBAction
    func captureStillImage(sender: UIButton) {
        captureStillImage = true
    }
    
    @IBAction
    func zoomGestureRecognized(sender: UIGestureRecognizer) {
        // New zoom scale is the current pinch gesture scale multiplied by the recognized pinch
        // gesture's scale.
        let newZoomScale: CGFloat = currentPinchGestureScale * zoomGestureRecognizer.scale
        
        // If the new zoom scale is within the possible range, update the current zoom scale,
        // and set the camera controller's zoom to it.
        if cameraController.setZoom(newZoomScale) {
            currentZoomScale = newZoomScale
        }
    }
    
    @IBAction
    func focusGestureRecognized(sender: UIGestureRecognizer) {
        // Locate point of recognized tap gesture
        let focusPoint = focusGestureRecognizer.locationInView(cameraPreview)
        
        // Update camera controller's focus & exposure modes to continuously auto-focus on the
        // point of the tap gesture.
        cameraController.setFocusMode(AVCaptureFocusMode.ContinuousAutoFocus, atPoint: focusPoint)
        cameraController.setExposureMode(AVCaptureExposureMode.ContinuousAutoExposure, atPoint: focusPoint)
    }
}

extension ViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == zoomGestureRecognizer {
            currentPinchGestureScale = currentZoomScale
        }
        
        return true
    }
}

extension ViewController: CameraControllerDelegate {
    func cameraController(controller: CameraController, didOutputSampleBuffer sampleBuffer: CMSampleBufferRef, type: CameraController.FrameType) {
        if captureStillImage && type == .Video {
            //let image: CGImageRef = cgImageFromSampleBuffer(sampleBuffer)
            //saveCGImageToCameraRoll(image)
            
            captureStillImage = false
        }
    }
    
    func cameraController(controller: CameraController, didEncounterError error: NSError) {
        println("Camera controller did encounter error: \(error)")
    }
}

private extension ViewController {
    func saveCGImageToCameraRoll(imageRef: CGImageRef) {
        if let image = UIImage(CGImage: imageRef) {
            saveImageToCameraRoll(image)
        }
    }
    
    func saveImageToCameraRoll(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, "successfullySavedImage", nil)
    }
    
    func successfullySavedImage() {
        println("Successfully saved image!")
    }
}

private extension ViewController {
    func setup() {
        cameraPreview.frame = view.bounds
        
        cameraController = CameraController(view: cameraPreview)
        cameraController.delegate = self
        
        cameraController.setLowLightBoost()
    }
}

