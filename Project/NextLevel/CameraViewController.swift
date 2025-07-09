//
//  CameraViewController.swift
//  NextLevel (http://github.com/NextLevel)
//
//  Copyright (c) 2016-present patrick piemonte (http://patrickpiemonte.com)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import UIKit
import AVFoundation
import Photos
// import NextLevel

class CameraViewController: UIViewController {

    static let nextLevelAlbumTitle = "NextLevel"

    // MARK: - UIViewController

    override public var prefersStatusBarHidden: Bool {
        return true
    }

    // MARK: - properties

    internal var previewView: UIView?
    internal var gestureView: UIView?
    internal var focusView: FocusIndicatorView?
    internal var controlDockView: UIView?
    internal var metadataObjectViews: [UIView]?
    
    // Multi-camera preview layers
    internal var secondaryPreviewLayer: AVSampleBufferDisplayLayer?
    internal var primaryImageView: UIImageView?
    internal var secondaryImageView: UIImageView?
    internal var ciContext: CIContext?

    internal var recordButton: UIImageView?
    internal var flipButton: UIButton?
    internal var flashButton: UIButton?
    internal var saveButton: UIButton?

    internal var longPressGestureRecognizer: UILongPressGestureRecognizer?
    internal var photoTapGestureRecognizer: UITapGestureRecognizer?
    internal var focusTapGestureRecognizer: UITapGestureRecognizer?
    internal var flipDoubleTapGestureRecognizer: UITapGestureRecognizer?

    private var _panStartPoint: CGPoint = .zero
    private var _panStartZoom: CGFloat = 0.0

    // MARK: - object lifecycle

    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {

        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    deinit {
    }

    // MARK: - view lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = UIColor.black
        self.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let screenBounds = UIScreen.main.bounds

        // preview
        self.previewView = UIView(frame: screenBounds)
        if let previewView = self.previewView {
            previewView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            previewView.backgroundColor = UIColor.black
            self.view.addSubview(previewView)
            
            // Always use the standard preview layer for primary camera
            NextLevel.shared.previewLayer.frame = previewView.bounds
            previewView.layer.addSublayer(NextLevel.shared.previewLayer)
            
            // Create secondary camera preview if multi-camera is supported
            if NextLevel.shared.isMultiCameraSupported {
                // Create CIContext for image conversion
                self.ciContext = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
                
                // Create a secondary preview using UIImageView (will be updated via delegate)
                let secondaryFrame = CGRect(x: previewView.bounds.width * 0.5,
                                          y: 0,
                                          width: previewView.bounds.width * 0.5,
                                          height: previewView.bounds.height)
                self.secondaryImageView = UIImageView(frame: secondaryFrame)
                if let secondaryImageView = self.secondaryImageView {
                    secondaryImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight, .flexibleLeftMargin]
                    secondaryImageView.contentMode = .scaleAspectFill
                    secondaryImageView.clipsToBounds = true
                    secondaryImageView.backgroundColor = .black
                    previewView.addSubview(secondaryImageView)
                }
                
                // Resize primary preview to half width
                NextLevel.shared.previewLayer.frame = CGRect(x: 0,
                                                           y: 0,
                                                           width: previewView.bounds.width * 0.5,
                                                           height: previewView.bounds.height)
            }
        }

        self.focusView = FocusIndicatorView(frame: .zero)

