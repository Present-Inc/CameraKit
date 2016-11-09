import UIKit
import AssetsLibrary


open class CameraViewController: UIViewController, CameraControllerDelegate {
    open var captureModes: Set<CameraController.CaptureMode> { return [.video] }
    public fileprivate(set) var cameraController: CameraController!
    
    @IBOutlet
    open var cameraPreview: UIView!
    
    // Toggle camera button
    @IBOutlet
    open var toggleCameraButton: UIButton? {
        didSet {
            toggleCameraButton?.addTarget(self, action: #selector(CameraViewController.toggleCamera(_:)), for: .touchUpInside)
        }
    }
    
    // Toggle LED button
    @IBOutlet
    open var toggleLEDButton: UIButton? {
        didSet {
            toggleLEDButton?.addTarget(self, action: #selector(CameraViewController.toggleLED(_:)), for: .touchUpInside)
        }
    }
    
    // Capture still image
    @IBOutlet
    open var captureStillImageButton: UIButton? {
        didSet {
            captureStillImageButton?.addTarget(self, action: #selector(CameraViewController.captureStillImage(_:)), for: .touchUpInside)
        }
    }
    
    // Zoom gesture
    @IBOutlet
    open var zoomGestureRecognizer: UIPinchGestureRecognizer? {
        didSet {
            zoomGestureRecognizer?.delegate = self
            zoomGestureRecognizer?.addTarget(self, action: #selector(CameraViewController.zoomGestureRecognized(_:)))
        }
    }
    
    // Tap to focus
    @IBOutlet
    open var focusGestureRecognizer: UITapGestureRecognizer? {
        didSet {
            focusGestureRecognizer?.delegate = self
            focusGestureRecognizer?.addTarget(self, action: #selector(CameraViewController.focusGestureRecognized(_:)))
        }
    }
    
    fileprivate var currentPinchGestureScale: CGFloat = 0.0
    fileprivate var currentZoomScale: CGFloat = 1.0
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        cameraController.startCaptureSession()
    }
    
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cameraController.stopCaptureSession()
    }
    
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraController.previewLayer.frame = cameraPreview.bounds
    }
    
    @IBAction
    open func toggleCamera(_ sender: UIButton) {
        let _ = cameraController.toggleCameraPosition()
    }
    
    @IBAction
    open func toggleLED(_ sender: UIButton) {
        do {
            try cameraController.toggleLED()
        } catch {
            print("Could not toggle LED", error)
        }
    }
    
    @IBAction
    open func captureStillImage(_ sender: UIButton) {
        do {
            try cameraController.captureStillImage()
        }
        catch {
            print("Could not capture still image", error)
        }
    }
    
    @IBAction
    open func zoomGestureRecognized(_ sender: UIPinchGestureRecognizer) {
        // New zoom scale is the current pinch gesture scale multiplied by the recognized pinch
        // gesture's scale.
        let newZoomScale: CGFloat = currentPinchGestureScale * sender.scale
        
        // If the new zoom scale is within the possible range, update the current zoom scale,
        // and set the camera controller's zoom to it.
        do {
            let _ = try cameraController.setZoom(newZoomScale)
            currentZoomScale = newZoomScale
        } catch {
            print("Could not set zoom!")
        }
    }
    
    @IBAction
    open func focusGestureRecognized(_ sender: UITapGestureRecognizer) {
        // Locate point of recognized tap gesture
        let focusPoint = sender.location(in: cameraPreview)
        
        // Update camera controller's focus & exposure modes to continuously auto-focus on the
        // point of the tap gesture.
        do {
            try cameraController.setFocusMode(AVCaptureFocusMode.continuousAutoFocus, atPoint: focusPoint)
            try cameraController.setExposureMode(AVCaptureExposureMode.continuousAutoExposure, atPoint: focusPoint)
        } catch {
            print("Could not set focus or exposure mode")
        }
    }
    
    /// Override this method to handle a captured image.
    open func cameraController(_ controller: CameraController, didOutputImage image: UIImage) { }
    
    /// Override this method to handle sample buffers as they're captured.
    open func cameraController(_ controller: CameraController, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, type: CameraController.FrameType) { }
}

extension CameraViewController: UIGestureRecognizerDelegate {
    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == zoomGestureRecognizer {
            currentPinchGestureScale = currentZoomScale
        }
        
        return true
    }
}

private extension CameraViewController {
    func setup() {
        do {
            cameraController = try CameraController(view: cameraPreview, captureModes: captureModes)
            cameraController.delegate = self
        } catch {
            fatalError("Could not setup camera controller")
        }
    }
}

