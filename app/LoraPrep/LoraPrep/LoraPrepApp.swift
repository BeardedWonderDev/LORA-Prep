//
//  LoraPrepApp.swift
//  LoraPrep
//
//  Created by Brian Pistone on 10/28/25.
//

import SwiftUI

@main
struct LoraPrepApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var model: AppState

    init() {
        let store = SettingsStore()
        _settings = StateObject(wrappedValue: store)
        _model = StateObject(wrappedValue: AppState(settings: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(settings)
        }
        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(settings)
        }
    }
}
