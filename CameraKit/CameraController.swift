//
//  CameraController.swift
//  CameraKit
//
//  Created by Justin Makaila on 4/5/15.
//  Copyright (c) 2015 Present, Inc. All rights reserved.
//

import UIKit
import CoreGraphics

let CameraKitDomain = "tv.present.CameraKit"
private let VideoOutputQueueIdentifier = CameraKitDomain + ".videoQueue"
private let AudioOutputQueueIdentifier = CameraKitDomain + ".audioQueue"

private let MaxZoomFactor: CGFloat = 8.0

public protocol CameraControllerDelegate {
    func cameraController(controller: CameraController, didOutputSampleBuffer sampleBuffer: CMSampleBufferRef, type: CameraController.FrameType)
    func cameraController(controller: CameraController, didEncounterError error: NSError)
    
    func cameraController(controller: CameraController, didStartCaptureSession started: Bool)
}

public class CameraController: NSObject {
    public enum FrameType {
        case Audio
        case Video
    }
    
    public var delegate: CameraControllerDelegate?
    
    public let captureSession: AVCaptureSession = AVCaptureSession()
    public let previewLayer: AVCaptureVideoPreviewLayer = AVCaptureVideoPreviewLayer()
    
    public var cameraPosition: AVCaptureDevicePosition = .Back {
        didSet {
            setCamera(cameraPosition)
        }
    }
    
    private var paused: Bool = false
    private var configuringCaptureSession: Bool = false
    
    private var frontCameraDevice: AVCaptureDevice?
    private var backCameraDevice: AVCaptureDevice?
    private var audioCaptureDevice: AVCaptureDevice?
    
    private var frontCameraDeviceInput: AVCaptureDeviceInput?
    private var backCameraDeviceInput: AVCaptureDeviceInput?
    
    // Capture session inputs
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    
    // Capture session output
    private var videoDeviceOutput: AVCaptureVideoDataOutput?
    private var audioDeviceOutput: AVCaptureAudioDataOutput?
    
    // Capture session connections
    private var videoConnection: AVCaptureConnection?
    private var audioConnection: AVCaptureConnection?
    
    // Used as the callback queue for the AVCaptureVideoDataOutput
    private let videoOutputQueue: dispatch_queue_t = dispatch_queue_create(VideoOutputQueueIdentifier, DISPATCH_QUEUE_SERIAL)
    // Used as the callback queue for the AVCaptureAudioDataOutput
    private let audioOutputQueue: dispatch_queue_t = dispatch_queue_create(AudioOutputQueueIdentifier, DISPATCH_QUEUE_SERIAL)
    
    deinit {
        teardownCaptureSession()
    }
    
    public override init() {
        super.init()
        
        setup()
    }
    
    public convenience init(view: UIView) {
        self.init()
        
        previewLayer.connection.videoOrientation = .Portrait
        
        // Add the preview layer to the view
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
    }
    
    public func startCaptureSession() {
        captureSession.startRunning()
    }
    
    public func stopCaptureSession() {
        captureSession.stopRunning()
    }
    
    public func configureAudioSession(category: String, options: AVAudioSessionCategoryOptions) {
        let audioSession = AVAudioSession.sharedInstance()
        
        var error: NSError?
        if !audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord, withOptions: .MixWithOthers, error: &error) {
            println("An error occurred: \(error!)")
        }
        
        if !audioSession.setActive(true, error: &error) {
            println("An error occurred: \(error!)")
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        if configuringCaptureSession {
            return
        }
        
        if connection == videoConnection {
            delegate?.cameraController(self, didOutputSampleBuffer: sampleBuffer, type: .Video)
        } else if connection == audioConnection {
            delegate?.cameraController(self, didOutputSampleBuffer: sampleBuffer, type: .Audio)
        }
    }
}

// MARK: - Camera Methods

public extension CameraController {
    // MARK: Focus
    /**
        TODO: Support setting the focus mode with point defaulting to previewLayer.center
     */
    func setFocusMode(focusMode: AVCaptureFocusMode, atPoint point: CGPoint) {
        let focusPoint = previewLayer.captureDevicePointOfInterestForPoint(point)
        
        if let videoDevice = currentVideoDevice {
            if videoDevice.focusPointOfInterestSupported && videoDevice.isFocusModeSupported(focusMode) {
                var lockError: NSError?
                
                if videoDevice.lockForConfiguration(&lockError) {
                    videoDevice.focusPointOfInterest = focusPoint
                    videoDevice.focusMode = focusMode
                    
                    videoDevice.unlockForConfiguration()
                }
            }
        }
    }
    
