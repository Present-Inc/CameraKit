import UIKit
import CameraKit


class StillImageCameraViewController: UIViewController {
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
    
    override func viewDidLayoutSubviews() {
        cameraPreview.frame = view.bounds;
    }
    
    @IBAction
    func toggleCamera(sender: UIButton) {
        cameraController.toggleCameraPosition()
    }
    
    @IBAction
    func toggleLED(sender: UIButton) {
        do {
            try cameraController.toggleLED()
        } catch {
            print("Could not toggle LED. Update button state to reflect this")
        }
    }
    
    @IBAction
    func captureStillImage(sender: UIButton) {
        do {
            try cameraController.captureStillImage()
        }
        catch {
            print("Could not capture still image")
        }
    }
    
    @IBAction
    func zoomGestureRecognized(sender: UIGestureRecognizer) {
        // New zoom scale is the current pinch gesture scale multiplied by the recognized pinch
        // gesture's scale.
        let newZoomScale: CGFloat = currentPinchGestureScale * zoomGestureRecognizer.scale
        
        // If the new zoom scale is within the possible range, update the current zoom scale,
        // and set the camera controller's zoom to it.
        do {
            try cameraController.setZoom(newZoomScale)
            currentZoomScale = newZoomScale
        } catch {
            print("Could not set zoom!")
        }
    }
    
    @IBAction
    func focusGestureRecognized(sender: UIGestureRecognizer) {
        // Locate point of recognized tap gesture
        let focusPoint = focusGestureRecognizer.locationInView(cameraPreview)
        
        // Update camera controller's focus & exposure modes to continuously auto-focus on the
        // point of the tap gesture.
        do {
            try cameraController.setFocusMode(AVCaptureFocusMode.ContinuousAutoFocus, atPoint: focusPoint)
            try cameraController.setExposureMode(AVCaptureExposureMode.ContinuousAutoExposure, atPoint: focusPoint)
        } catch {
            print("Could not set focus or exposure mode")
        }
    }
    
    @IBAction
    func closeButtonPressed(sender: AnyObject) {
        dismissViewControllerAnimated(true, completion: nil)
    }
    
    func successfullySavedImage(image: UIImage, error: NSError, context: UnsafeMutablePointer<Void>) {
        print("Successfully saved image!")
    }
}

extension StillImageCameraViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == zoomGestureRecognizer {
            currentPinchGestureScale = currentZoomScale
        }
        
        return true
    }
}

extension StillImageCameraViewController: CameraControllerDelegate {
    func cameraController(controller: CameraController, didOutputImage image: UIImage) {
        saveImageToCameraRoll(image)
    }
    
    func cameraController(controller: CameraController, didOutputSampleBuffer sampleBuffer: CMSampleBufferRef, type: CameraController.FrameType) {
        // TODO: Process video and audio frames here
    }
    
    func cameraController(controller: CameraController, didEncounterError error: NSError) { }
    
    func cameraController(controller: CameraController, didStartCaptureSession started: Bool) { }
}

internal extension StillImageCameraViewController {
    func saveImageToCameraRoll(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, "successfullySavedImage:error:context:", nil)
    }
}

private extension StillImageCameraViewController {
    func setup() {
        cameraPreview.frame = view.bounds
        
        do {
            cameraController = try CameraController(view: cameraPreview, captureModes: [.Photo])
            cameraController.delegate = self
        } catch {
            fatalError("Could not setup camera controller")
        }
        
        do {
            try cameraController.configureAudioSession(AVAudioSessionCategoryPlayAndRecord, options: [.MixWithOthers, .DefaultToSpeaker])
        } catch {
            print("Could not configure audio sessions with desired settings")
        }
    }
}