        // buttons
        self.recordButton = UIImageView(image: UIImage(named: "record_button"))
        self.longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressGestureRecognizer(_:)))
        if let recordButton = self.recordButton,
            let longPressGestureRecognizer = self.longPressGestureRecognizer {
            recordButton.isUserInteractionEnabled = true
            recordButton.sizeToFit()

            longPressGestureRecognizer.delegate = self
            longPressGestureRecognizer.minimumPressDuration = 0.2
            longPressGestureRecognizer.allowableMovement = 10.0
            recordButton.addGestureRecognizer(longPressGestureRecognizer)
        }

        self.flipButton = UIButton(type: .custom)
        if let flipButton = self.flipButton {
            flipButton.setImage(UIImage(named: "flip_button"), for: .normal)
            flipButton.sizeToFit()
            flipButton.addTarget(self, action: #selector(handleFlipButton(_:)), for: .touchUpInside)
        }

        self.saveButton = UIButton(type: .custom)
        if let saveButton = self.saveButton {
            saveButton.setImage(UIImage(named: "save_button"), for: .normal)
            saveButton.sizeToFit()
            saveButton.addTarget(self, action: #selector(handleSaveButton(_:)), for: .touchUpInside)
        }

        // capture control "dock"
        let controlDockHeight = screenBounds.height * 0.2
        self.controlDockView = UIView(frame: CGRect(x: 0, y: screenBounds.height - controlDockHeight, width: screenBounds.width, height: controlDockHeight))
        if let controlDockView = self.controlDockView {
            controlDockView.backgroundColor = UIColor.clear
            controlDockView.autoresizingMask = [.flexibleTopMargin]
            self.view.addSubview(controlDockView)

            if let recordButton = self.recordButton {
                recordButton.center = CGPoint(x: controlDockView.bounds.midX, y: controlDockView.bounds.midY)
                controlDockView.addSubview(recordButton)
            }

            if let flipButton = self.flipButton, let recordButton = self.recordButton {
                flipButton.center = CGPoint(x: recordButton.center.x + controlDockView.bounds.width * 0.25 + flipButton.bounds.width * 0.5, y: recordButton.center.y)
                controlDockView.addSubview(flipButton)
            }

            if let saveButton = self.saveButton, let recordButton = self.recordButton {
                saveButton.center = CGPoint(x: controlDockView.bounds.width * 0.25 - saveButton.bounds.width * 0.5, y: recordButton.center.y)
                controlDockView.addSubview(saveButton)
            }
        }

        // gestures
        self.gestureView = UIView(frame: screenBounds)
        if let gestureView = self.gestureView, let controlDockView = self.controlDockView {
            gestureView.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
            gestureView.frame.size.height -= controlDockView.frame.height
            gestureView.backgroundColor = .clear
            self.view.addSubview(gestureView)

            self.focusTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleFocusTapGestureRecognizer(_:)))
            if let focusTapGestureRecognizer = self.focusTapGestureRecognizer {
                focusTapGestureRecognizer.delegate = self
                focusTapGestureRecognizer.numberOfTapsRequired = 1
                gestureView.addGestureRecognizer(focusTapGestureRecognizer)
            }
        }

        // Configure NextLevel by modifying the configuration ivars
        let nextLevel = NextLevel.shared
        nextLevel.delegate = self
        nextLevel.deviceDelegate = self
        nextLevel.flashDelegate = self
        nextLevel.videoDelegate = self
        nextLevel.photoDelegate = self
        nextLevel.metadataObjectsDelegate = self
        nextLevel.multiCameraDelegate = self

        // video configuration
        nextLevel.videoConfiguration.preset = AVCaptureSession.Preset.hd1280x720
        nextLevel.videoConfiguration.bitRate = 5500000
        nextLevel.videoConfiguration.maxKeyFrameInterval = 30
        nextLevel.videoConfiguration.profileLevel = AVVideoProfileLevelH264HighAutoLevel

        // audio configuration
        nextLevel.audioConfiguration.bitRate = 96000

        // metadata objects configuration
        nextLevel.metadataObjectTypes = [AVMetadataObject.ObjectType.face, AVMetadataObject.ObjectType.qr]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if NextLevel.authorizationStatus(forMediaType: AVMediaType.video) == .authorized &&
           NextLevel.authorizationStatus(forMediaType: AVMediaType.audio) == .authorized {
            
            let nextLevel = NextLevel.shared
            
            // Configure multi-camera if supported before starting
            if nextLevel.isMultiCameraSupported {
                nextLevel.captureMode = .multiCamera
                
                let config = nextLevel.multiCameraConfiguration
                // Use two back cameras - wide and ultra-wide
                config.primaryCameraPosition = .back       // Wide angle camera
                config.secondaryCameraPosition = .back     // Ultra-wide camera (NextLevel will handle this)
                config.enabledCameras = [.back]            // We need NextLevel to handle multiple back cameras
                config.outputMode = .separate
                config.recordingMode = .separate
                config.preferredFrameRate = 30
                config.optimizeForDevice()
                
                // Validate configuration
                let validation = config.validate()
                if !validation.isValid {
                    print("Multi-camera configuration errors: \(validation.errors)")
                }
            }
            
            do {
                try nextLevel.start()
                
                // For multi-camera mode, the single preview layer will show the primary camera
                // NextLevel's current implementation doesn't expose separate preview layers
                // The delegate callbacks will provide access to both camera feeds
                
                // Add a small delay to ensure everything is initialized
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("Multi-camera session should be ready now")
                    print("Capture mode after start: \(nextLevel.captureMode)")
                }
            } catch {
                print("NextLevel, failed to start camera session")
            }
        } else {
            NextLevel.requestAuthorization(forMediaType: AVMediaType.video) { (mediaType, status) in
                print("NextLevel, authorization updated for media \(mediaType) status \(status)")
                if NextLevel.authorizationStatus(forMediaType: AVMediaType.video) == .authorized &&
                    NextLevel.authorizationStatus(forMediaType: AVMediaType.audio) == .authorized {
                    
                    let nextLevel = NextLevel.shared
                    
                    // Configure multi-camera if supported before starting
                    if nextLevel.isMultiCameraSupported {
                        nextLevel.captureMode = .multiCamera
                        
                        let config = nextLevel.multiCameraConfiguration
                        // Use two back cameras - wide and ultra-wide
                        config.primaryCameraPosition = .back       // Wide angle camera
                        config.secondaryCameraPosition = .back     // Ultra-wide camera (NextLevel will handle this)
                        config.enabledCameras = [.back, .front]    // Enable multiple cameras (NextLevel will map to actual devices)
                        config.outputMode = .separate
                        config.recordingMode = .separate
                        config.preferredFrameRate = 30
                        config.previewLayout = .sideBySide(splitRatio: 0.5)
                        config.optimizeForDevice()
                    }
                    
                    do {
                        try nextLevel.start()
                    } catch {
                        print("NextLevel, failed to start camera session")
                    }
                } else if status == .notAuthorized {
                    // gracefully handle when audio/video is not authorized
                    print("NextLevel doesn't have authorization for audio or video")
                }
            }
            NextLevel.requestAuthorization(forMediaType: AVMediaType.audio) { (mediaType, status) in
                print("NextLevel, authorization updated for media \(mediaType) status \(status)")
                if NextLevel.authorizationStatus(forMediaType: AVMediaType.video) == .authorized &&
                    NextLevel.authorizationStatus(forMediaType: AVMediaType.audio) == .authorized {
                    
                    let nextLevel = NextLevel.shared
                    
                    // Configure multi-camera if supported before starting
                    if nextLevel.isMultiCameraSupported {
                        nextLevel.captureMode = .multiCamera
                        
                        let config = nextLevel.multiCameraConfiguration
                        // Use two back cameras - wide and ultra-wide
                        config.primaryCameraPosition = .back       // Wide angle camera
                        config.secondaryCameraPosition = .back     // Ultra-wide camera (NextLevel will handle this)
                        config.enabledCameras = [.back, .front]    // Enable multiple cameras (NextLevel will map to actual devices)
                        config.outputMode = .separate
                        config.recordingMode = .separate
                        config.preferredFrameRate = 30
                        config.previewLayout = .sideBySide(splitRatio: 0.5)
                        config.optimizeForDevice()
                    }
                    
                    do {
                        try nextLevel.start()
                    } catch {
                        print("NextLevel, failed to start camera session")
                    }
                } else if status == .notAuthorized {
                    // gracefully handle when audio/video is not authorized
                    print("NextLevel doesn't have authorization for audio or video")
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        NextLevel.shared.stop()
    }

}

// MARK: - library

extension CameraViewController {

    internal func albumAssetCollection(withTitle title: String) -> PHAssetCollection? {
        let predicate = NSPredicate(format: "localizedTitle = %@", title)
        let options = PHFetchOptions()
        options.predicate = predicate
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
        if result.count > 0 {
            return result.firstObject
        }
        return nil
    }

}

// MARK: - capture

extension CameraViewController {

    internal func startCapture() {
        // Prevent multiple starts
        guard !NextLevel.shared.isRecording else {
            print("Recording already in progress, ignoring start request")
            return
        }
        
        self.photoTapGestureRecognizer?.isEnabled = false
        UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseInOut, animations: {
            self.recordButton?.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        }) { (_: Bool) in
        }
        
        // Use multi-camera recording
        if NextLevel.shared.captureMode == .multiCamera {
            do {
                try NextLevel.shared.startMultiCameraRecording()
                print("Multi-camera recording started successfully")
                
                // Capture a photo from the secondary camera after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NextLevel.shared.capturePhotoFromSecondaryCamera()
                }
            } catch {
                print("Failed to start multi-camera recording: \(error)")
                print("Error details: \(error.localizedDescription)")
            }
        } else {
            NextLevel.shared.record()
        }
    }

    internal func pauseCapture() {
        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseOut, animations: {
            self.recordButton?.transform = .identity
        }) { (_: Bool) in
            if NextLevel.shared.captureMode == .multiCamera {
                NextLevel.shared.pauseMultiCameraRecording()
            } else {
                NextLevel.shared.pause()
            }
        }
    }

    internal func endCapture() {
        // Prevent multiple calls
        guard NextLevel.shared.isRecording else {
            print("Not recording, ignoring end capture request")
            return
        }
        
        self.photoTapGestureRecognizer?.isEnabled = true
        
        // Handle multi-camera recording end
        if NextLevel.shared.captureMode == .multiCamera {
            NextLevel.shared.stopMultiCameraRecording { (urls, error) in
                if let urls = urls, !urls.isEmpty {
                    print("Received \(urls.count) video files from multi-camera recording")
                    self.saveMultipleVideos(withURLs: urls)
                } else if let error = error {
                    print("Error stopping multi-camera recording: \(error)")
                }
            }
        } else if let session = NextLevel.shared.session {
            // Handle standard recording end
                if session.clips.count > 1 {
                    session.mergeClips(usingPreset: AVAssetExportPresetHighestQuality, completionHandler: { (url: URL?, error: Error?) in
                        if let url = url {
                            self.saveVideo(withURL: url)
                        } else if let _ = error {
                            print("failed to merge clips at the end of capture \(String(describing: error))")
                        }
                    })
                } else if let lastClipUrl = session.lastClipUrl {
                    self.saveVideo(withURL: lastClipUrl)
                } else if session.currentClipHasStarted {
                    session.endClip(completionHandler: { (clip, error) in
                        if error == nil, let url = clip?.url {
                            self.saveVideo(withURL: url)
                        } else {
                            print("Error saving video: \(error?.localizedDescription ?? "")")
                        }
                    })
                } else {
                    // prompt that the video has been saved
                    let alertController = UIAlertController(title: "Video Capture", message: "Not enough video captured!", preferredStyle: .alert)
                    let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                    alertController.addAction(okAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }

    internal func authorizePhotoLibaryIfNecessary() {
        let authorizationStatus = PHPhotoLibrary.authorizationStatus()
        switch authorizationStatus {
        case .restricted:
            fallthrough
        case .denied:
            let alertController = UIAlertController(title: "Oh no!", message: "Access denied.", preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
            alertController.addAction(okAction)
            self.present(alertController, animated: true, completion: nil)
            break
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization({ (status) in
                if status == .authorized {

                } else {

                }
            })
            break
        case .authorized:
            break
        case .limited:
            break
        @unknown default:
            fatalError("unknown authorization type")
        }
    }

}

// MARK: - media utilities

extension CameraViewController {

    internal func saveMultipleVideos(withURLs urls: [URL]) {
        guard !urls.isEmpty else { return }
        
        var savedCount = 0
        var processedCount = 0
        let totalCount = urls.count
        
        let dispatchGroup = DispatchGroup()
        
        for url in urls {
            dispatchGroup.enter()
            
            PHPhotoLibrary.shared().performChanges({
                let albumAssetCollection = self.albumAssetCollection(withTitle: CameraViewController.nextLevelAlbumTitle)
                if albumAssetCollection == nil {
                    let changeRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: CameraViewController.nextLevelAlbumTitle)
                    _ = changeRequest.placeholderForCreatedAssetCollection
                }}, completionHandler: { (_: Bool, _: Error?) in
                    if let albumAssetCollection = self.albumAssetCollection(withTitle: CameraViewController.nextLevelAlbumTitle) {
                        PHPhotoLibrary.shared().performChanges({
                            if let assetChangeRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) {
                                let assetCollectionChangeRequest = PHAssetCollectionChangeRequest(for: albumAssetCollection)
                                let enumeration: NSArray = [assetChangeRequest.placeholderForCreatedAsset!]
                                assetCollectionChangeRequest?.addAssets(enumeration)
                            }
                        }, completionHandler: { (success2: Bool, _: Error?) in
                            if success2 {
                                savedCount += 1
                            }
                            processedCount += 1
                            dispatchGroup.leave()
                        })
                    } else {
                        processedCount += 1
                        dispatchGroup.leave()
                    }
                })
        }
        
        // Wait for all saves to complete, then show one alert
        dispatchGroup.notify(queue: .main) { [weak self] in
            // Only show alert if not already presenting
            guard self?.presentedViewController == nil else { return }
            
            if savedCount == totalCount {
                // prompt that the video has been saved
                DispatchQueue.main.async {
                    let alertController = UIAlertController(title: "Recording Saved!", message: "Video saved to the camera roll.", preferredStyle: .alert)
                    let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                    alertController.addAction(okAction)
                    self?.present(alertController, animated: true, completion: nil)
                }
            } else if savedCount > 0 {
                // prompt that some videos have been saved
                DispatchQueue.main.async {
                    let alertController = UIAlertController(title: "Partial Success", message: "Saved \(savedCount) of \(totalCount) videos.", preferredStyle: .alert)
                    let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                    alertController.addAction(okAction)
                    self?.present(alertController, animated: true, completion: nil)
                }
            } else {
                // prompt that the save failed
                DispatchQueue.main.async {
                    let alertController = UIAlertController(title: "Oops!", message: "Failed to save videos!", preferredStyle: .alert)
                    let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                    alertController.addAction(okAction)
                    self?.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    internal func saveVideo(withURL url: URL) {
        PHPhotoLibrary.shared().performChanges({
            let albumAssetCollection = self.albumAssetCollection(withTitle: CameraViewController.nextLevelAlbumTitle)
            if albumAssetCollection == nil {
                let changeRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: CameraViewController.nextLevelAlbumTitle)
                _ = changeRequest.placeholderForCreatedAssetCollection
            }}, completionHandler: { (_: Bool, _: Error?) in
                if let albumAssetCollection = self.albumAssetCollection(withTitle: CameraViewController.nextLevelAlbumTitle) {
                    PHPhotoLibrary.shared().performChanges({
                        if let assetChangeRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) {
                            let assetCollectionChangeRequest = PHAssetCollectionChangeRequest(for: albumAssetCollection)
                            let enumeration: NSArray = [assetChangeRequest.placeholderForCreatedAsset!]
                            assetCollectionChangeRequest?.addAssets(enumeration)
                        }
                    }, completionHandler: { (success2: Bool, _: Error?) in
                        DispatchQueue.main.async { [weak self] in
                            if success2 == true {
                                // prompt that the video has been saved
                                DispatchQueue.main.async {
                                    let alertController = UIAlertController(title: "Video Saved!", message: "Saved to the camera roll.", preferredStyle: .alert)
                                    let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                                    alertController.addAction(okAction)
                                    self?.present(alertController, animated: true, completion: nil)
                                }
                            } else {
                                // prompt that the video has been saved
                                DispatchQueue.main.async {
                                    let alertController = UIAlertController(title: "Oops!", message: "Something failed!", preferredStyle: .alert)
                                    let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                                    alertController.addAction(okAction)
                                    self?.present(alertController, animated: true, completion: nil)
                                }
                            }
                        }
                })
            }
        })
    }

    internal func savePhoto(photoImage: UIImage) {

        PHPhotoLibrary.shared().performChanges({

            let albumAssetCollection = self.albumAssetCollection(withTitle: CameraViewController.nextLevelAlbumTitle)
            if albumAssetCollection == nil {
                let changeRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: CameraViewController.nextLevelAlbumTitle)
                _ = changeRequest.placeholderForCreatedAssetCollection
            }

        }, completionHandler: { (success1: Bool, error1: Error?) in

            if success1 == true {
                if let albumAssetCollection = self.albumAssetCollection(withTitle: CameraViewController.nextLevelAlbumTitle) {
                    PHPhotoLibrary.shared().performChanges({
                        let assetChangeRequest = PHAssetChangeRequest.creationRequestForAsset(from: photoImage)
                        let assetCollectionChangeRequest = PHAssetCollectionChangeRequest(for: albumAssetCollection)
                        let enumeration: NSArray = [assetChangeRequest.placeholderForCreatedAsset!]
                        assetCollectionChangeRequest?.addAssets(enumeration)
                    }, completionHandler: { (success2: Bool, _: Error?) in
                        if success2 == true {
                            DispatchQueue.main.async {
                                let alertController = UIAlertController(title: "Photo Saved!", message: "Saved to the camera roll.", preferredStyle: .alert)
                                let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                                alertController.addAction(okAction)
                                self.present(alertController, animated: true, completion: nil)
                            }
                        }
                    })
                }
            } else if let _ = error1 {
                print("failure capturing photo from video frame \(String(describing: error1))")
            }

        })
    }

}

// MARK: - UIButton

extension CameraViewController {

    @objc internal func handleFlipButton(_ button: UIButton) {
        NextLevel.shared.flipCaptureDevicePosition()
    }

    internal func handleFlashModeButton(_ button: UIButton) {
    }

    @objc internal func handleSaveButton(_ button: UIButton) {
        self.endCapture()
    }

}

// MARK: - UIGestureRecognizerDelegate

extension CameraViewController: UIGestureRecognizerDelegate {

    @objc internal func handleLongPressGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began:
            self.startCapture()
            self._panStartPoint = gestureRecognizer.location(in: self.view)
            self._panStartZoom = CGFloat(NextLevel.shared.videoZoomFactor)
            break
        case .changed:
            let newPoint = gestureRecognizer.location(in: self.view)
            let scale = (self._panStartPoint.y / newPoint.y)
            let newZoom = (scale * self._panStartZoom)
            NextLevel.shared.videoZoomFactor = Float(newZoom)
            break
        case .ended:
            fallthrough
        case .cancelled:
            fallthrough
        case .failed:
            // For multi-camera mode, end the capture instead of pausing
            if NextLevel.shared.captureMode == .multiCamera {
                self.endCapture()
            } else {
                self.pauseCapture()
            }
            fallthrough
        default:
            break
        }
    }
}

