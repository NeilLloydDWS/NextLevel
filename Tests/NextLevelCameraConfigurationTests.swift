//
//  NextLevelCameraConfigurationTests.swift
//  NextLevelTests
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import XCTest
import AVFoundation
@testable import NextLevel

class NextLevelCameraConfigurationTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testBasicInitialization() {
        let config = NextLevelCameraConfiguration(
            cameraPosition: .back,
            lensType: .wideAngleCamera,
            captureMode: .video
        )
        
        XCTAssertEqual(config.cameraPosition, .back)
        XCTAssertEqual(config.lensType, .wideAngleCamera)
        XCTAssertEqual(config.captureMode, .video)
        XCTAssertEqual(config.zoomFactor, 1.0)
        XCTAssertEqual(config.preferredFrameRate, 30)
        XCTAssertFalse(config.isHDREnabled)
        XCTAssertFalse(config.isLowLightBoostEnabled)
    }
    
    func testConvenienceInitializers() {
        // Test 4K video configuration
        let video4K = NextLevelCameraConfiguration.video4K(
            position: .back,
            lensType: .wideAngleCamera
        )
        
        XCTAssertNotNil(video4K.videoConfiguration)
        XCTAssertEqual(video4K.videoConfiguration?.preset, .hd4K3840x2160)
        XCTAssertEqual(video4K.videoConfiguration?.bitRate, 50_000_000)
        XCTAssertEqual(video4K.preferredFrameRate, 30)
        
        // Test HD photo configuration
        let photoHD = NextLevelCameraConfiguration.photoHD(
            position: .front,
            lensType: .wideAngleCamera
        )
        
        XCTAssertNotNil(photoHD.photoConfiguration)
        XCTAssertEqual(photoHD.photoConfiguration?.preset, .photo)
        XCTAssertEqual(photoHD.photoConfiguration?.codec, .jpeg)
    }
    
    // MARK: - Validation Tests
    
    func testVideoModeValidation() {
        var config = NextLevelCameraConfiguration(
            cameraPosition: .back,
            lensType: .wideAngleCamera,
            captureMode: .video
        )
        
        // Should fail without video configuration
        var validation = config.validate()
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.errors.contains("Video configuration is required for video capture mode"))
        
        // Should pass with video configuration
        config.videoConfiguration = NextLevelVideoConfiguration()
        validation = config.validate()
        XCTAssertTrue(validation.isValid)
        XCTAssertTrue(validation.errors.isEmpty)
    }
    
    func testPhotoModeValidation() {
        var config = NextLevelCameraConfiguration(
            cameraPosition: .back,
            lensType: .ultraWideAngleCamera,
            captureMode: .photo
        )
        
        // Should fail without photo configuration
        var validation = config.validate()
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.errors.contains("Photo configuration is required for photo capture mode"))
        
        // Should pass with photo configuration
        config.photoConfiguration = NextLevelPhotoConfiguration()
        validation = config.validate()
        XCTAssertTrue(validation.isValid)
        XCTAssertTrue(validation.errors.isEmpty)
    }
    
    func testFrameRateValidation() {
        var config = NextLevelCameraConfiguration.video4K(
            position: .back,
            lensType: .wideAngleCamera
        )
        
        // Test invalid frame rates
        config.preferredFrameRate = 10
        var validation = config.validate()
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.errors.contains("Frame rate must be between 15 and 240 fps"))
        
        config.preferredFrameRate = 300
        validation = config.validate()
        XCTAssertFalse(validation.isValid)
        
        // Test valid frame rate
        config.preferredFrameRate = 60
        validation = config.validate()
        XCTAssertTrue(validation.isValid)
    }
    
    func testZoomFactorValidation() {
        var config = NextLevelCameraConfiguration.video4K(
            position: .back,
            lensType: .wideAngleCamera
        )
        
        // Test invalid zoom factors
        config.zoomFactor = 0.3
        var validation = config.validate()
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.errors.contains("Zoom factor must be between 0.5 and 100.0"))
        
        config.zoomFactor = 150.0
        validation = config.validate()
        XCTAssertFalse(validation.isValid)
        
        // Test valid zoom factor
        config.zoomFactor = 2.5
        validation = config.validate()
        XCTAssertTrue(validation.isValid)
    }
    
    // MARK: - Builder Pattern Tests
    
    func testBuilderMethods() {
        let baseConfig = NextLevelCameraConfiguration(
            cameraPosition: .back,
            lensType: .wideAngleCamera,
            captureMode: .video
        )
        
        let videoConfig = NextLevelVideoConfiguration()
        let photoConfig = NextLevelPhotoConfiguration()
        let exposureConfig = NextLevelExposureConfiguration()
        let focusConfig = NextLevelFocusConfiguration()
        
        // Test video configuration builder
        let withVideo = baseConfig.withVideoConfiguration(videoConfig)
        XCTAssertNotNil(withVideo.videoConfiguration)
        XCTAssertNil(baseConfig.videoConfiguration) // Original unchanged
        
        // Test photo configuration builder
        let withPhoto = baseConfig.withPhotoConfiguration(photoConfig)
        XCTAssertNotNil(withPhoto.photoConfiguration)
        
        // Test exposure configuration builder
        let withExposure = baseConfig.withExposureConfiguration(exposureConfig)
        XCTAssertNotNil(withExposure.exposureConfiguration)
        
        // Test focus configuration builder
        let withFocus = baseConfig.withFocusConfiguration(focusConfig)
        XCTAssertNotNil(withFocus.focusConfiguration)
    }
    
    // MARK: - Equatable Tests
    
    func testEquatable() {
        let config1 = NextLevelCameraConfiguration(
            cameraPosition: .back,
            lensType: .wideAngleCamera,
            captureMode: .video
        )
        
        var config2 = NextLevelCameraConfiguration(
            cameraPosition: .back,
            lensType: .wideAngleCamera,
            captureMode: .video
        )
        
        XCTAssertEqual(config1, config2)
        
        // Change zoom factor
        config2.zoomFactor = 2.0
        XCTAssertNotEqual(config1, config2)
        
        // Reset and change frame rate
        config2.zoomFactor = 1.0
        config2.preferredFrameRate = 60
        XCTAssertNotEqual(config1, config2)
    }
}

