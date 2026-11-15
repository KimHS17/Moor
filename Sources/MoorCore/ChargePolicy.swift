public enum ChargeDecision: Equatable, Sendable {
    case allow
    case block
}

/// 충전 허용/차단을 결정하는 순수 로직. 하드웨어를 건드리지 않는다.
public enum ChargePolicy {
    public static let defaultLimit = 55

    /// - `lowerLimit == upperLimit`: 단순 한도(상한 미만이면 충전, 이상이면 차단).
    /// - `lowerLimit < upperLimit`: 항해 모드. 두 값 사이에서는 현재 상태를 유지하므로
    ///   상한에서 멈춘 뒤 하한까지 내려가야 충전을 재개한다.
    /// - 입력이 이상하면 fail-safe로 충전을 허용한다.
    public static func decide(
        percent: Int,
        upperLimit: Int,
        lowerLimit: Int,
        isCharging: Bool
    ) -> ChargeDecision {
        let valid = 0...100
        guard
            valid.contains(percent), valid.contains(upperLimit), valid.contains(lowerLimit),
            lowerLimit <= upperLimit
        else { return .allow }

        if percent >= upperLimit { return .block }
        if percent <= lowerLimit { return .allow }
        return isCharging ? .allow : .block
    }
}
