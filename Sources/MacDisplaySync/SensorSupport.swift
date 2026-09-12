import CoreGraphics
import Darwin
import Foundation
import ObjectiveC.runtime

struct BuiltInDisplaySample: Equatable {
    let displayID: CGDirectDisplayID
    let brightness: Float
}

/// Reads the value macOS currently applies to the built-in display. When
/// automatic brightness is enabled, this already includes the ambient-light
/// sensor's adjustment.
enum BuiltInDisplayReader {
    private typealias CanChangeFn = @convention(c) (UInt32) -> Bool
    private typealias GetBrightnessFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32

    private struct API {
        let canChange: CanChangeFn
        let getBrightness: GetBrightnessFn
    }

    private static let api: API? = {
        guard let library = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY
        ), let canChange = dlsym(library, "DisplayServicesCanChangeBrightness"),
           let getBrightness = dlsym(library, "DisplayServicesGetBrightness") else {
            return nil
        }
        return API(
            canChange: unsafeBitCast(canChange, to: CanChangeFn.self),
            getBrightness: unsafeBitCast(getBrightness, to: GetBrightnessFn.self)
        )
    }()

    static func activeSample() -> BuiltInDisplaySample? {
        guard let api else { return nil }
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(UInt32(displays.count), &displays, &count) == .success else {
            return nil
        }

        guard let displayID = displays.prefix(Int(count)).first(where: {
            CGDisplayIsBuiltin($0) != 0 && CGDisplayIsActive($0) != 0 && CGDisplayIsAsleep($0) == 0
        }), api.canChange(displayID) else {
            return nil
        }

        var brightness: Float = -1
        guard api.getBrightness(displayID, &brightness) == 0,
              brightness.isFinite, (0...1).contains(brightness) else {
            return nil
        }
        return BuiltInDisplaySample(displayID: displayID, brightness: brightness)
    }
}

struct NightShiftSample: Equatable {
    let isWarm: Bool
    let strength: Float

    var description: String {
        isWarm ? "Night Shift warm" : "Night Shift neutral"
    }
}

/// Best-effort, read-only access to macOS Night Shift. The LG cannot mirror
/// True Tone's continuously adapted white point, so the app follows Night
/// Shift's live on/off state using hardware color presets instead.
enum NightShiftReader {
    private static let client: NSObject? = {
        guard dlopen(
            "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
            RTLD_LAZY
        ) != nil, let type = NSClassFromString("CBBlueLightClient") as? NSObject.Type else {
            return nil
        }
        return type.init()
    }()

    private typealias GetStatusFn = @convention(c) (
        AnyObject, Selector, UnsafeMutableRawPointer
    ) -> Bool
    private typealias GetFloatFn = @convention(c) (
        AnyObject, Selector, UnsafeMutablePointer<Float>
    ) -> Bool

    private static func implementation<T>(_ selectorName: String, as type: T.Type) -> T? {
        guard let client,
              let method = class_getInstanceMethod(Swift.type(of: client), Selector(selectorName)) else {
            return nil
        }
        return unsafeBitCast(method_getImplementation(method), to: type)
    }

    static var isSupported: Bool {
        guard let client else { return false }
        return client.responds(to: Selector(("getBlueLightStatus:"))) &&
            client.responds(to: Selector(("getStrength:")))
    }

    static func sample() -> NightShiftSample? {
        guard isSupported, let client,
              let getStatus = implementation("getBlueLightStatus:", as: GetStatusFn.self),
              let getStrength = implementation("getStrength:", as: GetFloatFn.self) else {
            return nil
        }

        var status = [UInt8](repeating: 0, count: 64)
        let statusOK = status.withUnsafeMutableBytes {
            getStatus(client, Selector(("getBlueLightStatus:")), $0.baseAddress!)
        }
        guard statusOK else { return nil }

        var strength: Float = 0
        guard getStrength(client, Selector(("getStrength:")), &strength), strength.isFinite else {
            return nil
        }
        return NightShiftSample(
            isWarm: status[0] == 1 && status[1] == 1,
            strength: min(max(strength, 0), 1)
        )
    }
}
