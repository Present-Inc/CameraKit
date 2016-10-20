import UIKit
import CameraKit
import Photos


class VideoCameraViewController: BaseCameraViewController {
    override var captureModes: Set<CameraController.CaptureMode> { return [.video] }
    
    @IBOutlet
    fileprivate var captureButton: UIButton! {
        didSet {
            captureButton.addTarget(self, action: #selector(toggleRecording(_:)), for: .touchUpInside)
        }
    }
    
    fileprivate var recording: Bool = false
    
    fileprivate var movieFileOutput: AVCaptureMovieFileOutput!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    func toggleRecording(_ sender: UIButton) {
        recording = !recording
        recording ? movieFileOutput.startRecording(toOutputFileURL: newOutputFileURL(), recordingDelegate: self) : movieFileOutput.stopRecording()
    }
}

extension VideoCameraViewController: AVCaptureFileOutputRecordingDelegate {
    func newOutputFileURL() -> URL {
        let outputPath = NSTemporaryDirectory() + "output\(Date().timeIntervalSince1970.description).mov"
        return URL(fileURLWithPath: outputPath)
    }
    
    func capture(_ captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAt fileURL: URL!, fromConnections connections: [Any]!) { }
    func capture(_ captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAt outputFileURL: URL!, fromConnections connections: [Any]!, error: Error!) {
        let alertController = UIAlertController(title: "Save", message: "Would you like to save this video?", preferredStyle: .alert)
        
        alertController.addAction(UIAlertAction(title: "No", style: .destructive, handler: nil))
        alertController.addAction(UIAlertAction(title: "Yes", style: .cancel, handler: { _ in
            self.saveVideoFileAtURL(outputFileURL)
        }))
        
        present(alertController, animated: true, completion: nil)
    }
    
    fileprivate func saveVideoFileAtURL(_ url: URL) {
        findOrCreateAlbum("Camera Kit Example") { album in
            guard let album = album
            else {
                return
            }
            
            self.saveVideoFile(url, inAlbum: album)
        }
    }
    
    fileprivate func saveVideoFile(_ url: URL, inAlbum album: PHAssetCollection, completion: ((Bool, NSError) -> Void)? = nil) {
        PHPhotoLibrary
            .shared()
            .performChanges({
                guard let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url),
                    let assetPlaceholder = assetRequest.placeholderForCreatedAsset,
                    let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                    else {
                        return
                }
                
                let assets: NSFastEnumeration = [assetPlaceholder] as NSFastEnumeration
                albumChangeRequest.addAssets(assets)
            },
            completionHandler: { success, error in
                print("Successfully saved video")
            }
        )
    }
    
    fileprivate func findOrCreateAlbum(_ albumName: String, completion: ((PHAssetCollection?) -> Void)? = nil) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
        let collection = PHAssetCollection.fetchAssetCollections(with: PHAssetCollectionType.album, subtype: PHAssetCollectionSubtype.any, options: fetchOptions)
        
        if let assetCollection = collection.firstObject {
            completion?(assetCollection)
        } else {
            var assetCollectionPlaceholder: PHObjectPlaceholder? = nil
            PHPhotoLibrary.shared()
                .performChanges({
                    let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                    assetCollectionPlaceholder = createAlbumRequest.placeholderForCreatedAssetCollection
                },
                completionHandler: { success, error in
                    if success {
                        var localIdentifiers: [String] = []
                        if let identifier = assetCollectionPlaceholder?.localIdentifier {
                            localIdentifiers.append(identifier)
                        }
                        
                        let collectionFetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: localIdentifiers, options: nil)
                        if let assetCollection = collectionFetchResult.firstObject {
                            completion?(assetCollection)
                            return
                        }
                    }
                    
                    completion?(nil)
                }
            )
        }
    }
    
    
}

private extension VideoCameraViewController {
    func setup() {
        movieFileOutput = AVCaptureMovieFileOutput()
        cameraController.addOutput(movieFileOutput)
    }
}
