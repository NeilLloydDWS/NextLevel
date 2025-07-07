//
//  NextLevelMigrationGuide.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation

/// Migration guide from legacy multi-camera API to V2
public class NextLevelMigrationGuide {
    
    // MARK: - Migration Examples
    
    /// Example 1: Basic dual camera setup migration
    public static func migrateDualCameraSetup() {
        // Legacy approach
        let legacyConfig = NextLevelMultiCameraConfiguration()
        // Properties no longer exist in legacy config
        // legacyConfig.primaryCameraDevice = .back
        // legacyConfig.secondaryCameraDevice = .front
        // ... configuration continues
        
        // V2 approach
        let v2Config = NextLevelMultiCameraConfigurationV2()
        
        // Add primary camera
        var primaryCamera = NextLevelCameraConfiguration(
            cameraPosition: .back,
            lensType: .wideAngleCamera,
            captureMode: .video
        )
        
        let primaryVideoConfig = NextLevelVideoConfiguration()
        primaryVideoConfig.preset = .hd1920x1080
        // primaryVideoConfig.bitRate = legacyConfig.videoBitRate
        // primaryVideoConfig.maxFrameRate = 30
        primaryCamera.videoConfiguration = primaryVideoConfig
        primaryCamera.preferredFrameRate = 30
        
        v2Config.setCamera(primaryCamera, priority: .high)
        
        // Add secondary camera
        var secondaryCamera = NextLevelCameraConfiguration(
            cameraPosition: .front,
            lensType: .wideAngleCamera,
            captureMode: .video
        )
        
        let secondaryVideoConfig = NextLevelVideoConfiguration()
        secondaryVideoConfig.preset = .hd1280x720
        // secondaryVideoConfig.bitRate = legacyConfig.videoBitRate / 2
        // secondaryVideoConfig.maxFrameRate = 30
        secondaryCamera.videoConfiguration = secondaryVideoConfig
        secondaryCamera.preferredFrameRate = 30
        
        v2Config.setCamera(secondaryCamera, priority: .medium)
        
        // v2Config.maxSimultaneousCameras = 2
        // v2Config.enableAutoThermalManagement = true
    }
    
    /// Example 2: Audio configuration migration
    public static func migrateAudioConfiguration() {
        // Legacy approach embedded audio in configuration
        let legacyConfig = NextLevelMultiCameraConfiguration()
        // ... camera setup
        
        // V2 approach separates audio
        let v2Config = NextLevelMultiCameraConfigurationV2()
        
        // Configure audio separately
        let audioConfig = NextLevelAudioConfiguration()
        audioConfig.bitRate = 128000
        
        v2Config.audioConfiguration = audioConfig
        v2Config.audioSource = .back // Which camera's mic to use
    }
    
    /// Example 3: Device position migration
    public static func migrateDevicePositions() {
        // Legacy approach limited positions
        // let legacyPrimary = legacyConfig.primaryCameraDevice
        // let legacySecondary = legacyConfig.secondaryCameraDevice
        
        // V2 approach with extended positions
        let positions: [NextLevelDevicePosition] = [
            .back,      // Primary back camera
            .front,     // Front camera
            // Extended positions would be defined if available
        ]
        
        // Can now configure multiple back cameras
        let wideCamera = NextLevelCameraConfiguration(
            cameraPosition: .back,
            lensType: .wideAngleCamera,
            captureMode: .video
        )
        
        let ultraWideCamera = NextLevelCameraConfiguration(
            cameraPosition: .back,
            lensType: .ultraWideAngleCamera,
            captureMode: .video
        )
        
        let telephotoCamera = NextLevelCameraConfiguration(
            cameraPosition: .back,
            lensType: .telephotoCamera,
            captureMode: .video
        )
    }
    
    /// Example 4: Lens type usage
    public static func migrateLensTypes() {
        // V2 supports multiple lens types
        let lensTypes: [NextLevelLensType] = [
            .wideAngleCamera,
            .ultraWideAngleCamera,
            .telephotoCamera,
            // .trueDepthCamera // Not available
        ]
        
        // Match camera position with appropriate lens type
        for lensType in lensTypes {
            let camera = NextLevelCameraConfiguration(
                cameraPosition: .back,
                lensType: lensType,
                captureMode: .video
            )
            // Configure as needed
        }
    }
    
    // MARK: - Key Differences
    
    /// Summary of key API differences
    public static func keyDifferences() {
        /*
         Key Migration Points:
         
         1. Configuration Structure:
            - Legacy: Single configuration object with fixed properties
            - V2: Modular configuration with per-camera settings
         
         2. Camera Management:
            - Legacy: Primary/Secondary camera model
            - V2: Unlimited cameras with priority system
         
         3. Resource Management:
            - Legacy: Basic thermal management
            - V2: Advanced resource allocation with priorities
         
         4. Flexibility:
            - Legacy: Fixed camera combinations
            - V2: Any combination of cameras with different settings
         
         5. Performance:
            - Legacy: Limited optimization options
            - V2: Fine-grained performance control
         */
    }
    
    // MARK: - Migration Checklist
    
    /// Checklist for migration
    public static func migrationChecklist() -> [String] {
        return [
            "1. Update to NextLevelMultiCameraConfigurationV2",
            "2. Replace primary/secondary model with individual camera configs",
            "3. Set camera priorities based on importance",
            "4. Configure audio separately if needed",
            "5. Enable thermal management",
            "6. Update delegate methods to V2 protocol",
            "7. Test resource allocation with multiple cameras",
            "8. Verify performance with new priority system"
        ]
    }
}