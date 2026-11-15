import Foundation

/// AppleSmartBattery에서 읽은 배터리 상태 스냅샷.
public struct BatteryInfo: Equatable, Sendable {
    public var percent: Int
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var cycleCount: Int
    public var temperatureCelsius: Double

    public init(percent: Int, isCharging: Bool, isPluggedIn: Bool, cycleCount: Int, temperatureCelsius: Double) {
        self.percent = percent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.cycleCount = cycleCount
        self.temperatureCelsius = temperatureCelsius
    }

    /// IORegistry 프로퍼티 딕셔너리를 변환한다. 필수 키가 없으면 nil.
    /// Apple Silicon에서 `CurrentCapacity`는 이미 0~100(%) 값이고, `Temperature`는 0.01°C 단위다.
    public init?(properties: [String: Any]) {
        guard
            let percent = (properties["CurrentCapacity"] as? NSNumber)?.intValue,
            let cycles = (properties["CycleCount"] as? NSNumber)?.intValue,
            let temp = (properties["Temperature"] as? NSNumber)?.doubleValue
        else { return nil }

        self.init(
            percent: min(max(percent, 0), 100),
            isCharging: (properties["IsCharging"] as? NSNumber)?.boolValue ?? false,
            isPluggedIn: (properties["ExternalConnected"] as? NSNumber)?.boolValue ?? false,
            cycleCount: cycles,
            temperatureCelsius: temp / 100.0
        )
    }
}