extension CameraViewController {

    internal func handlePhotoTapGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
        // play system camera shutter sound
        AudioServicesPlaySystemSoundWithCompletion(SystemSoundID(1108), nil)
        NextLevel.shared.capturePhotoFromVideo()
    }

    @objc internal func handleFocusTapGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
        let tapPoint = gestureRecognizer.location(in: self.previewView)

        if let focusView = self.focusView {
            var focusFrame = focusView.frame
            focusFrame.origin.x = CGFloat((tapPoint.x - (focusFrame.size.width * 0.5)).rounded())
            focusFrame.origin.y = CGFloat((tapPoint.y - (focusFrame.size.height * 0.5)).rounded())
            focusView.frame = focusFrame

            self.previewView?.addSubview(focusView)
            focusView.startAnimation()
        }

        // Focus handling - NextLevel will handle multi-camera focus internally
        let adjustedPoint = NextLevel.shared.previewLayer.captureDevicePointConverted(fromLayerPoint: tapPoint)
        NextLevel.shared.focusExposeAndAdjustWhiteBalance(atAdjustedPoint: adjustedPoint)
    }

}

// MARK: - NextLevelDelegate

extension CameraViewController: NextLevelDelegate {

    // permission
    func nextLevel(_ nextLevel: NextLevel, didUpdateAuthorizationStatus status: NextLevelAuthorizationStatus, forMediaType mediaType: AVMediaType) {
    }

