import AppKit
import SwiftUI

struct MenuBarExtraView: View {
    @EnvironmentObject private var appController: AppController
    @State private var projects: [Project] = []

    var body: some View {
        Group {
            if self.projects.isEmpty {
                Text("No Projects")
            } else {
                ForEach(self.projects.indices, id: \.self) { index in
                    let project = self.projects[index]

                    Button {
                        self.appController.runProject(project)
                    } label: {
                        Label("Run \(project.name)", systemImage: "play.fill")
                    }

                    if index == 0, self.projects.count > 1 {
                        Divider()
                    }
                }
            }

            Divider()

            Picker("Device", selection: self.$appController.selectedDevice) {
                Label("Run on iPhone", systemImage: "iphone")
                    .tag(AppController.Device.iPhone)

                Label("Run on iPad", systemImage: "ipad.landscape")
                    .tag(AppController.Device.iPad)
            }
            .pickerStyle(.inline)

            Divider()

            Button {
                self.appController.showMainWindow()
            } label: {
                Label("Show xDeploy", systemImage: "macwindow")
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit xDeploy", systemImage: "power")
            }
        }
        .onAppear {
            self.reload()
        }
    }

    private func reload() {
        let appData = DataManager.shared.load()
        self.projects = appData.projects
    }
}
