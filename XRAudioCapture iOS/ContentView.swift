//
//  ContentView.swift
//  XRAudioCapture iOS
//
//  Created by Michael A Edgcumbe on 2/3/24.
//

import SwiftUI
import RealityKit
import PHASE

struct ContentView : View {
    public let audioModel = AudioModel()
    public var viewContainer = ARViewContainer()
    var body: some View {
        viewContainer.edgesIgnoringSafeArea(.all)
            .task {
                do{
                    #if os(iOS)
                    viewContainer.arView.session.delegate = audioModel
                    #endif
                    
                    
                    var events = [PHASESoundEvent]()
                    let listener = audioModel.listeners[0]
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
                } catch {
                    print(error)
                }
            }
            .onDisappear(perform: {
                audioModel.phaseEngine.stop()
            })
    }
}

struct ARViewContainer: UIViewRepresentable {
    let arView = ARView(frame: .zero)
    func makeUIView(context: Context) -> ARView {

        // Create a cube model
        let mesh = MeshResource.generateBox(size: 0.1, cornerRadius: 0.005)
        let material = SimpleMaterial(color: .gray, roughness: 0.15, isMetallic: true)
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.transform.translation.y = 0.05

        // Create horizontal plane anchor for the content
        let anchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: SIMD2<Float>(0.2, 0.2)))
        anchor.children.append(model)

        // Add the horizontal plane anchor to the scene
        arView.scene.anchors.append(anchor)

        return arView
        
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
}

#Preview {
    ContentView()
}
