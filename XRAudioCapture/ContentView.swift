//
//  ContentView.swift
//  XRAudioCapture
//
//  Created by Michael A Edgcumbe on 2/1/24.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {

    @State private var showImmersiveSpace = false
    @State private var immersiveSpaceIsShown = false

    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace    
    
    var body: some View {
            VStack (spacing: 12) {
                Button {
                    showImmersiveSpace.toggle()
                } label: {
                    Label("Immersive Space", systemImage: "visionpro")
                }
            }
            .padding(36)
        .onChange(of: showImmersiveSpace) { _, newValue in
            Task {
                if newValue {
                    switch await openImmersiveSpace(id: "ImmersiveSpace") {
                    case .opened:
                        immersiveSpaceIsShown = true
                    case .error, .userCancelled:
                        fallthrough
                    @unknown default:
                        immersiveSpaceIsShown = false
                        showImmersiveSpace = false
                    }
                } else if immersiveSpaceIsShown {
                    await dismissImmersiveSpace()
                    immersiveSpaceIsShown = false
                }
            }
        }
    }
}

#Preview(windowStyle: .plain) {
    ContentView()
}