    // configuration
    func nextLevel(_ nextLevel: NextLevel, didUpdateVideoConfiguration videoConfiguration: NextLevelVideoConfiguration) {
    }

    func nextLevel(_ nextLevel: NextLevel, didUpdateAudioConfiguration audioConfiguration: NextLevelAudioConfiguration) {
    }

    // session
    func nextLevelSessionWillStart(_ nextLevel: NextLevel) {
        print("nextLevelSessionWillStart")
    }

    func nextLevelSessionDidStart(_ nextLevel: NextLevel) {
        print("nextLevelSessionDidStart")
    }

    func nextLevelSessionDidStop(_ nextLevel: NextLevel) {
        print("nextLevelSessionDidStop")
    }

    // interruption
    func nextLevelSessionWasInterrupted(_ nextLevel: NextLevel) {
    }

    func nextLevelSessionInterruptionEnded(_ nextLevel: NextLevel) {
    }

    // mode
    func nextLevelCaptureModeWillChange(_ nextLevel: NextLevel) {
    }

    func nextLevelCaptureModeDidChange(_ nextLevel: NextLevel) {
    }

}

extension CameraViewController: NextLevelPreviewDelegate {

    // preview
    func nextLevelWillStartPreview(_ nextLevel: NextLevel) {
    }

