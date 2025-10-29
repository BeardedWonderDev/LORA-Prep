//
//  ContentView.swift
//  LoraPrep
//
//  Created by Brian Pistone on 10/28/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppState()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            InputControlsView(model: model)

            HStack {
                Button {
                    model.startProcessing()
                } label: {
                    Label("Process Images", systemImage: "gearshape")
                }
                .disabled(!model.isReadyToProcess)
                .keyboardShortcut(.defaultAction)

                if model.isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Working…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            ResultsView(model: model)
        }
        .padding(24)
        .frame(minWidth: 960, minHeight: 640)
        .alert(item: $model.errorAlert) { item in
            Alert(title: Text("Error"),
                  message: Text(item.message),
                  dismissButton: .default(Text("OK")))
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 960, height: 640)
}
