//
//  NextLevelHardwareCapabilities.swift
//  NextLevel
//
//  Created by NextLevel on 7/1/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit
import os.log

/// Detects and manages hardware capabilities for multi-camera capture
public class HardwareCapabilityDetector {
    
    // MARK: - Properties
    
    /// Detected hardware capabilities
    private(set) public var capabilities: HardwareCapabilities = HardwareCapabilities()
    
    /// Device model identifier
    private let deviceModel: String
    
    /// Logger
    private let logger = OSLog(subsystem: "com.nextlevel", category: "HardwareDetector")
    
    // MARK: - Initialization
    
    public init() {
        self.deviceModel = HardwareCapabilityDetector.getDeviceModel()
        detectCapabilities()
    }
    
    // MARK: - Detection
    
    /// Detect hardware capabilities
    public func detectCapabilities() -> HardwareCapabilities {
        os_log("Detecting hardware capabilities for device: %@", log: logger, type: .info, deviceModel)
        
        // Base capabilities
        capabilities.deviceModel = deviceModel
        capabilities.isMultiCamSupported = AVCaptureMultiCamSession.isMultiCamSupported
        
        // Detect specific capabilities
        detectCameraCapabilities()
        detectMemoryCapabilities()
        detectProcessingCapabilities()
        detectDeviceSpecificLimitations()
        
        os_log("Hardware detection complete", log: logger, type: .info)
        
        return capabilities
    }
    
    // MARK: - Camera Detection
    
    private func detectCameraCapabilities() {
        // Count available cameras
        var cameraCount = 0
        var supportedLensTypes: Set<NextLevelLensType> = []
        
        for lensType in NextLevelLensType.allCases {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [lensType.avDeviceType],
                mediaType: .video,
                position: .unspecified
            )
            
            for device in discoverySession.devices {
                cameraCount += 1
                supportedLensTypes.insert(lensType)
                
                // Check specific camera features
                if device.position == .back {
                    checkBackCameraFeatures(device)
                } else if device.position == .front {
                    checkFrontCameraFeatures(device)
                }
            }
        }
        
        capabilities.totalCameras = cameraCount
        capabilities.supportedLensTypes = Array(supportedLensTypes)
        
