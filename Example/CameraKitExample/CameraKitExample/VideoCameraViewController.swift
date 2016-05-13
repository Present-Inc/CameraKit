import UIKit
import CameraKit
import Photos


class VideoCameraViewController: BaseCameraViewController {
    override var captureModes: Set<CameraController.CaptureMode> { return [.Video] }
    
    @IBOutlet
    private var captureButton: UIButton! {
        didSet {
            captureButton.addTarget(self, action: #selector(toggleRecording(_:)), forControlEvents: .TouchUpInside)
        }
    }
    
    private var recording: Bool = false
    
    private var movieFileOutput: AVCaptureMovieFileOutput!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    func toggleRecording(sender: UIButton) {
        recording = !recording
        recording ? movieFileOutput.startRecordingToOutputFileURL(newOutputFileURL(), recordingDelegate: self) : movieFileOutput.stopRecording()
    }
}

extension VideoCameraViewController: AVCaptureFileOutputRecordingDelegate {
    func newOutputFileURL() -> NSURL {
        let outputPath = NSTemporaryDirectory() + "output\(NSDate().timeIntervalSince1970.description).mov"
        return NSURL(fileURLWithPath: outputPath)
    }
    
    func captureOutput(captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAtURL fileURL: NSURL!, fromConnections connections: [AnyObject]!) { }
    func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError!) {
        let alertController = UIAlertController(title: "Save", message: "Would you like to save this video?", preferredStyle: .Alert)
        
        alertController.addAction(UIAlertAction(title: "No", style: .Destructive, handler: nil))
        alertController.addAction(UIAlertAction(title: "Yes", style: .Cancel, handler: { _ in
            self.saveVideoFileAtURL(outputFileURL)
        }))
        
        presentViewController(alertController, animated: true, completion: nil)
    }
    
    private func saveVideoFileAtURL(url: NSURL) {
        findOrCreateAlbum("Camera Kit Example") { album in
            guard let album = album
            else {
                return
            }
            
            self.saveVideoFile(url, inAlbum: album)
        }
    }
    
    private func saveVideoFile(url: NSURL, inAlbum album: PHAssetCollection, completion: ((Bool, NSError) -> Void)? = nil) {
        PHPhotoLibrary
            .sharedPhotoLibrary()
            .performChanges({
                guard let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideoAtFileURL(url),
                    let assetPlaceholder = assetRequest.placeholderForCreatedAsset,
                    let albumChangeRequest = PHAssetCollectionChangeRequest(forAssetCollection: album)
                    else {
                        return
                }
                
                albumChangeRequest.addAssets([assetPlaceholder])
            },
            completionHandler: { success, error in
                print("Successfully saved video")
            }
        )
    }
    
    private func findOrCreateAlbum(albumName: String, completion: (PHAssetCollection? -> Void)? = nil) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
        let collection = PHAssetCollection.fetchAssetCollectionsWithType(PHAssetCollectionType.Album, subtype: PHAssetCollectionSubtype.Any, options: fetchOptions)
        
        if let assetCollection = collection.firstObject as? PHAssetCollection {
            completion?(assetCollection)
        } else {
            var assetCollectionPlaceholder: PHObjectPlaceholder? = nil
            PHPhotoLibrary.sharedPhotoLibrary()
                .performChanges({
                    let createAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollectionWithTitle(albumName)
                    assetCollectionPlaceholder = createAlbumRequest.placeholderForCreatedAssetCollection
                },
                completionHandler: { success, error in
                    if success {
                        var localIdentifiers: [String] = []
                        if let identifier = assetCollectionPlaceholder?.localIdentifier {
                            localIdentifiers.append(identifier)
                        }
                        
                        let collectionFetchResult = PHAssetCollection.fetchAssetCollectionsWithLocalIdentifiers(localIdentifiers, options: nil)
                        if let assetCollection = collectionFetchResult.firstObject as? PHAssetCollection {
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