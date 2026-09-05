//
//  MiniAppApp.swift
//  MiniApp
//
//  Created by Kazuki Nakashima on 2026/05/02.
//

import SwiftUI

@main
struct MiniAppApp: App {
    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            ContentView()
            #else
            UIKitNavigationDemo()
            #endif
        }
    }
}
