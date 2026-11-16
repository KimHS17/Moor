import Foundation

enum Watch {
    static let intervalMilliseconds = 200

    /// 예: `14:03:07.200  CH0B=02  CH0C=03`
    static func line(timestamp: String, readings: [(key: FourCC, value: String)]) -> String {
        ([timestamp] + readings.map { "\($0.key)=\($0.value)" }).joined(separator: "  ")
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    /// 화이트리스트 키를 200ms마다 읽어 출력한다. 읽기 전용이다.
    /// 읽기가 한 번이라도 실패하면 1을, 아니면 0을 돌려준다.
    static func run(
        smc: SMCAccess,
        seconds: Int,
        now: () -> Date = Date.init,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        log: (String) -> Void
    ) -> Int32 {
        let samples = seconds * 1000 / intervalMilliseconds + 1
        var failed = false

        for index in 0..<samples {
            if index > 0 { sleep(Double(intervalMilliseconds) / 1000) }
            let readings = ChargingWhitelist.keys.map { key -> (key: FourCC, value: String) in
                do {
                    return (key, hex(try smc.read(key).bytes))
                } catch {
                    failed = true
                    return (key, "오류(\(error))")
                }
            }
            log(line(timestamp: timestamp(now()), readings: readings))
        }
        return failed ? 1 : 0
    }
}
