import AppKit
import SwiftUI

@main
struct MacDisplaySyncApp: App {
    @StateObject private var store = MonitorStore()

    var body: some Scene {
        MenuBarExtra("MacDisplaySync", systemImage: "sun.max.fill") {
            MacDisplaySyncView(store: store)
                .onAppear { store.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

struct MacDisplaySyncView: View {
    @ObservedObject var store: MonitorStore
    @State private var powerConfirmation = false
    @State private var resetConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 360)
        .alert("Turn off this display?", isPresented: $powerConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Turn Off", role: .destructive) { store.set(0xD6, to: 4, debounce: false) }
        } message: {
            Text("MacDisplaySync cannot turn it back on after the DDC connection disappears. Use the monitor’s power control to wake it.")
        }
        .alert("Reset monitor settings?", isPresented: $resetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { store.set(0x04, to: 1, debounce: false) }
        } message: {
            Text("This restores the monitor’s factory settings, including picture and input preferences.")
        }
        .alert("Monitor command failed", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "display")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                if store.displays.count > 1 {
                    Picker("Display", selection: Binding(
                        get: { store.selectedDisplayID },
                        set: { store.selectDisplay($0) }
                    )) {
                        ForEach(store.displays) { display in
                            Text(display.name).tag(Optional(display.id))
                        }
                    }
                    .labelsHidden()
                } else {
                    Text(store.selectedDisplay?.name ?? "MacDisplaySync")
                        .font(.headline)
                }
                Text(store.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await store.refreshDisplays() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh controls")
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if store.displays.isEmpty && !store.isRefreshing {
            VStack(spacing: 10) {
                Image(systemName: "display.trianglebadge.exclamationmark")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("No DDC Display")
                    .font(.headline)
                Text("Connect a DDC/CI monitor directly over USB-C or DisplayPort.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(height: 280)
        } else {
            ScrollView {
                LazyVStack(spacing: 18) {
                    automationSection
                    featureSection("Picture", features: FeatureCatalog.display)
                    featureSection("Sound", features: FeatureCatalog.audio)
                    sourceSection
                    colorTemperatureSection
                    monitorMenuSection
                    featureSection("Color", features: FeatureCatalog.color)
                    featureSection("Position", features: FeatureCatalog.position)
                    powerSection
                    AdvancedControls(store: store)
                }
                .padding(14)
            }
            .frame(height: 500)
        }
    }

    private var automationSection: some View {
        ControlSection("Follow MacBook") {
            Toggle(isOn: Binding(
                get: { store.followBuiltInBrightness },
                set: { store.setFollowBuiltInBrightness($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Brightness", systemImage: "sensor.fill")
                    Text("Mirrors the sensor-adjusted built-in display")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: Binding(
                get: { store.followNightShiftWarmth },
                set: { store.setFollowNightShiftWarmth($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Color warmth", systemImage: "sun.horizon.fill")
                    Text("5000 K when Night Shift is warm; restores your preset")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!NightShiftReader.isSupported || store.readings[0x14] == nil)

            if store.followBuiltInBrightness || store.followNightShiftWarmth {
                HStack(spacing: 7) {
                    Image(systemName: store.builtInBrightnessPercent == nil
                          ? "pause.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(
                            store.builtInBrightnessPercent == nil ? Color.secondary : Color.green
                        )
                    Text(store.syncStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func featureSection(_ title: String, features: [MonitorFeature]) -> some View {
        let available = features.filter { store.readings[$0.code] != nil }
        if !available.isEmpty {
            ControlSection(title) {
                ForEach(available) { feature in
                    if let reading = store.readings[feature.code] {
                        switch feature.kind {
                        case .slider:
                            HardwareSlider(
                                feature: feature,
                                reading: reading,
                                onChange: { store.set(feature.code, to: $0) }
                            )
                            .disabled(feature.code == 0x10 && store.followBuiltInBrightness)
                        case let .toggle(on, off):
                            Toggle(isOn: Binding(
                                get: { store.readings[feature.code]?.current == on },
                                set: { store.set(feature.code, to: $0 ? on : off, debounce: false) }
                            )) {
                                Label(feature.name, systemImage: feature.symbol)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        if let standard = store.readings[0x60] {
            ControlSection("Input") {
                DiscretePicker(
                    title: "Source",
                    symbol: "rectangle.connected.to.line.below",
                    current: standard.current,
                    options: DiscreteCatalog.inputs,
                    onChange: { store.set(0x60, to: $0, debounce: false) }
                )
            }
        } else if let alternate = store.readings[0xF4] {
            ControlSection("Input") {
                DiscretePicker(
                    title: "Source",
                    symbol: "rectangle.connected.to.line.below",
                    current: alternate.current,
                    options: DiscreteCatalog.lgInputs,
                    onChange: { store.set(0xF4, to: $0, debounce: false, dataAddress: 0x50) }
                )
            }
        }
    }

    @ViewBuilder
    private var colorTemperatureSection: some View {
        if let reading = store.readings[0x14] {
            ControlSection("White Point") {
                DiscretePicker(
                    title: "Color temperature",
                    symbol: "thermometer.medium",
                    current: reading.current,
                    options: DiscreteCatalog.colorTemperatures,
                    onChange: { store.set(0x14, to: $0, debounce: false) }
                )
                .disabled(store.followNightShiftWarmth)
            }
        }
    }

    @ViewBuilder
    private var monitorMenuSection: some View {
        if let language = store.readings[0xCC] {
            ControlSection("Monitor Menu") {
                DiscretePicker(
                    title: "OSD language",
                    symbol: "character.bubble",
                    current: language.current,
                    options: DiscreteCatalog.osdLanguages,
                    onChange: { store.set(0xCC, to: $0, debounce: false) }
                )
                if let pbp = store.readings[0xD7] {
                    DiscretePicker(
                        title: "Picture by Picture",
                        symbol: "rectangle.split.2x1",
                        current: pbp.current,
                        options: DiscreteCatalog.pictureByPicture,
                        onChange: { store.set(0xD7, to: $0, debounce: false) }
                    )
                }
            }
        } else if let pbp = store.readings[0xD7] {
            ControlSection("Monitor Menu") {
                DiscretePicker(
                    title: "Picture by Picture",
                    symbol: "rectangle.split.2x1",
                    current: pbp.current,
                    options: DiscreteCatalog.pictureByPicture,
                    onChange: { store.set(0xD7, to: $0, debounce: false) }
                )
            }
        }
    }

    @ViewBuilder
    private var powerSection: some View {
        if store.readings[0xD6] != nil {
            ControlSection("Display") {
                HStack {
                    Label("Power", systemImage: "power")
                    Spacer()
                    Button("Turn Off…") { powerConfirmation = true }
                }
                HStack {
                    Label("Factory settings", systemImage: "arrow.counterclockwise")
                    Spacer()
                    Button("Reset…") { resetConfirmation = true }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Hardware DDC/CI")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct ControlSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 12) { content }
                .padding(12)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct HardwareSlider: View {
    let feature: MonitorFeature
    let reading: VCPReading
    let onChange: (Int) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Label(feature.name, systemImage: feature.symbol)
                Spacer()
                Text("\(reading.current)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(reading.current) },
                    set: { onChange(Int($0.rounded())) }
                ),
                in: 0...Double(max(reading.maximum, reading.current, 1)),
                step: 1
            )
            .accessibilityValue("\(reading.current) of \(reading.maximum)")
        }
    }
}

struct DiscretePicker: View {
    let title: String
    let symbol: String
    let current: Int
    let options: [DiscreteOption]
    let onChange: (Int) -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Picker(title, selection: Binding(get: { current }, set: onChange)) {
                if !options.contains(where: { $0.value == current }) {
                    Text(String(format: "Current (0x%02X)", current)).tag(current)
                }
                ForEach(options) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
        }
    }
}

struct AdvancedControls: View {
    @ObservedObject var store: MonitorStore
    @State private var expanded = false
    @State private var code = "0x10"
    @State private var value = ""
    @State private var address = "0x51"
    @State private var result = ""

    var body: some View {
        DisclosureGroup("Advanced VCP", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Send a raw MCCS command for vendor-specific controls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("Code", text: $code).frame(width: 72)
                    TextField("Value", text: $value).frame(width: 72)
                    TextField("Address", text: $address).frame(width: 72)
                }
                HStack {
                    Button("Read") { read() }
                    Button("Write") { write() }
                        .disabled(parse(value) == nil)
                    Spacer()
                    Text(result).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VCP Explorer")
                        Text("Scans all 256 hardware feature codes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.isScanningAll {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(store.scanResults.isEmpty ? "Scan" : "Scan Again") {
                            Task { await store.scanAllFeatures() }
                        }
                    }
                }
                if !store.scanResults.isEmpty {
                    Text("\(store.scanResults.count) readable features")
                        .font(.caption.weight(.medium))
                    ForEach(store.scanResults, id: \.code) { reading in
                        HStack(spacing: 8) {
                            Text(String(format: "0x%02X", reading.code))
                                .font(.caption.monospaced())
                                .frame(width: 38, alignment: .leading)
                            Text(VCPLabels.name(for: reading.code))
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text("\(reading.current) / \(reading.maximum)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.top, 10)
        }
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func parse(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("0x") {
            return Int(cleaned.dropFirst(2), radix: 16)
        }
        return Int(cleaned)
    }

    private func read() {
        guard let parsedCode = parse(code), (0...255).contains(parsedCode) else {
            result = "Invalid code"
            return
        }
        Task {
            if let reading = await store.readRaw(code: parsedCode) {
                value = String(reading.current)
                result = "max \(reading.maximum)"
            }
        }
    }

    private func write() {
        guard let parsedCode = parse(code), let parsedValue = parse(value),
              let parsedAddress = parse(address),
              (0...255).contains(parsedCode), (0...65535).contains(parsedValue),
              (0...255).contains(parsedAddress) else {
            result = "Invalid value"
            return
        }
        Task {
            result = await store.writeRaw(
                code: parsedCode, value: parsedValue, dataAddress: parsedAddress
            ) ? "Written" : "Failed"
        }
    }
}
