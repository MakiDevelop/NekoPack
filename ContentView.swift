import SwiftUI

enum AppMode: String, CaseIterable {
    case compress = "壓縮"
    case extract = "解壓縮"
}

struct ContentView: View {
    @AppStorage("selectedAppearance") private var selectedAppearance: String = "light"
    @State private var currentMode: AppMode = .compress

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(0.1),
                    Color.purple.opacity(0.05)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack {
                        Text("NekoPack")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Spacer()

                        Picker("", selection: $selectedAppearance) {
                            Image(systemName: "sun.max").tag("light")
                            Image(systemName: "moon").tag("dark")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 80)
                    }

                    Picker("", selection: $currentMode) {
                        ForEach(AppMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 200)
                }
                .padding()

                switch currentMode {
                case .compress:
                    CompressView()
                case .extract:
                    ExtractView()
                }
            }
        }
        .frame(minWidth: 520, minHeight: 500)
        .preferredColorScheme(selectedAppearance == "dark" ? .dark : .light)
    }
}
