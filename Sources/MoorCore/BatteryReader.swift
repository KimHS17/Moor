import Foundation
import IOKit

public protocol BatteryReading: Sendable {
    func read() -> BatteryInfo?
}

/// IOKit의 AppleSmartBattery 서비스에서 배터리 정보를 읽는다. (읽기 전용)
public struct IOKitBatteryReader: BatteryReading {
    public init() {}

    public func read() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard
            IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let dict = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return nil }

        return BatteryInfo(properties: dict)
    }
}