    func nextLevelDidStopPreview(_ nextLevel: NextLevel) {
    }

}

extension CameraViewController: NextLevelDeviceDelegate {

    // position, orientation
    func nextLevelDevicePositionWillChange(_ nextLevel: NextLevel) {
    }

    func nextLevelDevicePositionDidChange(_ nextLevel: NextLevel) {
    }

    func nextLevel(_ nextLevel: NextLevel, didChangeDeviceOrientation deviceOrientation: NextLevelDeviceOrientation) {
    }

    // format
    func nextLevel(_ nextLevel: NextLevel, didChangeDeviceFormat deviceFormat: AVCaptureDevice.Format) {
    }

    // aperture
    func nextLevel(_ nextLevel: NextLevel, didChangeCleanAperture cleanAperture: CGRect) {
    }

    // lens
    func nextLevel(_ nextLevel: NextLevel, didChangeLensPosition lensPosition: Float) {
    }

    // focus, exposure, white balance
    func nextLevelWillStartFocus(_ nextLevel: NextLevel) {
    }

    func nextLevelDidStopFocus(_  nextLevel: NextLevel) {
        if let focusView = self.focusView {
            if focusView.superview != nil {
                focusView.stopAnimation()
            }
        }
    }

    func nextLevelWillChangeExposure(_ nextLevel: NextLevel) {
    }

