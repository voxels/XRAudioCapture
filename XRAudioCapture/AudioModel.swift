//
//  AudioModel.swift
//  XRAudioCapture
//
//  Created by Michael A Edgcumbe on 2/1/24.
//

import SwiftUI
import AVFoundation
import PHASE
import CoreMotion
import ARKit

open class AudioModel: NSObject, Identifiable, ObservableObject {
    
    public var id = UUID()
    let audioEngine = AVAudioEngine()
    let phaseEngines = [PHASEEngine(updateMode: .automatic)]
    var phaseEngine:PHASEEngine {
        return phaseEngines.first!
    }
    var sources = [PHASESource]()
    var listeners = [PHASEListener]()
#if os(iOS)
    let hmm = CMHeadphoneMotionManager()
#endif
    let motionManager = CMMotionManager()
    var deviceTransform: simd_float4x4 = matrix_identity_float4x4;
    var headphoneTransform: simd_float4x4 = matrix_identity_float4x4;
    
    static let sourceFiles:[URL] = [
        Bundle.main.url(forResource: "wind_grass", withExtension: "wav")!,
        Bundle.main.url(forResource: "wind_gusts", withExtension: "wav")!,
        Bundle.main.url(forResource: "surf", withExtension: "wav")!,
    ]
    static let locations:[SIMD3<Float>] = [
        SIMD3(0,0.1,0),
        SIMD3(0,20,0),
        SIMD3(200,0,200),
    ]
    
    static let sendLevels:[Double] = [
        0.02,
        0.01,
        0.02,
    ]
    
    static let playbackModes:[PHASEPlaybackMode] = [.looping, .looping,.looping,.looping,]

    private var displayLink:CADisplayLink!
    public override init(){
        super.init()
        createDisplayLink()
        for _ in AudioModel.sourceFiles {
            let engine = phaseEngine
            engine.outputSpatializationMode = .automatic
            let source = PHASESource(engine: engine)
            let listener = PHASEListener(engine: engine)
            sources.append(source)
            listeners.append(listener)
        }
    }
    
    public func startEngine(_ phaseEngine:PHASEEngine) throws{
        try phaseEngine.start()
#if os(iOS)
        hmm.startDeviceMotionUpdates(to: OperationQueue.current!) {[weak self] motion, error in
            guard let motion = motion, error == nil else { return }
            self?.handleHeadMovement(motion)
        }
#endif
#if os(visionOS)
        motionManager.startDeviceMotionUpdates(to: OperationQueue.current!) {[weak self] motion, error in
            guard let motion = motion, error == nil else { return }
            self?.handleDeviceMovement(motion)
        }
#endif
    }
    
    func handleHeadMovement(_ motion: CMDeviceMotion) {
        let m = motion.attitude.rotationMatrix
        let x = SIMD4(Float(m.m11), Float(m.m21), Float(m.m31), 0)
        let y = SIMD4(Float(m.m12), Float(m.m22), Float(m.m32), 0)
        let z = SIMD4(Float(m.m13), Float(m.m23), Float(m.m33), 0)
        let w = SIMD4(Float(0), Float(0), Float(0), Float(1))
        self.headphoneTransform = simd_float4x4(columns: (x, y, z, w))
        //listener1.transform = deviceTransform * headphoneTransform
    }
    
    func handleDeviceMovement(_ motion: CMDeviceMotion) {
        let m = motion.attitude.rotationMatrix
        let x = SIMD4(Float(m.m11), Float(m.m21), Float(m.m31), 0)
        let y = SIMD4(Float(m.m12), Float(m.m22), Float(m.m32), 0)
        let z = SIMD4(Float(m.m13), Float(m.m23), Float(m.m33), 0)
        let w = SIMD4(Float(0), Float(0), Float(0), Float(1))
        self.deviceTransform = simd_float4x4(columns: (x, y, z, w))
        //listener1.transform = deviceTransform * headphoneTransform
    }
    
