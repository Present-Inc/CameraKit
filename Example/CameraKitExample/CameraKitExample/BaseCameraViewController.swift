import UIKit
import CameraKit

protocol CaptureSessionObserver {
    var cameraController: CameraController! { get }
    
    func setupCaptureSessionObserver()
}

extension CaptureSessionObserver {
    func setupCaptureSessionObserver() {
        let notificationCenter = NSNotificationCenter.defaultCenter()
        let captureSession = cameraController.captureSession
        notificationCenter.addObserverForName(AVCaptureSessionRuntimeErrorNotification, object: captureSession, queue: nil) { notification in
            debugPrint("Capture session did encounter runtime error:", notification)
        }
        
        notificationCenter.addObserverForName(AVCaptureSessionWasInterruptedNotification, object: captureSession, queue: nil) { notification in
            debugPrint("Capture session was interrupted:", notification)
        }
        
        notificationCenter.addObserverForName(AVCaptureSessionInterruptionEndedNotification, object: captureSession, queue: nil) { notification in
            debugPrint("Capture session interruption did end:", notification)
        }
        
        notificationCenter.addObserverForName(AVCaptureSessionDidStartRunningNotification, object: captureSession, queue: nil) { notification in
            debugPrint("Capture session did start running:", notification)
        }
        
        notificationCenter.addObserverForName(AVCaptureSessionDidStopRunningNotification, object: captureSession, queue: nil) { notification in
            debugPrint("Capture session did stop running:", notification)
        }
    }
}


class BaseCameraViewController: CameraViewController, CaptureSessionObserver {
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupCaptureSessionObserver()
    }
    
    @IBAction
    func closeButtonPressed(sender: UIButton!) {
        dismissViewControllerAnimated(true, completion: nil)
    }
}