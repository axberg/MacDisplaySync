import Foundation

@main
enum MonitorSensorProbe {
    static func main() throws {
        var result: [String: Any] = [
            "nightShiftSupported": NightShiftReader.isSupported
        ]
        if let builtIn = BuiltInDisplayReader.activeSample() {
            result["builtInActive"] = true
            result["displayID"] = builtIn.displayID
            result["brightness"] = builtIn.brightness
        } else {
            result["builtInActive"] = false
        }
        if let nightShift = NightShiftReader.sample() {
            result["nightShiftWarm"] = nightShift.isWarm
            result["nightShiftStrength"] = nightShift.strength
        }
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