    func nextLevelDidChangeExposure(_ nextLevel: NextLevel) {
        if let focusView = self.focusView {
            if focusView.superview != nil {
                focusView.stopAnimation()
            }
        }
    }

    func nextLevelWillChangeWhiteBalance(_ nextLevel: NextLevel) {
    }

    func nextLevelDidChangeWhiteBalance(_ nextLevel: NextLevel) {
    }

}

// MARK: - NextLevelFlashDelegate

extension CameraViewController: NextLevelFlashAndTorchDelegate {

    func nextLevelDidChangeFlashMode(_ nextLevel: NextLevel) {
    }

    func nextLevelDidChangeTorchMode(_ nextLevel: NextLevel) {
    }

    func nextLevelFlashActiveChanged(_ nextLevel: NextLevel) {
    }

    func nextLevelTorchActiveChanged(_ nextLevel: NextLevel) {
    }

    func nextLevelFlashAndTorchAvailabilityChanged(_ nextLevel: NextLevel) {
    }

}

// MARK: - NextLevelVideoDelegate

extension CameraViewController: NextLevelVideoDelegate {

    // video zoom
    func nextLevel(_ nextLevel: NextLevel, didUpdateVideoZoomFactor videoZoomFactor: Float) {
    }

    // video frame processing
    func nextLevel(_ nextLevel: NextLevel, willProcessRawVideoSampleBuffer sampleBuffer: CMSampleBuffer, onQueue queue: DispatchQueue) {
    }