    public func addListener(_ listener:PHASEListener) throws {
        try phaseEngine.rootObject.addChild(listener)
    }
    
    public func addSpatialRecordedSession(at url:URL, source:PHASESource, listener:PHASEListener, location:SIMD3<Float>, sendLevel:Double = 0.1, cullDistance:Double = 1200.0, playbackMode:PHASEPlaybackMode) throws ->PHASESoundEvent {

        
        source.transform.columns.3.x = location.x
        source.transform.columns.3.y = location.y
        source.transform.columns.3.z = location.z
            try phaseEngine.rootObject.addChild(source)
        //try phaseEngine.rootObject.addChild(listener)
            let asset = try  self.phaseEngine.assetRegistry.registerSoundAsset(url: url, identifier: nil, assetType: .streamed, channelLayout:nil , normalizationMode: .dynamic)
            // Create a Spatial Pipeline.
            
            let spatialPipeline = PHASESpatialPipeline(flags: [.directPathTransmission, .lateReverb])!
            spatialPipeline.entries[PHASESpatialCategory.lateReverb]!.sendLevel = 0.1;
            spatialPipeline.entries[PHASESpatialCategory.directPathTransmission]!.sendLevel = sendLevel
            self.phaseEngine.defaultReverbPreset = .mediumRoom
            
            // Create a Spatial Mixer with the Spatial Pipeline.
            let spatialMixerDefinition = PHASESpatialMixerDefinition(spatialPipeline: spatialPipeline)
            
            // Set the Spatial Mixer's Distance Model.
            let distanceModelParameters = PHASEGeometricSpreadingDistanceModelParameters()
            distanceModelParameters.fadeOutParameters = PHASEDistanceModelFadeOutParameters(cullDistance: cullDistance)
        distanceModelParameters.rolloffFactor = 1.0
            spatialMixerDefinition.distanceModelParameters = distanceModelParameters
            
            // Create a Sampler Node from "drums" and hook it into the downstream Spatial Mixer.
            let samplerNodeDefinition = PHASESamplerNodeDefinition(soundAssetIdentifier: asset.identifier, mixerDefinition:spatialMixerDefinition)
            
            // Set the Sampler Node's Playback Mode to Looping.
            samplerNodeDefinition.playbackMode = playbackMode
            
            // Set the Sampler Node's Calibration Mode to Relative SPL and Level to 12 dB.
            samplerNodeDefinition.setCalibrationMode(calibrationMode: .relativeSpl, level: 1)
            
            // Set the Sampler Node's Cull Option to Sleep.
            samplerNodeDefinition.cullOption = .sleepWakeAtRealtimeOffset
            let soundEventAsset = try self.phaseEngine.assetRegistry.registerSoundEventAsset(rootNode: samplerNodeDefinition, identifier: asset.identifier + "_SoundEventAsset")
            
            let mixerParameters = PHASEMixerParameters()
            
            mixerParameters.addSpatialMixerParameters(identifier: spatialMixerDefinition.identifier, source: source, listener: listener)
            let bufferSoundEvent = try PHASESoundEvent(engine: self.phaseEngine, assetIdentifier: soundEventAsset.identifier, mixerParameters: mixerParameters)
            
           
        return bufferSoundEvent
    }
    