    // MARK: Exposure
    /**
        TODO: Support setting the exposure mode with point defaulting to previewLayer.center
     */
    func setExposureMode(exposureMode: AVCaptureExposureMode, atPoint point: CGPoint) {
        let exposurePoint = previewLayer.captureDevicePointOfInterestForPoint(point)
        
        if let videoDevice = currentVideoDevice {
            if videoDevice.exposurePointOfInterestSupported && videoDevice.isExposureModeSupported(exposureMode) {
                var lockError: NSError?
                
                if videoDevice.lockForConfiguration(&lockError) {
                    videoDevice.exposurePointOfInterest = exposurePoint
                    videoDevice.exposureMode = exposureMode
                    
                    videoDevice.unlockForConfiguration()
                }
            }
        }
    }
    
    // MARK: White Balance
    func setWhiteBalanceMode(whiteBalanceMode: AVCaptureWhiteBalanceMode) {
        if let videoDevice = currentVideoDevice {
            if videoDevice.isWhiteBalanceModeSupported(whiteBalanceMode) {
                var lockError: NSError?
                
                if videoDevice.lockForConfiguration(&lockError) {
                    videoDevice.whiteBalanceMode = whiteBalanceMode
                    
                    videoDevice.unlockForConfiguration()
                }
            }
        }
    }
    
    // MARK: Low Light Boost
    func setLowLightBoost(automaticallyEnabled: Bool = true) {
        if let videoDevice = currentVideoDevice {
            if videoDevice.lowLightBoostSupported {
                var lockError: NSError?
                
                if videoDevice.lockForConfiguration(&lockError) {
                    videoDevice.automaticallyEnablesLowLightBoostWhenAvailable = automaticallyEnabled
                    
                    videoDevice.unlockForConfiguration()
                }
            }
        }
    }
    
    // MARK: Torch
    func setTorchMode(mode: AVCaptureTorchMode) {
        if let device = currentVideoDevice {
            if device.hasTorch && device.torchAvailable {
                var lockError: NSError?
                if device.lockForConfiguration(&lockError) {
                    device.torchMode = mode
                    
                    device.unlockForConfiguration()
                }
            }
        }
    }
    
    func toggleLED() {
        if let device = currentVideoDevice {
            if device.hasTorch && device.torchAvailable {
                var lockError: NSError?
                if device.lockForConfiguration(&lockError) {
                    switch(device.torchMode) {
                    case .Off:
                        device.torchMode = .On
                    case .On:
                        device.torchMode = .Off
                    default:
                        break
                    }
                    
                    device.unlockForConfiguration()
                }
            }
        }
    }
    