    func nextLevel(_ nextLevel: NextLevel, willProcessFrame frame: AnyObject, timestamp: TimeInterval, onQueue queue: DispatchQueue) {
    }

    // enabled by isCustomContextVideoRenderingEnabled
    func nextLevel(_ nextLevel: NextLevel, renderToCustomContextWithImageBuffer imageBuffer: CVPixelBuffer, onQueue queue: DispatchQueue) {
    }

    // video recording session
    func nextLevel(_ nextLevel: NextLevel, didSetupVideoInSession session: NextLevelSession) {
    }

    func nextLevel(_ nextLevel: NextLevel, didSetupAudioInSession session: NextLevelSession) {
    }

    func nextLevel(_ nextLevel: NextLevel, didStartClipInSession session: NextLevelSession) {
    }

    func nextLevel(_ nextLevel: NextLevel, didCompleteClip clip: NextLevelClip, inSession session: NextLevelSession) {
    }

    func nextLevel(_ nextLevel: NextLevel, didAppendVideoSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: NextLevelSession) {
    }

    func nextLevel(_ nextLevel: NextLevel, didAppendAudioSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: NextLevelSession) {
    }

    func nextLevel(_ nextLevel: NextLevel, didAppendVideoPixelBuffer pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, inSession session: NextLevelSession) {
    }

    func nextLevel(_ nextLevel: NextLevel, didSkipVideoPixelBuffer pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, inSession session: NextLevelSession) {
    }

    func nextLevel(_ nextLevel: NextLevel, didSkipVideoSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: NextLevelSession) {
    }

    func nextLevel(_ nextLevel: NextLevel, didSkipAudioSampleBuffer sampleBuffer: CMSampleBuffer, inSession session: NextLevelSession) {
    }

    func nextLevel(_ nextLevel: NextLevel, didCompleteSession session: NextLevelSession) {
        // called when a configuration time limit is specified
        self.endCapture()
    }

    // video frame photo

    func nextLevel(_ nextLevel: NextLevel, didCompletePhotoCaptureFromVideoFrame photoDict: [String: Any]?) {
        if let dictionary = photoDict,
            let photoData = dictionary[NextLevelPhotoJPEGKey] as? Data,
            let photoImage = UIImage(data: photoData) {
            self.savePhoto(photoImage: photoImage)
        }
    }

}

// MARK: - NextLevelPhotoDelegate

extension CameraViewController: NextLevelPhotoDelegate {
    func nextLevel(_ nextLevel: NextLevel, output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, photoConfiguration: NextLevelPhotoConfiguration) {
    }

    func nextLevel(_ nextLevel: NextLevel, output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings, photoConfiguration: NextLevelPhotoConfiguration) {
    }

    func nextLevel(_ nextLevel: NextLevel, output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings, photoConfiguration: NextLevelPhotoConfiguration) {
    }

    func nextLevel(_ nextLevel: NextLevel, didFinishProcessingPhoto photo: AVCapturePhoto, photoDict: [String: Any], photoConfiguration: NextLevelPhotoConfiguration) {

            PHPhotoLibrary.shared().performChanges({

                let albumAssetCollection = self.albumAssetCollection(withTitle: CameraViewController.nextLevelAlbumTitle)
                if albumAssetCollection == nil {
                    let changeRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: CameraViewController.nextLevelAlbumTitle)
                    _ = changeRequest.placeholderForCreatedAssetCollection
                }

            }, completionHandler: { (success1: Bool, error1: Error?) in

                if success1 == true {
                    if let albumAssetCollection = self.albumAssetCollection(withTitle: CameraViewController.nextLevelAlbumTitle) {
                        PHPhotoLibrary.shared().performChanges({
                            if let data = photoDict[NextLevelPhotoFileDataKey] as? Data,
                               let photoImage = UIImage(data: data) {
                                let assetChangeRequest = PHAssetChangeRequest.creationRequestForAsset(from: photoImage)
                                let assetCollectionChangeRequest = PHAssetCollectionChangeRequest(for: albumAssetCollection)
                                let enumeration: NSArray = [assetChangeRequest.placeholderForCreatedAsset!]
                                assetCollectionChangeRequest?.addAssets(enumeration)
                            }
                        }, completionHandler: { (success2: Bool, _: Error?) in
                            if success2 == true {
                                DispatchQueue.main.async {
                                    // Don't show photo alert to avoid conflicts with video alert
                                    print("Photo saved successfully")
                                }
                            }
                        })
                    }
                } else if let _ = error1 {
                    print("failure capturing photo from video frame \(String(describing: error1))")
                }

            })
    }

    func nextLevelDidCompletePhotoCapture(_ nextLevel: NextLevel) {
        // Save the captured photo from secondary camera
        if let photo = nextLevel.capturedSecondaryPhoto {
            self.savePhoto(photoImage: photo)
            // Clear the photo after saving
            nextLevel.clearCapturedSecondaryPhoto()
        }
    }

    func nextLevel(_ nextLevel: NextLevel, didFinishProcessingPhoto photo: AVCapturePhoto) {
    }

}