    public func addAmbientRecordedSession(at urls:[URL], sources:[PHASESource], listener:PHASEListener, playbackModes:[PHASEPlaybackMode]) throws ->[PHASESoundEvent] {

        var countSources = 0
        var retval = [PHASESoundEvent]()
        for source in sources{
            
            try phaseEngine.rootObject.addChild(source)
            
            let asset = try  self.phaseEngine.assetRegistry.registerSoundAsset(url: urls[countSources], identifier: nil, assetType: .streamed, channelLayout:nil , normalizationMode: .dynamic)
            // Create a Spatial Pipeline.
            
            self.phaseEngine.defaultReverbPreset = .largeChamber
            
            let orientation = simd_quatf(ix: 1.0, iy: 0.0, iz: 0.0, r: 0.0)
            let ambientMixerDefinition = PHASEAmbientMixerDefinition(channelLayout: .init(layoutTag: kAudioChannelLayoutTag_Stereo)!, orientation: orientation)

            
            // Create a Sampler Node from "drums" and hook it into the downstream Spatial Mixer.
            let samplerNodeDefinition = PHASESamplerNodeDefinition(soundAssetIdentifier: asset.identifier, mixerDefinition:ambientMixerDefinition)
            
            // Set the Sampler Node's Playback Mode to Looping.
            samplerNodeDefinition.playbackMode = playbackModes[countSources]
            
            // Set the Sampler Node's Calibration Mode to Relative SPL and Level to 12 dB.
            samplerNodeDefinition.setCalibrationMode(calibrationMode: .relativeSpl, level: 1)
            
            // Set the Sampler Node's Cull Option to Sleep.
            samplerNodeDefinition.cullOption = .sleepWakeAtRealtimeOffset
            let soundEventAsset = try self.phaseEngine.assetRegistry.registerSoundEventAsset(rootNode: samplerNodeDefinition, identifier: asset.identifier + "_SoundEventAsset")
            
            let mixerParameters = PHASEMixerParameters()
            mixerParameters.addAmbientMixerParameters(identifier: ambientMixerDefinition.identifier, listener: listener)
            let bufferSoundEvent = try PHASESoundEvent(engine: self.phaseEngine, assetIdentifier: soundEventAsset.identifier, mixerParameters: mixerParameters)
            
            retval.append(bufferSoundEvent)
            countSources += 1
            
        }
        return retval
    }
    
    public func liveSession() throws{
        try phaseEngine.start()
        let inputNode = audioEngine.inputNode
        let audioFormat = inputNode.outputFormat(forBus: 0)
        let source = PHASESource(engine:self.phaseEngine )
        //source.transform =
        let listener = PHASEListener(engine: self.phaseEngine)
        inputNode.installTap(onBus: 0, bufferSize: 8192, format: audioFormat) { buffer, time in
            do{
                let asset = try  self.phaseEngine.assetRegistry.registerSoundAsset(data: Data(buffer: buffer, time: time), identifier: nil, format: audioFormat, normalizationMode: .dynamic)
                // Create a Spatial Pipeline.
                
                let spatialPipeline = PHASESpatialPipeline(flags: [.directPathTransmission, .lateReverb])!
                spatialPipeline.entries[PHASESpatialCategory.lateReverb]!.sendLevel = 0.1;
                self.phaseEngine.defaultReverbPreset = .mediumRoom
                
                // Create a Spatial Mixer with the Spatial Pipeline.
                let spatialMixerDefinition = PHASESpatialMixerDefinition(spatialPipeline: spatialPipeline)
                
                // Set the Spatial Mixer's Distance Model.
                let distanceModelParameters = PHASEGeometricSpreadingDistanceModelParameters()
                distanceModelParameters.fadeOutParameters = PHASEDistanceModelFadeOutParameters(cullDistance: 10.0)
                distanceModelParameters.rolloffFactor = 0.25
                spatialMixerDefinition.distanceModelParameters = distanceModelParameters
                
                // Create a Sampler Node from "drums" and hook it into the downstream Spatial Mixer.
                let samplerNodeDefinition = PHASESamplerNodeDefinition(soundAssetIdentifier: asset.identifier, mixerDefinition:spatialMixerDefinition)
                
                // Set the Sampler Node's Playback Mode to Looping.
                samplerNodeDefinition.playbackMode = .oneShot
                
                // Set the Sampler Node's Calibration Mode to Relative SPL and Level to 12 dB.
                samplerNodeDefinition.setCalibrationMode(calibrationMode: .relativeSpl, level: 3)
                
                // Set the Sampler Node's Cull Option to Sleep.
                samplerNodeDefinition.cullOption = .sleepWakeAtRealtimeOffset
                let soundEventAsset = try self.phaseEngine.assetRegistry.registerSoundEventAsset(rootNode: samplerNodeDefinition, identifier: asset.identifier + "_SoundEventAsset")
                
                let mixerParameters = PHASEMixerParameters()
                
                mixerParameters.addSpatialMixerParameters(identifier: spatialMixerDefinition.identifier, source: source, listener: listener)
                let bufferSoundEvent = try PHASESoundEvent(engine: self.phaseEngine, assetIdentifier: soundEventAsset.identifier, mixerParameters: mixerParameters)
                bufferSoundEvent.start()
            } catch {
                print(error)
            }
        }
    }
    