    // MARK: Zoom
    func setZoom(zoomLevel: CGFloat) -> Bool {
        if let videoDevice = currentVideoDevice {
            if zoomLevel <= MaxZoomFactor && zoomLevel >= 1 {
                var lockError: NSError?
                if videoDevice.lockForConfiguration(&lockError) {
                    videoDevice.videoZoomFactor = zoomLevel
                    videoDevice.unlockForConfiguration()
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: Camera Position
    
    /**
    Convenience method for toggling the camera position.
    */
    func toggleCameraPosition() -> Bool {
        cameraPosition = (cameraPosition == .Back) ? .Front : .Back
        return true
    }
    
    private func setCamera(position: AVCaptureDevicePosition) -> Bool {
        let deviceInput = position == .Front ? frontCameraDeviceInput : backCameraDeviceInput
        
        if let deviceInput = deviceInput {
            configureCaptureSession { captureSession in
                self.replaceCurrentVideoDeviceInputWithDeviceInput(deviceInput)
            }
            
            return true
        }
        
        return false
    }
    
    func configureCaptureSession(closure: (AVCaptureSession) -> ()) {
        configuringCaptureSession = true
    
        stopCaptureSession()
        
        captureSession.beginConfiguration()
        closure(captureSession)
        captureSession.commitConfiguration()
        
        startCaptureSession()
        
        configuringCaptureSession = false
    }
}

// MARK: - Setup Methods

private extension CameraController {
    func setup() {
        setupPreviewLayer()
        setupCaptureSession()
    }
    
    func setupPreviewLayer() {
        previewLayer.session = captureSession
        previewLayer.videoGravity = AVVideoScalingModeFit
    }
    
    func setupCaptureSession() {
        captureSession.automaticallyConfiguresApplicationAudioSession = false
        
        addCaptureSessionObserver()
        
        // Set the session preset
        captureSession.sessionPreset = AVCaptureSessionPresetHigh
        
        // Setup capture devices
        setupCaptureDevices()
        
        // Setup device inputs
        setupVideoDeviceInput()
        setupAudioDeviceInput()
        
        // Setup device outputs
        setupVideoDeviceOutput()
        setupAudioDeviceOutput()
        
        // Setup connections
        setupVideoConnection()
        setupAudioConnection()
    }
}

// MARK: - Capture Session Utilities

private extension CameraController {
    func setupCaptureDevices() {
        frontCameraDevice = videoDeviceForPosition(.Front)
        backCameraDevice = videoDeviceForPosition(.Back)
        audioCaptureDevice = defaultAudioDevice
        
        frontCameraDeviceInput = AVCaptureDeviceInput.deviceInputWithDevice(frontCameraDevice!, error: nil) as? AVCaptureDeviceInput
        backCameraDeviceInput = AVCaptureDeviceInput.deviceInputWithDevice(backCameraDevice!, error: nil) as? AVCaptureDeviceInput
    }
    
    func setupVideoDeviceInput() {
        if let videoInput = videoDeviceInput {
            captureSession.removeInput(videoInput)
        }
        
        // Setup the video device input
        var videoDeviceError: NSError?
        videoDeviceInput = AVCaptureDeviceInput.deviceInputWithDevice(defaultVideoDevice, error: &videoDeviceError) as? AVCaptureDeviceInput
        if let error = videoDeviceError {
            delegate?.cameraController(self, didEncounterError: error)
        }
        
        // Add the video device input
        addInput(videoDeviceInput)
    }
    
    func setupAudioDeviceInput() {
        if let audioInput = audioDeviceInput {
            captureSession.removeInput(audioInput)
        }
        
        // Setup the audio device input
        var audioDeviceError: NSError?
        audioDeviceInput = AVCaptureDeviceInput.deviceInputWithDevice(defaultAudioDevice, error: &audioDeviceError) as? AVCaptureDeviceInput
        if let error = audioDeviceError {
            delegate?.cameraController(self, didEncounterError: error)
        }
        
        addInput(audioDeviceInput)
    }
    
    func setupVideoDeviceOutput() {
        // If there's already a `videoDeviceOutput`, remove it
        if let videoOutput = videoDeviceOutput {
            captureSession.removeOutput(videoOutput)
        }
        
        // Setup the video device output
        videoDeviceOutput = AVCaptureVideoDataOutput()
        videoDeviceOutput?.setSampleBufferDelegate(self, queue: videoOutputQueue)
        videoDeviceOutput?.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        
        // Add the video device output
        addOutput(videoDeviceOutput)
    }
    
    func setupAudioDeviceOutput() {
        // If there's already an `audioDeviceOutput`, remove it
        if let audioOutput = audioDeviceOutput {
            captureSession.removeOutput(audioOutput)
        }
        
        // Setup the audio device output
        audioDeviceOutput = AVCaptureAudioDataOutput()
        audioDeviceOutput?.setSampleBufferDelegate(self, queue: audioOutputQueue)
        
        // Add the audio device output
        addOutput(audioDeviceOutput)
    }
    
    func setupVideoConnection() {
        // Setup the video connction
        videoConnection = videoDeviceOutput?.connectionWithMediaType(AVMediaTypeVideo)
        
        // TODO: Support different video orientations
        videoConnection?.videoOrientation = .Portrait
        videoConnection?.preferredVideoStabilizationMode = .Auto
    }
    
    func setupAudioConnection() {
        // Setup the audio connection
        audioConnection = audioDeviceOutput?.connectionWithMediaType(AVMediaTypeAudio)
    }
    
    func addInput(input: AVCaptureInput?) {
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
    }
    
    func addOutput(output: AVCaptureOutput?) {
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        }
    }
    
    func addCaptureSessionObserver() {
        let notificationCenter = NSNotificationCenter.defaultCenter()
        
        notificationCenter.addObserver(self, selector: "captureSessionDidStartRunning:", name: AVCaptureSessionDidStartRunningNotification, object: self.captureSession)
        notificationCenter.addObserver(self, selector: "captureSessionDidStopRunning:", name: AVCaptureSessionDidStopRunningNotification, object: self.captureSession)
        notificationCenter.addObserver(self, selector: "captureSessionDidFailWithError:", name: AVCaptureSessionRuntimeErrorNotification, object: self.captureSession)
        notificationCenter.addObserver(self, selector: "captureSessionWasInterrupted:", name: AVCaptureSessionWasInterruptedNotification, object: self.captureSession)
    }
    
    func removeCaptureSessionObserver() {
        let notificationCenter = NSNotificationCenter.defaultCenter()
        
        notificationCenter.removeObserver(self, name: AVCaptureSessionDidStartRunningNotification, object: nil)
        notificationCenter.removeObserver(self, name: AVCaptureSessionDidStopRunningNotification, object: nil)
        notificationCenter.removeObserver(self, name: AVCaptureSessionRuntimeErrorNotification, object: nil)
        notificationCenter.removeObserver(self, name: AVCaptureSessionWasInterruptedNotification, object: nil)
    }
    
    func teardownCaptureSession() {
        removeCaptureSessionObserver()
        
        for input in inputDevices {
            captureSession.removeInput(input)
        }
        
        for output in outputDevices {
            captureSession.removeOutput(output)
        }
        
        previewLayer.removeFromSuperlayer()
        previewLayer.session = nil
    }
}

public extension CameraController {
    func captureSessionDidStartRunning(notification: NSNotification) {
        delegate?.cameraController(self, didStartCaptureSession: true)
    }
    
    func captureSessionDidStopRunning(notification: NSNotification) {
        delegate?.cameraController(self, didStartCaptureSession: false)
    }
    
    func captureSessionDidFailWithError(notification: NSNotification) {
        var captureSessionError: NSError = notification.userInfo![AVCaptureSessionErrorKey] as! NSError
        
        stopCaptureSession()
        
        delegate?.cameraController(self, didEncounterError: captureSessionError)
    }
    
    func captureSessionWasInterrupted(notification: NSNotification) {
        println("Capture session was interrupted:\n\(notification)")
    }
}

// MARK: - AVFoundation Utilities

private extension CameraController {
    var inputDevices: [AVCaptureDeviceInput] {
        return captureSession.inputs as! [AVCaptureDeviceInput]
    }
    
    var outputDevices: [AVCaptureOutput] {
        return captureSession.outputs as! [AVCaptureOutput]
    }
    
    var videoDevices: [AVCaptureDevice] {
        return AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo) as! [AVCaptureDevice]
    }
    
    var audioDevices: [AVCaptureDevice] {
        return AVCaptureDevice.devicesWithMediaType(AVMediaTypeAudio) as! [AVCaptureDevice]
    }
    
    var currentAudioDeviceInput: AVCaptureDeviceInput? {
        return currentDeviceForMediaType(AVMediaTypeAudio)
    }
    
    var currentVideoDeviceInput: AVCaptureDeviceInput? {
        return currentDeviceForMediaType(AVMediaTypeVideo)
    }
    
    var currentVideoDevice: AVCaptureDevice? {
        return videoDeviceInput?.device
    }
    
    var currentAudioDevice: AVCaptureDevice? {
        return audioDeviceInput?.device
    }
    
    var defaultAudioDevice: AVCaptureDevice {
        return AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
    }
    
    var defaultVideoDevice: AVCaptureDevice {
        return AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
    }
    
    func currentDeviceForMediaType(mediaType: String) -> AVCaptureDeviceInput? {
        for input: AnyObject in captureSession.inputs {
            if let deviceInput = input as? AVCaptureDeviceInput {
                if deviceInput.device.hasMediaType(mediaType) {
                    return deviceInput
                }
            }
        }
        
        return nil
    }
    
    func videoDeviceForPosition(position: AVCaptureDevicePosition) -> AVCaptureDevice? {
        for device in videoDevices {
            if device.position == position {
                return device
            }
        }
        
        return nil
    }
    
    func replaceCurrentVideoDeviceWithDevice(device: AVCaptureDevice) {
        let deviceInput = AVCaptureDeviceInput(device: device, error: nil)
        
        replaceCurrentVideoDeviceInputWithDeviceInput(deviceInput)
    }
    
    func replaceCurrentVideoDeviceInputWithDeviceInput(deviceInput: AVCaptureDeviceInput) {
        if let videoInput = videoDeviceInput {
            captureSession.removeInput(videoInput)
        }
        
        videoDeviceInput = deviceInput
        addInput(deviceInput)
        
        setupVideoDeviceOutput()
        setupVideoConnection()
    }
    
    func replaceCurrentAudioDeviceWithDevice(device: AVCaptureDevice) {
        let deviceInput = AVCaptureDeviceInput(device: device, error: nil)
        
        replaceCurrentAudioDeviceInputWithDeviceInput(deviceInput)
    }
    
    func replaceCurrentAudioDeviceInputWithDeviceInput(deviceInput: AVCaptureDeviceInput) {
        if let audioInput = audioDeviceInput {
            captureSession.removeInput(audioInput)
        }
        
        audioDeviceInput = deviceInput
        addInput(deviceInput)
        
        setupAudioDeviceOutput()
        setupAudioConnection()
    }
    
}