// MARK: - KVO

private var CameraViewControllerNextLevelCurrentDeviceObserverContext = "CameraViewControllerNextLevelCurrentDeviceObserverContext"

extension CameraViewController {

    internal func addKeyValueObservers() {
        self.addObserver(self, forKeyPath: "currentDevice", options: [.new], context: &CameraViewControllerNextLevelCurrentDeviceObserverContext)
    }

    internal func removeKeyValueObservers() {
        self.removeObserver(self, forKeyPath: "currentDevice")
    }

    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if context == &CameraViewControllerNextLevelCurrentDeviceObserverContext {
            // self.captureDeviceDidChange()
        }
    }

}

extension CameraViewController: NextLevelMetadataOutputObjectsDelegate {

    func metadataOutputObjects(_ nextLevel: NextLevel, didOutput metadataObjects: [AVMetadataObject]) {
        guard let previewView = self.previewView else {
            return
        }

        if let metadataObjectViews = metadataObjectViews {
            for view in metadataObjectViews {
                view.removeFromSuperview()
            }
            self.metadataObjectViews = nil
        }

        self.metadataObjectViews = metadataObjects.map { metadataObject in
            let view = UIView(frame: metadataObject.bounds)
            view.backgroundColor = UIColor.clear
            view.layer.borderColor = UIColor.yellow.cgColor
            view.layer.borderWidth = 1
            return view
        }

        if let metadataObjectViews = self.metadataObjectViews {
            for view in metadataObjectViews {
                previewView.addSubview(view)
            }
        }
    }
}

// MARK: - NextLevelMultiCameraDelegate

extension CameraViewController: NextLevelMultiCameraDelegate {
    
    func nextLevel(_ nextLevel: NextLevel, 
                   didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                   from position: NextLevelDevicePosition) {
        // Handle raw sample buffers from each camera if needed
    }
    
    func nextLevel(_ nextLevel: NextLevel,
                   didOutputPixelBuffer pixelBuffer: CVPixelBuffer,
                   from position: NextLevelDevicePosition,
                   timestamp: TimeInterval) {
        // Display secondary camera feed in the image view
        // When using two back cameras, NextLevel temporarily marks the secondary as .front
        guard position == .front,
              let secondaryImageView = self.secondaryImageView,
              let context = self.ciContext else {
            return
        }
        
        // Perform image conversion on background queue to avoid blocking
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Create CIImage from pixel buffer
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            
            // Don't rotate for back cameras - they should have the same orientation
            let rotatedImage = ciImage
            
            // Convert to CGImage
            guard let cgImage = context.createCGImage(rotatedImage, from: rotatedImage.extent) else {
                return
            }
            
            // Update UI on main thread
            let uiImage = UIImage(cgImage: cgImage)
            DispatchQueue.main.async {
                secondaryImageView.image = uiImage
            }
        }
    }
    
    func nextLevel(_ nextLevel: NextLevel,
                   didStartMultiCameraSession positions: Set<NextLevelDevicePosition>) {
        print("Multi-camera session started with cameras: \(positions)")
    }
    
    func nextLevel(_ nextLevel: NextLevel,
                   didStopMultiCameraSession positions: Set<NextLevelDevicePosition>) {
        print("Multi-camera session stopped")
    }
    
    func nextLevel(_ nextLevel: NextLevel,
                   multiCameraSessionInterrupted positions: Set<NextLevelDevicePosition>) {
        print("Multi-camera session interrupted for cameras: \(positions)")
    }
    
    func nextLevel(_ nextLevel: NextLevel,
                   multiCameraSessionInterruptionEnded positions: Set<NextLevelDevicePosition>) {
        print("Multi-camera session interruption ended for cameras: \(positions)")
    }
}