// MARK: - NextLevelMultiCameraConfigurationV2Tests

class NextLevelMultiCameraConfigurationV2Tests: XCTestCase {
    
    func testBasicInitialization() {
        let config = NextLevelMultiCameraConfigurationV2()
        
        XCTAssertTrue(config.cameraConfigurations.isEmpty)
        XCTAssertEqual(config.outputMode, .separate)
        XCTAssertEqual(config.recordingMode, .separate)
        XCTAssertEqual(config.maximumSimultaneousCameras, 2)
        XCTAssertTrue(config.enableThermalManagement)
        XCTAssertTrue(config.enableResourceOptimization)
    }
    
    func testCameraManagement() {
        let config = NextLevelMultiCameraConfigurationV2()
        
        let camera1 = NextLevelCameraConfiguration.video4K(
            position: .back,
            lensType: .wideAngleCamera
        )
        
        let camera2 = NextLevelCameraConfiguration.photoHD(
            position: .front,
            lensType: .wideAngleCamera
        )
        
        // Add cameras
        config.setCamera(camera1, priority: .essential)
        config.setCamera(camera2, priority: .medium)
        
        XCTAssertEqual(config.cameraCount, 2)
        XCTAssertTrue(config.hasVideoCameras)
        XCTAssertTrue(config.hasPhotoCameras)
        XCTAssertEqual(config.configuredPositions, [.back, .front])
        
        // Get camera configuration
        let retrievedCamera = config.cameraConfiguration(at: .back)
        XCTAssertNotNil(retrievedCamera)
        XCTAssertEqual(retrievedCamera?.lensType, .wideAngleCamera)
        
        // Remove camera
        config.removeCamera(at: .front)
        XCTAssertEqual(config.cameraCount, 1)
        XCTAssertFalse(config.hasPhotoCameras)
    }
    
    func testUpdateCamera() {
        let config = NextLevelMultiCameraConfigurationV2()
        
        var camera = NextLevelCameraConfiguration.video4K(
            position: .back,
            lensType: .wideAngleCamera
        )
        config.setCamera(camera)
        
        // Update camera configuration
        config.updateCamera(at: .back) { camera in
            camera.zoomFactor = 2.5
            camera.preferredFrameRate = 60
        }
        
        let updated = config.cameraConfiguration(at: .back)
        XCTAssertEqual(updated?.zoomFactor, 2.5)
        XCTAssertEqual(updated?.preferredFrameRate, 60)
    }
    
    func testValidation() {
        let config = NextLevelMultiCameraConfigurationV2()
        
        // Empty configuration should fail
        var validation = config.validate()
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.errors.contains("No cameras configured"))
        
        // Add valid cameras
        config.setCamera(NextLevelCameraConfiguration.video4K(position: .back, lensType: .wideAngleCamera))
        config.setCamera(NextLevelCameraConfiguration.photoHD(position: .front, lensType: .wideAngleCamera))
        
        validation = config.validate()
        XCTAssertTrue(validation.isValid)
        