        // Determine max simultaneous cameras based on device
        capabilities.maxCameras = determineMaxSimultaneousCameras()
    }
    
    private func checkBackCameraFeatures(_ device: AVCaptureDevice) {
        // Check 4K support
        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            
            if dimensions.width >= 3840 && dimensions.height >= 2160 {
                capabilities.supports4K = true
                
                // Check 4K frame rates
                for range in format.videoSupportedFrameRateRanges {
                    if range.maxFrameRate >= 60 {
                        capabilities.supports4K60fps = true
                    }
                }
            }
            
            // Check HDR support
            if format.isVideoHDRSupported {
                capabilities.supportsHDR = true
            }
        }
        
        // Check other features
        // Portrait effects matte support check would go here
        capabilities.supportsDepthCapture = false
        capabilities.supportsProRAW = checkProRAWSupport(device)
    }
    
    private func checkFrontCameraFeatures(_ device: AVCaptureDevice) {
        // Front camera specific checks
        capabilities.hasTrueDepthCamera = device.deviceType == .builtInTrueDepthCamera
    }
    
    // MARK: - Memory Detection
    
    private func detectMemoryCapabilities() {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        
        // Set memory limits based on total RAM
        if physicalMemory >= 6 * 1024 * 1024 * 1024 { // 6GB+
            capabilities.maxMemory = 3 * 1024 * 1024 * 1024 // 3GB for capture
            capabilities.memoryTier = .high
        } else if physicalMemory >= 4 * 1024 * 1024 * 1024 { // 4GB+
            capabilities.maxMemory = 2 * 1024 * 1024 * 1024 // 2GB for capture
            capabilities.memoryTier = .medium
        } else {
            capabilities.maxMemory = 1 * 1024 * 1024 * 1024 // 1GB for capture
            capabilities.memoryTier = .low
        }
    }
    
    // MARK: - Processing Detection
    
    private func detectProcessingCapabilities() {
        // Detect processor capabilities
        let processorCount = ProcessInfo.processInfo.processorCount
        
        capabilities.cpuCores = processorCount
        capabilities.maxCPU = 80.0 // Conservative limit
        
        // GPU capabilities based on device
        let gpuCapabilities = detectGPUCapabilities()
        capabilities.maxGPU = gpuCapabilities.maxUsage
        capabilities.gpuTier = gpuCapabilities.tier
        
        // Bandwidth based on device generation
        capabilities.maxBandwidth = determineBandwidth()
    }
    
    private func detectGPUCapabilities() -> (maxUsage: Double, tier: PerformanceTier) {
        // Determine GPU tier based on device model
        if deviceModel.contains("iPhone15") || deviceModel.contains("iPhone14,") {
            return (90.0, .high)
        } else if deviceModel.contains("iPhone13") || deviceModel.contains("iPhone12") {
            return (80.0, .medium)
        } else {
            return (70.0, .low)
        }
    }
    
    // MARK: - Device Specific
    
    private func detectDeviceSpecificLimitations() {
        // Set specific limitations based on device model
        
        // iPhone 15 Pro/Pro Max
        if deviceModel.contains("iPhone16,") {
            capabilities.maxCameras = 3
            capabilities.supportedResolutions = ["4K", "1080p", "720p"]
            capabilities.supportedFrameRates = [24, 25, 30, 60, 120, 240]
            capabilities.supportsProRes = true
        }
        // iPhone 14 Pro/Pro Max
        else if deviceModel.contains("iPhone15,") {
            capabilities.maxCameras = 2
            capabilities.supportedResolutions = ["4K", "1080p", "720p"]
            capabilities.supportedFrameRates = [24, 25, 30, 60, 120]
            capabilities.supportsProRes = true
        }
        // iPhone 13 Pro/Pro Max
        else if deviceModel.contains("iPhone14,") {
            capabilities.maxCameras = 2
            capabilities.supportedResolutions = ["4K", "1080p", "720p"]
            capabilities.supportedFrameRates = [24, 25, 30, 60]
            capabilities.supportsProRes = true
        }
        // iPhone 12 Pro/Pro Max
        else if deviceModel.contains("iPhone13,") {
            capabilities.maxCameras = 2
            capabilities.supportedResolutions = ["4K", "1080p", "720p"]
            capabilities.supportedFrameRates = [24, 25, 30, 60]
        }
        // Older devices
        else {
            capabilities.maxCameras = AVCaptureMultiCamSession.isMultiCamSupported ? 2 : 1
            capabilities.supportedResolutions = ["1080p", "720p"]
            capabilities.supportedFrameRates = [24, 25, 30]
        }
        
        // Apply thermal limitations
        applyThermalLimitations()
    }
    
    private func applyThermalLimitations() {
        // Reduce capabilities based on thermal considerations
        let thermalReduction: Double = 0.8
        
        capabilities.thermalLimits = ThermalLimits(
            maxSustainedBandwidth: capabilities.maxBandwidth * thermalReduction,
            maxSustainedCPU: capabilities.maxCPU * thermalReduction,
            maxSustainedGPU: capabilities.maxGPU * thermalReduction,
            cooldownRequired: true
        )
    }
    
    // MARK: - Helper Methods
    
    private func determineMaxSimultaneousCameras() -> Int {
        // Check if multi-cam is supported
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            return 1
        }
        
        // Determine based on device
        if deviceModel.contains("iPhone16,") {
            return 3 // iPhone 15 Pro can handle 3 cameras
        } else if deviceModel.contains("iPhone15,") || deviceModel.contains("iPhone14,") {
            return 2 // iPhone 13/14 Pro can handle 2 cameras
        } else {
            return 2 // Default for multi-cam supported devices
        }
    }
    
    private func determineBandwidth() -> Double {
        // Bandwidth in Mbps based on device generation
        if deviceModel.contains("iPhone16,") {
            return 600.0 // iPhone 15 Pro
        } else if deviceModel.contains("iPhone15,") {
            return 500.0 // iPhone 14 Pro
        } else if deviceModel.contains("iPhone14,") {
            return 400.0 // iPhone 13 Pro
        } else {
            return 300.0 // Older devices
        }
    }
    
    private func checkProRAWSupport(_ device: AVCaptureDevice) -> Bool {
        // ProRAW requires specific device capabilities
        guard #available(iOS 14.3, *) else { return false }
        
        // Check if device supports Apple ProRAW
        for format in device.formats {
            if format.supportedColorSpaces.contains(.P3_D65) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Device Model Detection
    
    private static func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}

// MARK: - Hardware Capabilities Model

/// Hardware capabilities structure
public struct HardwareCapabilities {
    // Device info
    var deviceModel: String = ""
    var isMultiCamSupported: Bool = false
    
    // Camera capabilities
    var totalCameras: Int = 0
    var maxCameras: Int = 1
    var supportedLensTypes: [NextLevelLensType] = []
    var supports4K: Bool = false
    var supports4K60fps: Bool = false
    var supportsHDR: Bool = false
    var supportsProRes: Bool = false
    var supportsProRAW: Bool = false
    var supportsDepthCapture: Bool = false
    var hasTrueDepthCamera: Bool = false
    
    // Performance capabilities
    var maxBandwidth: Double = 300.0 // Mbps
    var maxMemory: Int64 = 1 * 1024 * 1024 * 1024 // 1GB
    var maxCPU: Double = 80.0 // Percentage
    var maxGPU: Double = 80.0 // Percentage
    var cpuCores: Int = 4
    
    // Supported configurations
    var supportedResolutions: [String] = ["1080p", "720p"]
    var supportedFrameRates: [Int] = [24, 25, 30]
    
    // Performance tiers
    var memoryTier: PerformanceTier = .medium
    var gpuTier: PerformanceTier = .medium
    
    // Thermal limits
    var thermalLimits: ThermalLimits = ThermalLimits()
}

/// Performance tier enumeration
public enum PerformanceTier: Int {
    case low = 0
    case medium = 1
    case high = 2
}

/// Thermal limits
public struct ThermalLimits {
    var maxSustainedBandwidth: Double = 240.0 // Mbps
    var maxSustainedCPU: Double = 60.0 // Percentage
    var maxSustainedGPU: Double = 60.0 // Percentage
    var cooldownRequired: Bool = true
}

// MARK: - Hardware Limitation Manager

/// Manages hardware limitations and provides fallback strategies
public class HardwareLimitationManager {
    
    // MARK: - Properties
    
    private let capabilities: HardwareCapabilities
    private let logger = OSLog(subsystem: "com.nextlevel", category: "HardwareLimitations")
    
    // MARK: - Initialization
    
    public init(capabilities: HardwareCapabilities) {
        self.capabilities = capabilities
    }
    
    // MARK: - Validation
    
    /// Validate configuration against hardware limitations
    public func validateConfiguration(_ config: NextLevelMultiCameraConfigurationV2) -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        // Check camera count
        if config.cameraCount > capabilities.maxCameras {
            errors.append("Device supports maximum \(capabilities.maxCameras) simultaneous cameras")
        }
        
        // Check each camera configuration
        for (_, cameraConfig) in config.cameraConfigurations {
            validateCameraConfiguration(cameraConfig, errors: &errors, warnings: &warnings)
        }
        
        // Check combined resource usage
        validateCombinedResources(config, errors: &errors, warnings: &warnings)
        
        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }
    
    private func validateCameraConfiguration(_ config: NextLevelCameraConfiguration, 
                                           errors: inout [String], 
                                           warnings: inout [String]) {
        // Check resolution support
        if let videoConfig = config.videoConfiguration {
            let resolution = getResolutionString(for: videoConfig.preset)
            
            if !capabilities.supportedResolutions.contains(resolution) {
                errors.append("Resolution \(resolution) not supported on this device")
            }
            
            // Check frame rate
            if !capabilities.supportedFrameRates.contains(config.preferredFrameRate) {
                errors.append("Frame rate \(config.preferredFrameRate)fps not supported")
            }
            
            // Check 4K60 specific
            if resolution == "4K" && config.preferredFrameRate >= 60 && !capabilities.supports4K60fps {
                errors.append("4K at 60fps not supported on this device")
            }
        }
        
        // Check HDR
        if config.isHDREnabled && !capabilities.supportsHDR {
            warnings.append("HDR not supported on this device")
        }
    }
    
    private func validateCombinedResources(_ config: NextLevelMultiCameraConfigurationV2,
                                         errors: inout [String],
                                         warnings: inout [String]) {
        // Calculate total bandwidth
        var totalBandwidth = 0.0
        
        for (_, cameraConfig) in config.cameraConfigurations {
            if let videoConfig = cameraConfig.videoConfiguration {
                let bitrate = Double(videoConfig.bitRate) / (1024 * 1024) // Convert to Mbps
                totalBandwidth += bitrate
            }
        }
        
        if totalBandwidth > capabilities.maxBandwidth {
            errors.append("Total bandwidth (\(Int(totalBandwidth))Mbps) exceeds device limit (\(Int(capabilities.maxBandwidth))Mbps)")
        }
        
        if totalBandwidth > capabilities.thermalLimits.maxSustainedBandwidth {
            warnings.append("Configuration may cause thermal throttling during extended use")
        }
    }
    
    // MARK: - Fallback Strategies
    
    /// Get fallback configuration for unsupported setup
    public func getFallbackConfiguration(for config: NextLevelMultiCameraConfigurationV2) -> NextLevelMultiCameraConfigurationV2 {
        let fallback = NextLevelMultiCameraConfigurationV2()
        
        // Limit camera count
        let maxCameras = min(config.cameraCount, capabilities.maxCameras)
        var addedCameras = 0
        
        // Add cameras by priority
        let sortedCameras = config.cameraConfigurations.sorted { 
            (config.cameraPriorities[$0.key] ?? .medium).rawValue > 
            (config.cameraPriorities[$1.key] ?? .medium).rawValue
        }
        
        for (position, cameraConfig) in sortedCameras {
            guard addedCameras < maxCameras else { break }
            
            let adjustedConfig = getAdjustedCameraConfiguration(cameraConfig)
            fallback.setCamera(adjustedConfig, priority: config.cameraPriorities[position] ?? .medium)
            addedCameras += 1
        }
        
        os_log("Created fallback configuration with %d cameras", log: logger, type: .info, addedCameras)
        
        return fallback
    }
    
    private func getAdjustedCameraConfiguration(_ config: NextLevelCameraConfiguration) -> NextLevelCameraConfiguration {
        var adjusted = config
        
        // Adjust video settings
        if let videoConfig = config.videoConfiguration {
            var adjustedVideo = videoConfig
            
            // Limit resolution
            if !capabilities.supports4K && videoConfig.preset == .hd4K3840x2160 {
                adjustedVideo.preset = .hd1920x1080
            }
            
            // Limit frame rate
            let maxFrameRate = capabilities.supportedFrameRates.max() ?? 30
            adjusted.preferredFrameRate = min(config.preferredFrameRate, maxFrameRate)
            
            adjusted.videoConfiguration = adjustedVideo
        }
        
        // Disable unsupported features
        if !capabilities.supportsHDR {
            adjusted.isHDREnabled = false
        }
        
        return adjusted
    }
    
    private func getResolutionString(for preset: AVCaptureSession.Preset) -> String {
        switch preset {
        case .hd4K3840x2160:
            return "4K"
        case .hd1920x1080:
            return "1080p"
        case .hd1280x720:
            return "720p"
        default:
            return "SD"
        }
    }
}

// MARK: - Validation Result

public struct ValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
}