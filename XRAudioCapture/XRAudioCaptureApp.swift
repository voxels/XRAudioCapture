//
//  XRAudioCaptureApp.swift
//  XRAudioCapture
//
//  Created by Michael A Edgcumbe on 2/1/24.
//

import SwiftUI

@main
struct XRAudioCaptureApp: App {
    @StateObject private var audioModel = AudioModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }.windowResizability(.contentSize)

        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveView(audioModel:audioModel)
        }.immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