        // Test mixed mode validation
        config.outputMode = .combined
        validation = config.validate()
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.errors.contains("Mixed video/photo capture requires separate output mode"))
    }
    
    func testThermalStateAdjustment() {
        let config = NextLevelMultiCameraConfigurationV2()
        
        // Add multiple cameras with different priorities
        var camera1 = NextLevelCameraConfiguration.video4K(position: .back, lensType: .wideAngleCamera)
        camera1.preferredFrameRate = 60
        config.setCamera(camera1, priority: .essential)
        
        var camera2 = NextLevelCameraConfiguration.video4K(position: .front, lensType: .wideAngleCamera)
        camera2.preferredFrameRate = 30
        config.setCamera(camera2, priority: .medium)
        
        var camera3 = NextLevelCameraConfiguration.photoHD(position: .back2, lensType: .ultraWideAngleCamera)
        config.setCamera(camera3, priority: .low)
        
        // Test fair thermal state
        config.adjustForThermalState(.fair)
        XCTAssertEqual(config.cameraCount, 3) // All cameras still present
        let updatedCamera2 = config.cameraConfiguration(at: .front)
        XCTAssertEqual(updatedCamera2?.preferredFrameRate, 24) // Reduced frame rate
        
        // Test serious thermal state
        config.adjustForThermalState(.serious)
        XCTAssertEqual(config.cameraCount, 2) // Low priority camera removed
        XCTAssertNil(config.cameraConfiguration(at: .back2))
        
        // Test critical thermal state
        config.adjustForThermalState(.critical)
        XCTAssertEqual(config.cameraCount, 1) // Only essential camera remains
        XCTAssertNotNil(config.cameraConfiguration(at: .back))
        XCTAssertNil(config.cameraConfiguration(at: .front))
    }
    
    func testConvenienceConfigurations() {
        // Test 4K + HD Photo configuration
        let config1 = NextLevelMultiCameraConfigurationV2.video4KPlusHDPhoto()
        XCTAssertEqual(config1.cameraCount, 2)
        XCTAssertTrue(config1.hasVideoCameras)
        XCTAssertTrue(config1.hasPhotoCameras)
        XCTAssertEqual(config1.outputMode, .separate)
        
        // Test dual video recording configuration
        let config2 = NextLevelMultiCameraConfigurationV2.dualVideoRecording()
        XCTAssertEqual(config2.cameraCount, 2)
        XCTAssertTrue(config2.hasVideoCameras)
        XCTAssertFalse(config2.hasPhotoCameras)
        XCTAssertEqual(config2.outputMode, .combined)
        XCTAssertEqual(config2.recordingMode, .composited)
    }
}

// MARK: - Extended Position Tests

class NextLevelDevicePositionExtendedTests: XCTestCase {
    
    func testPositionConversion() {
        // Test primary positions
        XCTAssertEqual(NextLevelDevicePositionExtended.back.avPosition, .back)
        XCTAssertEqual(NextLevelDevicePositionExtended.front.avPosition, .front)
        XCTAssertEqual(NextLevelDevicePositionExtended.unspecified.avPosition, .unspecified)
        
        // Test extended positions
        XCTAssertEqual(NextLevelDevicePositionExtended.back2.avPosition, .back)
        XCTAssertEqual(NextLevelDevicePositionExtended.back3.avPosition, .back)
        XCTAssertEqual(NextLevelDevicePositionExtended.front2.avPosition, .front)
    }
    
    func testPrimaryPositionCheck() {
        XCTAssertTrue(NextLevelDevicePositionExtended.back.isPrimary)
        XCTAssertTrue(NextLevelDevicePositionExtended.front.isPrimary)
        XCTAssertFalse(NextLevelDevicePositionExtended.back2.isPrimary)
        XCTAssertFalse(NextLevelDevicePositionExtended.back3.isPrimary)
        XCTAssertFalse(NextLevelDevicePositionExtended.front2.isPrimary)
    }
    
    func testLensTypeConversion() {
        XCTAssertEqual(NextLevelLensType.wideAngleCamera.avDeviceType, .builtInWideAngleCamera)
        XCTAssertEqual(NextLevelLensType.ultraWideAngleCamera.avDeviceType, .builtInUltraWideCamera)
        XCTAssertEqual(NextLevelLensType.telephotoCamera.avDeviceType, .builtInTelephotoCamera)
    }
    
    func testFocalLengthEquivalent() {
        XCTAssertEqual(NextLevelLensType.ultraWideAngleCamera.focalLengthEquivalent, 13)
        XCTAssertEqual(NextLevelLensType.wideAngleCamera.focalLengthEquivalent, 26)
        XCTAssertEqual(NextLevelLensType.telephotoCamera.focalLengthEquivalent, 52)
        XCTAssertNil(NextLevelLensType.dualCamera.focalLengthEquivalent)
    }
}