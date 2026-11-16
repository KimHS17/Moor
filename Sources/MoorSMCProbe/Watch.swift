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

    /// 화이트리스트 키를 한 번씩 읽는다. 읽지 못한 키의 값은 nil이고, 줄에는 오류 내용이 들어간다.
    static func sample(smc: SMCAccess, now: () -> Date = Date.init) -> (line: String, values: [[UInt8]?]) {
        var values: [[UInt8]?] = []
        let readings = ChargingWhitelist.keys.map { key -> (key: FourCC, value: String) in
            do {
                let bytes = try smc.read(key).bytes
                values.append(bytes)
                return (key, hex(bytes))
            } catch {
                values.append(nil)
                return (key, "오류(\(error))")
            }
        }
        return (line(timestamp: timestamp(now()), readings: readings), values)
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
            let sample = sample(smc: smc, now: now)
            if sample.values.contains(where: { $0 == nil }) { failed = true }
            log(sample.line)
        }
        return failed ? 1 : 0
    }
}
