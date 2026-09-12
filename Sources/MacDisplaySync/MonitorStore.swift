import Foundation

@MainActor
final class MonitorStore: ObservableObject {
    @Published var displays: [MonitorDisplay] = []
    @Published var selectedDisplayID: String?
    @Published var readings: [Int: VCPReading] = [:]
    @Published var isRefreshing = false
    @Published var status = "Looking for displays…"
    @Published var errorMessage: String?
    @Published var scanResults: [VCPReading] = []
    @Published var isScanningAll = false
    @Published private(set) var followBuiltInBrightness: Bool
    @Published private(set) var followNightShiftWarmth: Bool
    @Published private(set) var syncStatus = "Off"
    @Published private(set) var builtInBrightnessPercent: Int?
    @Published private(set) var nightShiftDescription: String?

    private let client = DDCClient()
    private var pendingWrites: [Int: Task<Void, Never>] = [:]
    private var syncTimer: Timer?
    private var syncTickInProgress = false
    private var lastSyncedBrightness: Int?
    private var lastSyncedWarmth: Bool?
    private var savedNeutralPreset: Int?

    private enum PreferenceKey {
        static let followBrightness = "followBuiltInBrightness"
        static let followWarmth = "followNightShiftWarmth"
        static let savedNeutralPreset = "savedNeutralColorPreset"
    }

    init() {
        let defaults = UserDefaults.standard
        followBuiltInBrightness = defaults.bool(forKey: PreferenceKey.followBrightness)
        followNightShiftWarmth = defaults.bool(forKey: PreferenceKey.followWarmth)
        savedNeutralPreset = defaults.object(forKey: PreferenceKey.savedNeutralPreset) as? Int

        Task { @MainActor [weak self] in
            guard let self else { return }
            await refreshDisplays()
            configureSyncTimer()
        }
    }

    var selectedDisplay: MonitorDisplay? {
        if let selectedDisplayID,
           let selected = displays.first(where: { $0.id == selectedDisplayID }) {
            return selected
        }
        return displays.first
    }

    func start() {
        guard displays.isEmpty, !isRefreshing else { return }
        Task { await refreshDisplays() }
    }

    func setFollowBuiltInBrightness(_ enabled: Bool) {
        guard followBuiltInBrightness != enabled else { return }
        followBuiltInBrightness = enabled
        UserDefaults.standard.set(enabled, forKey: PreferenceKey.followBrightness)
        lastSyncedBrightness = nil
        configureSyncTimer()
        Task { await syncNow() }
    }

    func setFollowNightShiftWarmth(_ enabled: Bool) {
        guard followNightShiftWarmth != enabled else { return }
        if enabled, savedNeutralPreset == nil, let preset = readings[0x14]?.current {
            savedNeutralPreset = preset
            UserDefaults.standard.set(preset, forKey: PreferenceKey.savedNeutralPreset)
        }
        followNightShiftWarmth = enabled
        UserDefaults.standard.set(enabled, forKey: PreferenceKey.followWarmth)
        lastSyncedWarmth = nil
        configureSyncTimer()

        if enabled {
            Task { await syncNow() }
        } else {
            Task { await restoreNeutralPreset() }
        }
    }

    func refreshDisplays() async {
        isRefreshing = true
        readings = [:]
        status = "Finding DDC controls…"
        do {
            displays = try await client.displays()
            if selectedDisplay == nil { selectedDisplayID = displays.first?.id }
            guard let display = selectedDisplay else {
                status = "No controllable external display"
                isRefreshing = false
                return
            }

            var supported: [Int: VCPReading] = [:]
            for code in FeatureCatalog.probeCodes {
                if let value = try? await client.read(display: display.index, code: code) {
                    supported[code] = value
                    readings = supported
                }
            }
            status = supported.isEmpty
                ? "Connected, but no DDC controls responded"
                : "\(supported.count) hardware controls available"
            if followNightShiftWarmth, savedNeutralPreset == nil,
               let preset = supported[0x14]?.current {
                savedNeutralPreset = preset
                UserDefaults.standard.set(preset, forKey: PreferenceKey.savedNeutralPreset)
            }
        } catch {
            status = "Could not connect"
            errorMessage = error.localizedDescription
        }
        isRefreshing = false
        if followBuiltInBrightness || followNightShiftWarmth {
            await syncNow()
        }
    }

    func selectDisplay(_ id: String?) {
        selectedDisplayID = id
        Task { await refreshReadings() }
    }

