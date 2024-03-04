//
//  ImmersiveView.swift
//  XRAudioCapture
//
//  Created by Michael A Edgcumbe on 2/1/24.
//

import SwiftUI
import RealityKit
import RealityKitContent
import PHASE

struct ImmersiveView: View {
    @StateObject public var sessionManager:SessionManager = SessionManager()
    @ObservedObject public var audioModel:AudioModel
    public let ceilingTextureNames = ["Ceiling_1", "Ceiling_2"]
    public let floorTextureNames = ["Floor_1", "Floor_2", "Floor_3"]
    public let splatterTextureNames = ["Splatter_1","Splatter_1","Splatter_2","Splatter_3","Splatter_4","Splatter_5","Splatter_6","Splatter_7","Splatter_8","Splatter_9","Splatter_10","Splatter_11","Splatter_12","Splatter_13","Splatter_14"]
    public let bootTextureNames = ["Boot_Left", "Boot_Right"]
    public let feetTextureNames = ["Foot_1","Foot_2","Foot_3","Foot_4","Foot_5","Foot_6","Foot_7","Foot_8","Foot_9","Foot_10","Foot_11","Foot_12"]
    public let fingerprintTextureNames = ["Fingerprint_1","Fingerprint_2","Fingerprint_3","Fingerprint_4","Fingerprint_5"]
    
    
    @State private var skyboxEntity = Entity()
    @State private var originalSkyboxRotation:simd_quatf = simd_quatf()
    @State private var ceilingTextureEntities:[Entity] = []
    @State private var floorTextureEntities:[Entity] = []
    @State private var splatterTextureEntities:[Entity] = []
    @State private var bootTextureEntities:[Entity] = []
    @State private var feetTextureEntities:[Entity] = []
    @State private var fingerprintTextureEntities:[Entity] = []
    
