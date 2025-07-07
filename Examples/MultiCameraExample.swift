//
//  MultiCameraExample.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import UIKit
import AVFoundation
import NextLevel

/// Example implementation of multi-camera recording with NextLevel V2
/// Demonstrates how to set up independent 4K video recording on one back camera
/// and HD image capture on another back camera simultaneously
class MultiCameraExampleViewController: UIViewController {
    
    // MARK: - Properties
    
    private let nextLevel = NextLevel.shared
    private var previewViews: [String: UIView] = [:] // Using String keys for camera IDs
    private var recordButton: UIButton!
    private var capturePhotoButton: UIButton!
    private var switchConfigButton: UIButton!
    private var isRecording = false
    
    // Camera identifiers
    private let videoCameraId = "back_video_4k"
    private let photoCameraId = "back_photo_hd"
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupNextLevel()
        requestPermissions()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        nextLevel.start()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        nextLevel.stop()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // Create preview containers
        let videoPreview = UIView()
        videoPreview.backgroundColor = .darkGray
        videoPreview.layer.cornerRadius = 8
        view.addSubview(videoPreview)
        previewViews[videoCameraId] = videoPreview
        
        let photoPreview = UIView()
        photoPreview.backgroundColor = .darkGray
        photoPreview.layer.cornerRadius = 8
        view.addSubview(photoPreview)
        previewViews[photoCameraId] = photoPreview
        
        // Layout previews
        videoPreview.translatesAutoresizingMaskIntoConstraints = false
        photoPreview.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Main preview (4K video camera)
            videoPreview.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            videoPreview.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            videoPreview.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            videoPreview.heightAnchor.constraint(equalTo: videoPreview.widthAnchor, multiplier: 16.0/9.0),
            
