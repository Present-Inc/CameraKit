import UIKit

final class SlowMotionCameraViewController: CameraViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        try! cameraController.setSlowMotion()
    }
}