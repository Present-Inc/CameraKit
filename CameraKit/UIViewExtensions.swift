import UIKit
import AVFoundation

public extension UIView {
    public func add(previewLayer: AVCaptureVideoPreviewLayer) {
        layer.masksToBounds = true
        previewLayer.frame = layer.bounds
        layer.addSublayer(previewLayer)
    }
    
    public func removePreviewLayer() {
        for layer in layer.sublayers ?? [] {
            if layer is AVCaptureVideoPreviewLayer {
                layer.removeFromSuperlayer()
            }
        }
    }
}
