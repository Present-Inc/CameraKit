import UIKit
import CameraKit

final class SlowMotionCameraViewController: CameraViewController {
    override var captureModes: Set<CameraController.CaptureMode> { return [.SlowMotionVideo] }
}