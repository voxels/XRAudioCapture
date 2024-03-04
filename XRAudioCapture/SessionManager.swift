//
//  SessionManager.swift
//  BodyTrackingVisualization
//
//  Created by Michael A Edgcumbe on 3/1/24.
//

import Foundation
import ARKit
import RealityKit
import QuartzCore
import SwiftUI

public class TextureContainer {
    let id:UUID
    let planeAnchor:PlaneAnchor
    var entity:Entity
    var hasTextures:Bool
    
    public init(id: UUID, planeAnchor:PlaneAnchor, entity: Entity, hasTextures: Bool) {
        self.id = id
        self.planeAnchor = planeAnchor
        self.entity = entity
        self.hasTextures = hasTextures
    }
}

open class SessionManager: ObservableObject {
    public let planeTracking:PlaneDetectionProvider = PlaneDetectionProvider(alignments: [.horizontal, .vertical])
    public let worldTracking:WorldTrackingProvider = WorldTrackingProvider()
    private let handTracking:HandTrackingProvider = HandTrackingProvider()
    var arkitSession = ARKitSession()
    var providersStoppedWithError = false
    var worldSensingAuthorizationStatus = ARKitSession.AuthorizationStatus.notDetermined
    var handTrackingAuthorizationStatus = ARKitSession.AuthorizationStatus.notDetermined
    
    
    public let originLocation:Entity = Entity()
    @Published public var deviceLocation: Entity = Entity()
    @Published public var leftHandLocation:Entity = Entity()
    @Published public var rightHandLocation:Entity = Entity()
    @Published public var ceilingLocations:[Entity] = []
    @Published public var floorLocations:[Entity] = []
    @Published public var wallLocations:[Entity] = []
    @Published public var furnitureLocations:[Entity] = []
    @Published public var deviceLocationTransform = Transform.identity
    
    private var joinCeilingLocations:[Entity] = []
    private var joinWallLocations:[Entity] = []
    private var joinFloorLocations:[Entity] = []
    private var joinFurnitureLocations:[Entity] = []

    
    public var displayLinkTimestamp:Double = 0
    public var lastFrameDisplayLinkTimestamp:Double = 0
    private var displayLink:CADisplayLink!
    
    var entityMap: [UUID: Entity] = [:]
    var entityIdentities:[Entity:UUID] = [:]
    var textureContainers:[UUID:TextureContainer] = [:]
    
    var allRequiredAuthorizationsAreGranted: Bool {
        worldSensingAuthorizationStatus == .allowed
    }
    
    var allRequiredProvidersAreSupported: Bool {
        WorldTrackingProvider.isSupported
    }
    
    var canEnterImmersiveSpace: Bool {
        allRequiredAuthorizationsAreGranted && allRequiredProvidersAreSupported
    }
    
    public init() {
        createDisplayLink()
    }
    
    func requestWorldSensingAuthorization() async {
        print("request authorization")
        let authorizationResult = await arkitSession.requestAuthorization(for: [.worldSensing])
        worldSensingAuthorizationStatus = authorizationResult[.worldSensing]!
    }
    
    func requestHandsTrackingAuthorization() async {
        let authorizationResult = await arkitSession.requestAuthorization(for: [.handTracking])
        handTrackingAuthorizationStatus = authorizationResult[.handTracking]!
    }
    
    func queryWorldSensingAuthorization() async {
        let authorizationResult = await arkitSession.queryAuthorization(for: [.worldSensing])
        worldSensingAuthorizationStatus = authorizationResult[.worldSensing]!
    }
    
    func queryHandTrackingAuthorization() async {
        let authorizationResult = await arkitSession.queryAuthorization(for: [.handTracking])
        handTrackingAuthorizationStatus = authorizationResult[.worldSensing]!
    }
    
    
    func monitorSessionEvents() async {
        for await event in arkitSession.events {
            switch event {
            case .dataProviderStateChanged(_, let newState, let error):
                switch newState {
                case .initialized:
                    break
                case .running:
                    break
                case .paused:
                    break
                case .stopped:
                    if let error {
                        print("An error occurred: \(error)")
                        providersStoppedWithError = true
                    }
                @unknown default:
                    break
                }
            case .authorizationChanged(let type, let status):
                print("Authorization type \(type) changed to \(status)")
                if type == .worldSensing {
                    worldSensingAuthorizationStatus = status
                }
                if type == .handTracking {
                    handTrackingAuthorizationStatus = status
                }
            default:
                print("An unknown event occured \(event)")
            }
        }
    }
    
    @MainActor
    func runARKitSession() async {
        print("run session")
        
        do {
            // Run a new set of providers every time when entering the immersive space.
            try await arkitSession.run([worldTracking, planeTracking])
        } catch {
            print(error)
            return
        }
        
        
    }
    
    @MainActor
    func processDeviceAnchorUpdates() async {
        await run(function: self.queryAndProcessLatestAnchors, withFrequency: 90)
    }
    