            // Secondary preview (HD photo camera)
            photoPreview.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            photoPreview.topAnchor.constraint(equalTo: videoPreview.bottomAnchor, constant: 16),
            photoPreview.widthAnchor.constraint(equalToConstant: 120),
            photoPreview.heightAnchor.constraint(equalTo: photoPreview.widthAnchor, multiplier: 16.0/9.0)
        ])
        
        // Add labels
        addLabel(to: videoPreview, text: "4K Video")
        addLabel(to: photoPreview, text: "HD Photo")
        
        // Create control buttons
        recordButton = createButton(title: "Record 4K", action: #selector(toggleRecording))
        capturePhotoButton = createButton(title: "Capture HD Photo", action: #selector(capturePhoto))
        switchConfigButton = createButton(title: "Switch Config", action: #selector(switchConfiguration))
        
        let stackView = UIStackView(arrangedSubviews: [recordButton, capturePhotoButton])
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 16
        view.addSubview(stackView)
        
        view.addSubview(switchConfigButton)
        
        stackView.translatesAutoresizingMaskIntoConstraints = false
        switchConfigButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -92),
            stackView.heightAnchor.constraint(equalToConstant: 50),
            
            switchConfigButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            switchConfigButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            switchConfigButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            switchConfigButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    private func addLabel(to view: UIView, text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        label.textAlignment = .center
        view.addSubview(label)
        
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            label.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    private func createButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
    
    private func setupNextLevel() {
        // Set delegates
        nextLevel.delegate = self
        nextLevel.multiCameraV2Delegate = self
        
        // Configure multi-camera using your specific requirements
        setupUserRequiredConfiguration()
    }
    
    private func setupUserRequiredConfiguration() {
        do {
            // Create configuration matching user requirements:
            // - 4K video recording on one back camera (wide angle)
            // - HD image capture on another back camera (ultra-wide or telephoto)
            
            let configuration = NextLevelMultiCameraConfigurationV2()
            
            // Configure 4K video camera (back wide angle)
            var videoCameraConfig = NextLevelCameraConfiguration(
                cameraPosition: .back,
                lensType: .wideAngleCamera,
                captureMode: .video
            )
            
            // Video configuration for 4K
            let videoConfig = NextLevelVideoConfiguration()
            videoConfig.preset = .hd4K3840x2160
            videoConfig.bitRate = 50_000_000 // 50 Mbps for 4K
            videoCameraConfig.videoConfiguration = videoConfig
            
            // Apply your app's settings individually
            videoCameraConfig.preferredFrameRate = 30 // fps
            videoCameraConfig.videoStabilizationMode = .cinematic // video stabilization mode
            videoCameraConfig.exposureMode = .continuousAutoExposure // exposure
            videoCameraConfig.focusMode = .continuousAutoFocus
            videoCameraConfig.zoomFactor = 1.0 // zoom
            videoCameraConfig.orientation = .portrait // orientation
            videoCameraConfig.isHDREnabled = true // HDR for better 4K quality
            
            // Add to configuration with high priority
            configuration.setCamera(videoCameraConfig, priority: .high)
            
            // Configure HD photo camera (back ultra-wide or telephoto)
            var photoCameraConfig = NextLevelCameraConfiguration(
                cameraPosition: .back,
                lensType: .ultraWideAngleCamera, // Using ultra-wide for HD photos
                captureMode: .photo
            )
            
            // Photo configuration for HD
            let photoConfig = NextLevelPhotoConfiguration()
            photoConfig.codec = .hevc
            photoConfig.isHighResolutionEnabled = true
            photoCameraConfig.photoConfiguration = photoConfig
            
            // Apply settings for photo camera
            photoCameraConfig.exposureMode = .continuousAutoExposure
            photoCameraConfig.focusMode = .continuousAutoFocus
            photoCameraConfig.zoomFactor = 1.0
            photoCameraConfig.orientation = .portrait
            photoCameraConfig.flashMode = .off
            
            // Add to configuration with medium priority
            configuration.setCamera(photoCameraConfig, priority: .medium)
            
            // Configure audio (optional, using the video camera's microphone)
            let audioConfig = NextLevelAudioConfiguration()
            audioConfig.bitRate = 128000 // audio bitrate
            configuration.audioConfiguration = audioConfig
            configuration.audioSource = .back // Use back camera's microphone
            
            // Enable multi-camera mode
            try nextLevel.enableMultiCameraV2(with: configuration)
            
            // Configure session
            nextLevel.automaticallyUpdatesDeviceOrientation = false
            nextLevel.resetSession { (error) in
                if let error = error {
                    print("Session reset error: \(error)")
                } else {
                    print("Multi-camera session configured successfully")
                    self.setupPreviewLayers()
                }
            }
            
        } catch {
            showAlert(title: "Setup Error", message: error.localizedDescription)
        }
    }
    
    private func setupPreviewLayers() {
        // Note: The current API doesn't provide per-camera preview layers
        // This would need to be implemented in the multi-camera session
        // For now, we'll use the main preview layer
        
        if let mainPreview = nextLevel.previewLayer {
            mainPreview.frame = previewViews[videoCameraId]?.bounds ?? .zero
            mainPreview.videoGravity = .resizeAspectFill
            previewViews[videoCameraId]?.layer.addSublayer(mainPreview)
        }
    }
    
    // MARK: - Permissions
    
    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if !granted {
                DispatchQueue.main.async {
                    self.showAlert(title: "Camera Access", message: "Please enable camera access in Settings")
                }
            }
        }
        
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                DispatchQueue.main.async {
                    self.showAlert(title: "Microphone Access", message: "Please enable microphone access in Settings")
                }
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        do {
            // Start 4K recording on the wide angle camera
            try nextLevel.startRecordingV2(at: .back)
            
            isRecording = true
            recordButton.setTitle("Stop Recording", for: .normal)
            recordButton.backgroundColor = .systemRed
            
        } catch {
            showAlert(title: "Recording Error", message: error.localizedDescription)
        }
    }
    
    private func stopRecording() {
        // Stop recording on the wide angle camera
        nextLevel.stopRecordingV2(at: .back)
        
        isRecording = false
        recordButton.setTitle("Record 4K", for: .normal)
        recordButton.backgroundColor = .systemBlue
    }
    
    @objc private func capturePhoto() {
        // Capture HD photo on the ultra-wide camera while potentially recording 4K on wide
        capturePhotoButton.isEnabled = false
        
        nextLevel.capturePhotoV2(at: .back, flashMode: .off) { [weak self] (image, error) in
            DispatchQueue.main.async {
                self?.capturePhotoButton.isEnabled = true
                
                if let image = image {
                    self?.showPhotoPreview(image)
                } else if let error = error {
                    self?.showAlert(title: "Photo Error", message: error.localizedDescription)
                }
            }
        }
    }
    
    @objc private func switchConfiguration() {
        // Example of switching between different configurations
        let actionSheet = UIAlertController(title: "Select Configuration", message: nil, preferredStyle: .actionSheet)
        
        actionSheet.addAction(UIAlertAction(title: "4K Video + HD Photo", style: .default) { _ in
            self.setupUserRequiredConfiguration()
        })
        
        actionSheet.addAction(UIAlertAction(title: "Dual HD Video", style: .default) { _ in
            self.setupDualVideoConfiguration()
        })
        
        actionSheet.addAction(UIAlertAction(title: "High FPS Action", style: .default) { _ in
            self.setupActionCameraConfiguration()
        })
        
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = switchConfigButton
            popover.sourceRect = switchConfigButton.bounds
        }
        
        present(actionSheet, animated: true)
    }
    
    private func setupDualVideoConfiguration() {
        do {
            let configuration = NextLevelMultiCameraConfigurationV2()
            
            // Back camera - HD video
            var backCameraConfig = NextLevelCameraConfiguration(
                cameraPosition: .back,
                lensType: .wideAngleCamera,
                captureMode: .video
            )
            let backVideoConfig = NextLevelVideoConfiguration()
            backVideoConfig.preset = .hd1920x1080
            backVideoConfig.bitRate = 10_000_000
            backCameraConfig.videoConfiguration = backVideoConfig
            backCameraConfig.preferredFrameRate = 30
            backCameraConfig.videoStabilizationMode = .standard
            configuration.setCamera(backCameraConfig, priority: .high)
            
            // Front camera - HD video
            var frontCameraConfig = NextLevelCameraConfiguration(
                cameraPosition: .front,
                lensType: .wideAngleCamera,
                captureMode: .video
            )
            let frontVideoConfig = NextLevelVideoConfiguration()
            frontVideoConfig.preset = .hd1280x720
            frontVideoConfig.bitRate = 5_000_000
            frontCameraConfig.videoConfiguration = frontVideoConfig
            frontCameraConfig.preferredFrameRate = 30
            configuration.setCamera(frontCameraConfig, priority: .medium)
            
            try nextLevel.enableMultiCameraV2(with: configuration)
            setupPreviewLayers()
            
        } catch {
            showAlert(title: "Configuration Error", message: error.localizedDescription)
        }
    }
    
    private func setupActionCameraConfiguration() {
        do {
            let configuration = NextLevelMultiCameraConfigurationV2()
            
            // High FPS configuration
            var cameraConfig = NextLevelCameraConfiguration(
                cameraPosition: .back,
                lensType: .wideAngleCamera,
                captureMode: .video
            )
            let videoConfig = NextLevelVideoConfiguration()
            videoConfig.preset = .hd1920x1080
            videoConfig.bitRate = 20_000_000
            cameraConfig.videoConfiguration = videoConfig
            cameraConfig.preferredFrameRate = 60 // High FPS
            cameraConfig.videoStabilizationMode = .standard
            configuration.setCamera(cameraConfig, priority: .high)
            
            try nextLevel.enableMultiCameraV2(with: configuration)
            setupPreviewLayers()
            
        } catch {
            showAlert(title: "Configuration Error", message: error.localizedDescription)
        }
    }
    
    // MARK: - Helpers
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showPhotoPreview(_ image: UIImage) {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        
        let previewVC = UIViewController()
        previewVC.view = imageView
        previewVC.modalPresentationStyle = .fullScreen
        
        // Add close button
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        closeButton.layer.cornerRadius = 8
        closeButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        closeButton.addTarget(self, action: #selector(dismissPhotoPreview), for: .touchUpInside)
        
        previewVC.view.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: previewVC.view.safeAreaLayoutGuide.topAnchor, constant: 20),
            closeButton.trailingAnchor.constraint(equalTo: previewVC.view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 80),
            closeButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        present(previewVC, animated: true)
    }
    
    @objc private func dismissPhotoPreview() {
        dismiss(animated: true)
    }
}

