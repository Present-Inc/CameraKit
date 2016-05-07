import UIKit
import AssetsLibrary

public class CameraViewController: UIViewController, CameraControllerDelegate {
    public var captureModes: Set<CameraController.CaptureMode> { return [.Video] }
    private(set) var cameraController: CameraController!
    
    @IBOutlet
    var cameraPreview: UIView!
    
    // Toggle camera button
    @IBOutlet
    var toggleCameraButton: UIButton? {
        didSet {
            toggleCameraButton?.addTarget(self, action: #selector(CameraViewController.toggleCamera(_:)), forControlEvents: .TouchUpInside)
        }
    }
    
    // Toggle LED button
    @IBOutlet
    var toggleLEDButton: UIButton? {
        didSet {
            toggleLEDButton?.addTarget(self, action: #selector(CameraViewController.toggleLED(_:)), forControlEvents: .TouchUpInside)
        }
    }
    
    // Capture still image
    @IBOutlet
    var captureStillImageButton: UIButton? {
        didSet {
            captureStillImageButton?.addTarget(self, action: #selector(CameraViewController.captureStillImage(_:)), forControlEvents: .TouchUpInside)
        }
    }
    
    // Zoom gesture
    @IBOutlet
    var zoomGestureRecognizer: UIPinchGestureRecognizer? {
        didSet {
            zoomGestureRecognizer?.delegate = self
            zoomGestureRecognizer?.addTarget(self, action: #selector(CameraViewController.zoomGestureRecognized(_:)))
        }
    }
    
    // Tap to focus
    @IBOutlet
    var focusGestureRecognizer: UITapGestureRecognizer? {
        didSet {
            focusGestureRecognizer?.delegate = self
            focusGestureRecognizer?.addTarget(self, action: #selector(CameraViewController.focusGestureRecognized(_:)))
        }
    }
    
    private var currentPinchGestureScale: CGFloat = 0.0
    private var currentZoomScale: CGFloat = 1.0

    public override func viewDidLoad() {
        super.viewDidLoad()
        
        setup()
    }
    
    public override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        
        cameraController.startCaptureSession()
    }
    
    public override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        
        cameraController.stopCaptureSession()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraController.previewLayer.frame = cameraPreview.bounds
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
            print("Could not toggle LED", error)
        }
    }
    
    @IBAction
    func captureStillImage(sender: UIButton) {
        do {
            try cameraController.captureStillImage()
        }
        catch {
            print("Could not capture still image", error)
        }
    }
    
    @IBAction
    func zoomGestureRecognized(sender: UIPinchGestureRecognizer) {
        // New zoom scale is the current pinch gesture scale multiplied by the recognized pinch
        // gesture's scale.
        let newZoomScale: CGFloat = currentPinchGestureScale * sender.scale
        
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
    func focusGestureRecognized(sender: UITapGestureRecognizer) {
        // Locate point of recognized tap gesture
        let focusPoint = sender.locationInView(cameraPreview)
        
        // Update camera controller's focus & exposure modes to continuously auto-focus on the
        // point of the tap gesture.
        do {
            try cameraController.setFocusMode(AVCaptureFocusMode.ContinuousAutoFocus, atPoint: focusPoint)
            try cameraController.setExposureMode(AVCaptureExposureMode.ContinuousAutoExposure, atPoint: focusPoint)
        } catch {
            print("Could not set focus or exposure mode")
        }
    }
    
    
}

extension CameraViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(gestureRecognizer: UIGestureRecognizer) -> Bool {
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
        
        do {
            try cameraController.configureAudioSession(AVAudioSessionCategoryPlayAndRecord, options: [.MixWithOthers, .DefaultToSpeaker])
        } catch {
            print("Could not configure audio sessions with desired settings")
        }
    }
}