    public func add71MultichannelRecordedSession(at url:URL, source:PHASESource, listener:PHASEListener, playbackMode:PHASEPlaybackMode) throws ->PHASESoundEvent {

            try phaseEngine.rootObject.addChild(source)
            
            let asset = try  self.phaseEngine.assetRegistry.registerSoundAsset(url: url, identifier: nil, assetType: .streamed, channelLayout:AVAudioChannelLayout(layoutTag:  kAudioChannelLayoutTag_AudioUnit_7_1) , normalizationMode: .dynamic)
            // Create a Spatial Pipeline.
            
            self.phaseEngine.defaultReverbPreset = .largeChamber
            
            let orientation = simd_quatf(ix: 1.0, iy: 0.0, iz: 0.0, r: 0.0)
            let ambientMixerDefinition = PHASEAmbientMixerDefinition(channelLayout: .init(layoutTag: kAudioChannelLayoutTag_AudioUnit_7_1)!, orientation: orientation)

            
            // Create a Sampler Node from "drums" and hook it into the downstream Spatial Mixer.
            let samplerNodeDefinition = PHASESamplerNodeDefinition(soundAssetIdentifier: asset.identifier, mixerDefinition:ambientMixerDefinition)
            
            // Set the Sampler Node's Playback Mode to Looping.
            samplerNodeDefinition.playbackMode = playbackMode
            
            // Set the Sampler Node's Calibration Mode to Relative SPL and Level to 12 dB.
            samplerNodeDefinition.setCalibrationMode(calibrationMode: .relativeSpl, level: 1)
            
            // Set the Sampler Node's Cull Option to Sleep.
            samplerNodeDefinition.cullOption = .sleepWakeAtRealtimeOffset
            let soundEventAsset = try self.phaseEngine.assetRegistry.registerSoundEventAsset(rootNode: samplerNodeDefinition, identifier: asset.identifier + "_SoundEventAsset")
            
            let mixerParameters = PHASEMixerParameters()
            mixerParameters.addAmbientMixerParameters(identifier: ambientMixerDefinition.identifier, listener: listener)
            let bufferSoundEvent = try PHASESoundEvent(engine: self.phaseEngine, assetIdentifier: soundEventAsset.identifier, mixerParameters: mixerParameters)
            
            return bufferSoundEvent

    }
}

extension AudioModel {
    private func createDisplayLink() {
        displayLink = CADisplayLink(target: self, selector:#selector(onFrame(link:)))
        displayLink.add(to: .main, forMode: .default)
    }
}


extension AudioModel {
    
    @objc func onFrame(link:CADisplayLink) {
        
        let time = link.timestamp
        
        var source1Transform: simd_float4x4 = matrix_identity_float4x4
        var xPos:Float = 0.0
        xPos += 2 * cos(Float(time))
        let yPos:Float = 1
        var zPos:Float = 0
        zPos += 2 * sin(Float(time))
        source1Transform.columns.3.x = xPos
        source1Transform.columns.3.y = yPos
        source1Transform.columns.3.z = zPos
        //source1.transform = source1Transform
    }
}


extension Data {
    init(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        self.init(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
    }
}


#if os(iOS)

extension AudioModel : ARSessionDelegate {
    
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
          self.deviceTransform = frame.camera.transform
          //listener1.transform = deviceTransform * headphoneTransform
    }

}
#endif
