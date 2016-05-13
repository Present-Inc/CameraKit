import UIKit
import CameraKit


class StillImageCameraViewController: BaseCameraViewController {
    override var captureModes: Set<CameraController.CaptureMode> { return [.Photo] }
    
    override func cameraController(controller: CameraController, didOutputImage image: UIImage) {
        saveImageToCameraRoll(image)
    }
    
    func saveImageToCameraRoll(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(StillImageCameraViewController.successfullySavedImage(_:error:context:)), nil)
    }
    
    func successfullySavedImage(image: UIImage, error: NSError, context: UnsafeMutablePointer<Void>) {
        print("Successfully saved image!")
    }
}