// MARK: - NextLevelDelegate

extension MultiCameraExampleViewController: NextLevelDelegate {
    func nextLevel(_ nextLevel: NextLevel, didUpdateVideoConfiguration configuration: NextLevelVideoConfiguration) {
        print("Video configuration updated")
    }
    
    func nextLevel(_ nextLevel: NextLevel, didUpdateAudioConfiguration configuration: NextLevelAudioConfiguration) {
        print("Audio configuration updated")
    }
    
    func nextLevelSessionWillStart(_ nextLevel: NextLevel) {
        print("Session will start")
    }
    
    func nextLevelSessionDidStart(_ nextLevel: NextLevel) {
        print("Session did start")
    }
    
    func nextLevelSessionDidStop(_ nextLevel: NextLevel) {
        print("Session did stop")
    }
}

// MARK: - NextLevelMultiCameraV2Delegate

extension MultiCameraExampleViewController: NextLevelMultiCameraV2Delegate {
    
    func nextLevel(_ nextLevel: NextLevel, didSetupCamera position: NextLevelDevicePosition, with configuration: NextLevelCameraConfiguration) {
        print("Camera setup at position \(position)")
        print("  - Lens type: \(configuration.lensType)")
        print("  - Capture mode: \(configuration.captureMode)")
        if let videoConfig = configuration.videoConfiguration {
            print("  - Video preset: \(videoConfig.preset)")
            print("  - Bitrate: \(videoConfig.bitRate)")
        }
    }
    
    func nextLevel(_ nextLevel: NextLevel, didStartVideoRecording position: NextLevelDevicePosition) {
        print("Started recording at position \(position)")
    }
    
    func nextLevel(_ nextLevel: NextLevel, didCompleteVideoRecording position: NextLevelDevicePosition, url: URL?) {
        print("Completed recording at position \(position)")
        if let url = url {
            print("Video saved to: \(url.lastPathComponent)")
            DispatchQueue.main.async {
                self.showAlert(title: "Recording Saved", message: "4K video saved successfully")
            }
        }
    }
    
    func nextLevel(_ nextLevel: NextLevel, didCapturePhoto photo: AVCapturePhoto, fromCamera position: NextLevelDevicePosition) {
        print("Captured photo from position \(position)")
    }
    
    func nextLevel(_ nextLevel: NextLevel, didUpdateVideoRecordingProgress progress: Float, duration: CMTime, forCamera position: NextLevelDevicePosition) {
        let seconds = CMTimeGetSeconds(duration)
        print("Recording progress at \(position): \(Int(seconds))s")
    }
    
    func nextLevel(_ nextLevel: NextLevel, camera position: NextLevelDevicePosition, didEncounterError error: Error) {
        print("Camera error at \(position): \(error)")
        DispatchQueue.main.async {
            self.showAlert(title: "Camera Error", message: error.localizedDescription)
        }
    }
}