    func refreshReadings() async {
        guard let display = selectedDisplay else { return }
        isRefreshing = true
        let knownCodes = readings.isEmpty ? FeatureCatalog.probeCodes : Array(readings.keys)
        var refreshed: [Int: VCPReading] = [:]
        for code in knownCodes {
            if let value = try? await client.read(display: display.index, code: code) {
                refreshed[code] = value
                readings = refreshed
            }
        }
        status = "\(refreshed.count) hardware controls available"
        isRefreshing = false
    }

    func set(_ code: Int, to value: Int, debounce: Bool = true, dataAddress: Int = 0x51) {
        guard let display = selectedDisplay else { return }

        if let old = readings[code] {
            readings[code] = VCPReading(code: code, current: value, maximum: old.maximum)
        }

        pendingWrites[code]?.cancel()
        pendingWrites[code] = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
            }
            do {
                try await client.write(
                    display: display.index,
                    code: code,
                    value: value,
                    dataAddress: dataAddress
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func readRaw(code: Int) async -> VCPReading? {
        guard let display = selectedDisplay else { return nil }
        do {
            return try await client.read(display: display.index, code: code)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func writeRaw(code: Int, value: Int, dataAddress: Int) async -> Bool {
        guard let display = selectedDisplay else { return false }
        do {
            try await client.write(
                display: display.index, code: code, value: value, dataAddress: dataAddress
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func scanAllFeatures() async {
        guard let display = selectedDisplay, !isScanningAll else { return }
        isScanningAll = true
        do {
            scanResults = try await client.scan(display: display.index)
        } catch {
            errorMessage = error.localizedDescription
        }
        isScanningAll = false
    }

    private func configureSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
        guard followBuiltInBrightness || followNightShiftWarmth else {
            syncStatus = "Off"
            builtInBrightnessPercent = nil
            nightShiftDescription = nil
            return
        }

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.syncNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer
    }

    private func syncNow() async {
        guard !syncTickInProgress,
              followBuiltInBrightness || followNightShiftWarmth else { return }
        syncTickInProgress = true
        defer { syncTickInProgress = false }

        guard let sample = BuiltInDisplayReader.activeSample() else {
            syncStatus = "Paused — MacBook display is off"
            builtInBrightnessPercent = nil
            nightShiftDescription = nil
            lastSyncedBrightness = nil
            lastSyncedWarmth = nil
            return
        }
        guard let display = selectedDisplay else {
            syncStatus = "Waiting for an external display"
            return
        }

        builtInBrightnessPercent = Int((sample.brightness * 100).rounded())
        var statusParts: [String] = []

        if followBuiltInBrightness, let brightness = readings[0x10] {
            let target = min(
                max(Int((sample.brightness * Float(brightness.maximum)).rounded()), 0),
                brightness.maximum
            )
            statusParts.append("Brightness \(builtInBrightnessPercent ?? target)%")
            if lastSyncedBrightness != target || brightness.current != target {
                do {
                    try await client.write(display: display.index, code: 0x10, value: target)
                    readings[0x10] = VCPReading(
                        code: 0x10, current: target, maximum: brightness.maximum
                    )
                    lastSyncedBrightness = target
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }

        if followNightShiftWarmth {
            if let nightShift = NightShiftReader.sample() {
                nightShiftDescription = nightShift.description
                statusParts.append(nightShift.isWarm ? "Warm" : "Neutral")
                let targetPreset = nightShift.isWarm ? 0x04 : (savedNeutralPreset ?? 0x05)
                if readings[0x14] != nil &&
                   (lastSyncedWarmth != nightShift.isWarm ||
                    readings[0x14]?.current != targetPreset) {
                    do {
                        try await client.write(
                            display: display.index, code: 0x14, value: targetPreset
                        )
                        readings[0x14] = VCPReading(
                            code: 0x14,
                            current: targetPreset,
                            maximum: readings[0x14]?.maximum ?? 0x0B
                        )
                        lastSyncedWarmth = nightShift.isWarm
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } else {
                nightShiftDescription = "Night Shift unavailable"
                statusParts.append("Warmth unavailable")
            }
        }

        syncStatus = statusParts.isEmpty
            ? "Waiting for supported controls"
            : statusParts.joined(separator: " · ")
    }

    private func restoreNeutralPreset() async {
        defer {
            savedNeutralPreset = nil
            lastSyncedWarmth = nil
            UserDefaults.standard.removeObject(forKey: PreferenceKey.savedNeutralPreset)
        }
        guard let preset = savedNeutralPreset, let display = selectedDisplay,
              readings[0x14] != nil else { return }
        do {
            try await client.write(display: display.index, code: 0x14, value: preset)
            readings[0x14] = VCPReading(
                code: 0x14, current: preset, maximum: readings[0x14]?.maximum ?? 0x0B
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