    @MainActor
    private func queryAndProcessLatestAnchors() async {
        // Device anchors are only available when the provider is running.
        guard worldTracking.state == .running else { return }
        
        let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
        
        if let deviceAnchor, deviceAnchor.isTracked  {
            updateDevicePlacementLocation(deviceAnchor)
        }
        

        let currentUpdates = planeTracking.anchorUpdates
        
            
        for await latestUpdate in currentUpdates {
            joinCeilingLocations.removeAll()
            joinWallLocations.removeAll()
            joinFloorLocations.removeAll()
            joinFurnitureLocations.removeAll()
            
            var newCeilingLocations:[Entity] = []
            var newWallLocations:[Entity] = []
            var newFloorLocations:[Entity] = []
            var newFurnitureLocations:[Entity] = []
            
            switch latestUpdate.event {
            case .added:
                fallthrough
            case .updated:
                updatePlane(latestUpdate.anchor, update:latestUpdate)
            case .removed:
                removePlane(latestUpdate.anchor)
            }
            
            let entity = entityMap[latestUpdate.anchor.id]
            if let entity = entity {
                
                if latestUpdate.anchor.classification == .ceiling {
                    newCeilingLocations.append(entity)
                } else if latestUpdate.anchor.classification == .wall {
                    newWallLocations.append(entity)
                } else if latestUpdate.anchor.classification == .floor {
                    newFloorLocations.append(entity)
                } else if latestUpdate.anchor.classification == .table || latestUpdate.anchor.classification == .table {
                    newFurnitureLocations.append(entity)
                }
                for location in newCeilingLocations {
                    if !ceilingLocations.contains(location) {
                        joinCeilingLocations.append(location)
                    }
                }
                
                for location in newWallLocations {
                    if !wallLocations.contains(location) {
                        joinWallLocations.append(location)
                    }
                }
                
                for location in newFloorLocations {
                    if !floorLocations.contains(location) {
                        joinFloorLocations.append(location)
                    }
                }
                
                for location in newFurnitureLocations {
                    if !furnitureLocations.contains(location) {
                        joinFurnitureLocations.append(location)
                    }
                }
                
                
                ceilingLocations.append(contentsOf: joinCeilingLocations)
                wallLocations.append(contentsOf:joinWallLocations)
                floorLocations.append(contentsOf:joinFloorLocations)
                furnitureLocations.append(contentsOf:joinFurnitureLocations)
            }
        }
    }
    
    func updatePlane(_ anchor: PlaneAnchor, update:AnchorUpdate<PlaneAnchor>) {
        if entityMap[anchor.id] == nil {
            let entity = Entity()
            entity.setTransformMatrix(anchor.originFromAnchorTransform, relativeTo: nil)
            entity.name = UUID().uuidString
            entityMap[anchor.id] = entity
            entityIdentities[entity] = anchor.id
            originLocation.addChild(entity)
            
            let textureContainer = TextureContainer(id:anchor.id, planeAnchor:anchor, entity:entity, hasTextures:false)
            textureContainers[anchor.id] = textureContainer
        } else if let entity = entityMap[anchor.id] {
            entity.setTransformMatrix(anchor.originFromAnchorTransform, relativeTo: nil)
            textureContainers[anchor.id]?.entity = entity
        }
    }
    
    func removePlane(_ anchor: PlaneAnchor) {

        if let entity = entityMap[anchor.id] {
            
            for child in entity.children {
                child.removeFromParent()
            }
            
            entityIdentities.removeValue(forKey: entity)
            
            if ceilingLocations.contains(entity) {
                ceilingLocations.removeAll { containedEntity in
                    containedEntity == entity
                }
            }
            if wallLocations.contains(entity) {
                wallLocations.removeAll { containedEntity in
                    containedEntity == entity
                }
            }
            
            if floorLocations.contains(entity) {
                floorLocations.removeAll { containedEntity in
                    containedEntity == entity
                }
            }
            
            if furnitureLocations.contains(entity) {
                furnitureLocations.removeAll { containedEntity in
                    containedEntity == entity
                }
            }
        }
        textureContainers.removeValue(forKey: anchor.id)
        entityMap.removeValue(forKey: anchor.id)
        entityMap[anchor.id]?.removeFromParent()

    }
    
    
    @MainActor
    private func updateDevicePlacementLocation(_ deviceAnchor: DeviceAnchor)  {
        deviceLocation.transform = Transform(matrix: deviceAnchor.originFromAnchorTransform)
        deviceLocationTransform = deviceLocation.transform
    }
    
    @MainActor
    private func updateLeftHandPlacementLocation(_ handAnchor: HandAnchor)  {
        leftHandLocation.transform = Transform(matrix: handAnchor.originFromAnchorTransform)
    }
    
    @MainActor
    private func updateRightHandPlacementLocation(_ handAnchor: HandAnchor)  {
        rightHandLocation.transform = Transform(matrix: handAnchor.originFromAnchorTransform)
    }
}


extension SessionManager {
    /// Run a given function at an approximate frequency.
    ///
    /// > Note: This method doesn’t take into account the time it takes to run the given function itself.
    @MainActor
    func run(function: () async -> Void, withFrequency hz: UInt64) async {
        while true {
            if Task.isCancelled {
                return
            }
            
            // Sleep for 1 s / hz before calling the function.
            let nanoSecondsToSleep: UInt64 = NSEC_PER_SEC / hz
            do {
                try await Task.sleep(nanoseconds: nanoSecondsToSleep)
            } catch {
                // Sleep fails when the Task is cancelled. Exit the loop.
                return
            }
            
            await function()
        }
    }
}

extension SessionManager {
    private func createDisplayLink() {
        displayLink = CADisplayLink(target: self, selector:#selector(onFrame(link:)))
        displayLink.add(to: .main, forMode: .default)
    }
}


extension SessionManager {
    
    @objc func onFrame(link:CADisplayLink) {
        if lastFrameDisplayLinkTimestamp + link.duration + 2 < link.timestamp  {
            Task { @MainActor in
                await processDeviceAnchorUpdates()
                lastFrameDisplayLinkTimestamp = displayLinkTimestamp
            }
        }

        displayLinkTimestamp = link.timestamp
    }
}

