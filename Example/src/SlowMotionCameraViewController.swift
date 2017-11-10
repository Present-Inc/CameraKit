import UIKit
import CameraKit


final class SlowMotionCameraViewController: VideoCameraViewController {
    override var captureModes: Set<CameraController.CaptureMode> { return [.slowMotionVideo] }
}
