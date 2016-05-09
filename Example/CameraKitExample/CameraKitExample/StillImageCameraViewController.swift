import UIKit
import CameraKit


class StillImageCameraViewController: CameraViewController {
    override var captureModes: Set<CameraController.CaptureMode> { return [.Photo] }
    
    func successfullySavedImage(image: UIImage, error: NSError, context: UnsafeMutablePointer<Void>) {
        print("Successfully saved image!")
    }
}

extension StillImageCameraViewController {
    override func cameraController(controller: CameraController, didOutputImage image: UIImage) {
        saveImageToCameraRoll(image)
    }
}

internal extension StillImageCameraViewController {
    func saveImageToCameraRoll(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(StillImageCameraViewController.successfullySavedImage(_:error:context:)), nil)
    }
}