    var body: some View {
        RealityView { content in
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                
                sessionManager.originLocation.transform.translation = SIMD3<Float>(0,0,0)
                content.add(sessionManager.originLocation)
                sessionManager.originLocation.addChild(sessionManager.deviceLocation)
                
                if let sphereEntity = immersiveContentEntity.findEntity(named:"Sphere") as? ModelEntity {
                    if var material = sphereEntity.model?.materials.first as? PhysicallyBasedMaterial {
                        material.faceCulling = .none
                        sphereEntity.model?.materials = [material]
                        skyboxEntity = sphereEntity
                        skyboxEntity.transform.translation = SIMD3.zero
                        originalSkyboxRotation = skyboxEntity.transform.rotation
                        sessionManager.originLocation.addChild(skyboxEntity)
                        
                    }
                }
                                
                for name in ceilingTextureNames {
                    if let entity = immersiveContentEntity.findEntity(named: name) {
                        ceilingTextureEntities.append(entity)
                        print("Appended texture entity: \(name)")
                    }
                }

                for name in floorTextureNames {
                    if let entity = immersiveContentEntity.findEntity(named: name) {
                        floorTextureEntities.append(entity)
                        print("Appended texture entity: \(name)")

                    }
                }

                for name in splatterTextureNames {
                    if let entity = immersiveContentEntity.findEntity(named: name) {
                        splatterTextureEntities.append(entity)
                        print("Appended texture entity: \(name)")

                    }
                }

                for name in bootTextureNames {
                    if let entity = immersiveContentEntity.findEntity(named: name) {
                        bootTextureEntities.append(entity)
                        print("Appended texture entity: \(name)")

                    }
                }
                
                
                for name in feetTextureNames {
                    if let entity = immersiveContentEntity.findEntity(named: name) {
                        feetTextureEntities.append(entity)
                        print("Appended texture entity: \(name)")

                    }
                }

                for name in fingerprintTextureNames {
                    if let entity = immersiveContentEntity.findEntity(named: name) {
                        fingerprintTextureEntities.append(entity)
                        print("Appended texture entity: \(name)")
                    }
                }
                
                // Add an ImageBasedLight for the immersive content
                guard let resource = try? await EnvironmentResource(named: "ImageBasedLight") else { return }
                let iblComponent = ImageBasedLightComponent(source: .single(resource), intensityExponent: 0.25)
                immersiveContentEntity.components.set(iblComponent)
                immersiveContentEntity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: immersiveContentEntity))

            }
        }
        .task {
            // Monitors changes in authorization. For example, the user may revoke authorization in Settings.
            await sessionManager.monitorSessionEvents()
        }
        .task {
            await sessionManager.requestWorldSensingAuthorization()
            //await sessionManager.requestHandsTrackingAuthorization()
            await sessionManager.runARKitSession()
        }
        .task {
            await sessionManager.processDeviceAnchorUpdates()
        }
        .task {
            do{
                let listener = audioModel.listeners[0]
                var events = [PHASESoundEvent]()

                if listener.parent == nil {
                
                try audioModel.addListener(listener)
                for index in 0..<AudioModel.sourceFiles.count{
                    let url = AudioModel.sourceFiles[index]
                    let source = audioModel.sources[index]
                   
                    let playbackModel = AudioModel.playbackModes[index]
                    let location = AudioModel.locations[index]
                    let sendLevel = AudioModel.sendLevels[index]
                    let event = try audioModel
                        .addSpatialRecordedSession(at: url, source: source, listener: listener, location: location, sendLevel: sendLevel, playbackMode: playbackModel)
                    events.append(event)
                }
                try audioModel.startEngine(audioModel.phaseEngine)
                    for event in events {
                       await event.start()
                    }
                }
            } catch {
                print(error)
            }
        }
        .onDisappear(perform: {
            for event in audioModel.phaseEngine.soundEvents {
                event.pause()
            }
            
            for location in sessionManager.ceilingLocations {
                location.removeFromParent()
            }

            for location in sessionManager.floorLocations {
                location.removeFromParent()
            }

            for location in sessionManager.wallLocations {
                location.removeFromParent()
            }

            for location in sessionManager.furnitureLocations {
                location.removeFromParent()
            }

            sessionManager.ceilingLocations.removeAll()
            sessionManager.floorLocations.removeAll()
            sessionManager.wallLocations.removeAll()
            sessionManager.furnitureLocations.removeAll()
            
        })
        .onAppear(perform: {
            for event in audioModel.phaseEngine.soundEvents {
                event.resume()
            }
        })
        .onChange(of:sessionManager.ceilingLocations) { oldValue, newValue in
            for location in newValue {
                if let anchorIdentity = sessionManager.entityIdentities[location], let textureContainer = sessionManager.textureContainers[anchorIdentity], textureContainer.hasTextures == false {
                    
                    
                    for ceilingTextureEntity in ceilingTextureEntities {
                        for _ in 0..<1 {
                            let ceilingEntity = ceilingTextureEntity.clone(recursive: false)

                            textureContainer.entity.addChild(ceilingEntity)
                            ceilingEntity.transform.translation = SIMD3<Float>.zero
                            ceilingEntity.transform.translation += SIMD3<Float>(Float.random(in: -1 * textureContainer.planeAnchor.geometry.extent.width / 2..<textureContainer.planeAnchor.geometry.extent.width / 2),Float.random(in:-0.0001..<0.0001),Float.random(in: -textureContainer.planeAnchor.geometry.extent.height / 2..<textureContainer.planeAnchor.geometry.extent.height / 2))
                            ceilingEntity.transform.rotation = simd_quatf(angle: Float.pi, axis: SIMD3<Float>(1, 0, 0))
                        }
                    }
                    
                    textureContainer.hasTextures = true
                }
            }
        }
        .onChange(of:sessionManager.floorLocations) { oldValue, newValue in
            for location in newValue {
                if let anchorIdentity = sessionManager.entityIdentities[location], let textureContainer = sessionManager.textureContainers[anchorIdentity], textureContainer.hasTextures == false {
                    
                    guard textureContainer.planeAnchor.geometry.extent.width >= 1 && textureContainer.planeAnchor.geometry.extent.height >= 1 else {
                        continue
                    }
                    
                    for floorTextureEntity in floorTextureEntities {
                        for _ in 0..<2 {
                            let floorEntity = floorTextureEntity.clone(recursive: false)

                            textureContainer.entity.addChild(floorEntity)
                            floorEntity.transform.translation = SIMD3<Float>.zero
                            floorEntity.transform.translation += SIMD3<Float>(Float.random(in: -1 * textureContainer.planeAnchor.geometry.extent.width / 2..<textureContainer.planeAnchor.geometry.extent.width / 2),Float.random(in:-0.0001..<0.0001),Float.random(in: -textureContainer.planeAnchor.geometry.extent.height / 2..<textureContainer.planeAnchor.geometry.extent.height / 2))
                                let randomScale = Float.random(in:0.05..<0.4)
                            floorEntity.transform.scale = SIMD3<Float>(randomScale, Float.random(in:-0.0001..<0.0001), randomScale)
                        }
                    }
                    

                    for bootTextureEntity in bootTextureEntities {
                        for _ in 0..<5 {
                            let bootEntity = bootTextureEntity.clone(recursive: false)
                            textureContainer.entity.addChild(bootEntity)
                            bootEntity.transform.translation = SIMD3<Float>.zero
                            bootEntity.transform.translation += SIMD3<Float>(Float.random(in: -1 * textureContainer.planeAnchor.geometry.extent.width / 2..<textureContainer.planeAnchor.geometry.extent.width / 2),Float.random(in:-0.0001..<0.0001),Float.random(in: -textureContainer.planeAnchor.geometry.extent.height / 2..<textureContainer.planeAnchor.geometry.extent.height / 2))
                            bootEntity.transform.rotation += simd_quatf(angle: Float.random(in: 0..<Float.pi), axis: SIMD3<Float>(0,1,0))
                            bootEntity.transform.scale = SIMD3<Float>(0.25, Float.random(in:-0.0001..<0.0001),0.5)
                        }
                    }

                    
                    for splatterTextureEntity in splatterTextureEntities {
                        for _ in 0..<8 {
                            let splatterEntity = splatterTextureEntity.clone(recursive: false)
                            textureContainer.entity.addChild(splatterEntity)
                            splatterEntity.transform.translation = SIMD3<Float>.zero
                            splatterEntity.transform.translation += SIMD3<Float>(Float.random(in: -1 * textureContainer.planeAnchor.geometry.extent.width / 2..<textureContainer.planeAnchor.geometry.extent.width / 2),Float.random(in:-0.0001..<0.0001),Float.random(in: -textureContainer.planeAnchor.geometry.extent.height / 2..<textureContainer.planeAnchor.geometry.extent.height / 2))
                            splatterEntity.transform.rotation += simd_quatf(angle: Float.random(in: 0..<Float.pi), axis: SIMD3<Float>(0,1,0))
                            let randomScale = Float.random(in:0.01..<0.15)
                            splatterEntity.transform.scale = SIMD3<Float>(randomScale, Float.random(in:-0.0001..<0.0001), randomScale)
                        }
                    }
                    
                    for footTextureEntity in feetTextureEntities {
                        for _ in 0..<5 {
                            let footEntity = footTextureEntity.clone(recursive: false)
                            textureContainer.entity.addChild(footEntity)
                            footEntity.transform.translation = SIMD3<Float>.zero
                            footEntity.transform.translation += SIMD3<Float>(Float.random(in: -1 * textureContainer.planeAnchor.geometry.extent.width / 2..<textureContainer.planeAnchor.geometry.extent.width / 2),Float.random(in:-0.0001..<0.0001),Float.random(in: -textureContainer.planeAnchor.geometry.extent.height / 2..<textureContainer.planeAnchor.geometry.extent.height / 2))
                            footEntity.transform.rotation += simd_quatf(angle: Float.random(in: 0..<Float.pi), axis: SIMD3<Float>(0,1,0))
                            footEntity.transform.scale = SIMD3<Float>(0.25, Float.random(in:-0.0001..<0.0001),0.5)
                        }
                    }
                    
                    textureContainer.hasTextures = true
                }
            }
        }
        .onChange(of:sessionManager.wallLocations) { oldValue, newValue in
            
            
            for location in newValue {
                if let anchorIdentity = sessionManager.entityIdentities[location], let textureContainer = sessionManager.textureContainers[anchorIdentity], textureContainer.hasTextures == false {
                    
                    guard textureContainer.planeAnchor.geometry.extent.width >= 1 && textureContainer.planeAnchor.geometry.extent.height >= 1 else {
                        continue
                    }
                    
                    for splatterTextureEntity in splatterTextureEntities {
                        for _ in 0..<4 {
                            let splatterEntity = splatterTextureEntity.clone(recursive: false)
                            textureContainer.entity.addChild(splatterEntity)
                            splatterEntity.transform.translation = SIMD3<Float>.zero
                            splatterEntity.transform.translation += SIMD3<Float>(Float.random(in: -1 * textureContainer.planeAnchor.geometry.extent.width / 2..<textureContainer.planeAnchor.geometry.extent.width / 2),Float.random(in:-0.0001..<0.0001),Float.random(in: -textureContainer.planeAnchor.geometry.extent.height / 2..<textureContainer.planeAnchor.geometry.extent.height / 2))
                            let randomScale = Float.random(in:0.01..<0.25)
                            splatterEntity.transform.scale = SIMD3<Float>(randomScale, Float.random(in:-0.0001..<0.0001), randomScale)
                        }
                    }
                    
                    for fingerprintTextureEntity in fingerprintTextureEntities {
                        for _ in 0..<8 {
                            textureContainer.entity.addChild(fingerprintTextureEntity)
                            fingerprintTextureEntity.transform.translation = SIMD3<Float>.zero
                            fingerprintTextureEntity.transform.translation += SIMD3<Float>(Float.random(in: -1 * textureContainer.planeAnchor.geometry.extent.width / 2..<textureContainer.planeAnchor.geometry.extent.width / 2),Float.random(in:-0.0001..<0.0001),Float.random(in: -textureContainer.planeAnchor.geometry.extent.height / 2..<textureContainer.planeAnchor.geometry.extent.height / 2))
                            let randomScale = Float.random(in:0.2..<0.25)
                            fingerprintTextureEntity.transform.scale = SIMD3<Float>(randomScale, Float.random(in:-0.0001..<0.0001), randomScale)
                        }
                    }
                    
                    textureContainer.hasTextures = true
                }
            }
        }.onChange(of:sessionManager.deviceLocationTransform) { oldValue, newValue in
            skyboxEntity.transform.translation = newValue.translation
            skyboxEntity.transform.rotation = newValue.rotation - simd_quatf(angle:Float.pi/2, axis:SIMD3<Float>(0,1,0))
        }
    }
}

#Preview {
    ImmersiveView(audioModel:AudioModel())
        .previewLayout(.sizeThatFits)
}
