import Foundation

/// `set` 실험 한 번의 내용.
struct SetPlan: Equatable {
    enum Order: String, Equatable {
        case bc
        case cb
    }

    static let holdRange = 1...120

    /// CH0B에 쓸 값.
    let b: ChargingValue
    /// CH0C에 쓸 값. nil이면 CH0C는 쓰지 않는다.
    let c: ChargingValue?
    let order: Order
    let holdSeconds: Int

    /// 실제로 쓰는 순서대로 나열한 (키, 값).
    var writes: [(key: FourCC, value: ChargingValue)] {
        let keys = ChargingWhitelist.keys
        let pairs: [(key: FourCC, value: ChargingValue?)] = [(keys[0], b), (keys[1], c)]
        let ordered = order == .bc ? pairs : Array(pairs.reversed())
        return ordered.compactMap { pair in pair.value.map { (pair.key, $0) } }
    }
}

/// 실험용: 지정한 값을 지정한 순서로 쓰고, 유지 시간 동안 값을 출력한 뒤 반드시 00/00으로 복구한다.
/// 쓰기 결과를 검증해 실패 처리하지는 않는다(무엇이 읽히는지 보는 것이 목적이다).
enum SetExperiment {
    static let restoreTimeoutMilliseconds = 5_000

    /// `tick`은 주어진 밀리초만큼 기다리고, 그 사이 시그널을 받았으면 `.signal`을 돌려준다.
    /// 종료 코드: 정상 0, 시그널 뒤 복구했으면 128+시그널 번호, 오류나 복구 실패 1.
    static func run(
        smc: SMCAccess,
        plan: SetPlan,
        now: () -> Date = Date.init,
        tick: (Int) -> WaitOutcome,
        log: @escaping (String) -> Void
    ) -> Int32 {
        let interval = Watch.intervalMilliseconds
        let allow = ChargingValue.allow.rawValue
        var attemptedWrite = false
        var failed = false
        var signalNumber: Int32?

        func sample() -> [[UInt8]?] {
            let sample = Watch.sample(smc: smc, now: now)
            log(sample.line)
            return sample.values
        }

        do {
            try ChargingController(smc: smc, log: log, sleep: { _ in }).preflight()
            _ = sample()

            for write in plan.writes {
                log("쓰기 \(write.key) ← \(hex([write.value.rawValue]))")
                attemptedWrite = true
                try smc.write(write.key, bytes: [write.value.rawValue])
                _ = sample()
            }

            log("\(plan.holdSeconds)초 유지 (SIGINT/SIGTERM/SIGHUP을 받으면 바로 복구)")
            for _ in 0..<(plan.holdSeconds * 1000 / interval) {
                if case .signal(let number) = tick(interval) {
                    signalNumber = number
                    log("시그널 \(number)을 받아 복구를 시작함")
                    break
                }
                _ = sample()
            }
        } catch {
            log("오류: \(error)")
            failed = true
        }

        // 쓰기를 시도하기 전에 끝났으면(키가 없거나 크기가 다름) 아무것도 쓰지 않는다.
        guard attemptedWrite else { return failed ? 1 : 0 }

        log("복구: 두 키에 00을 씀")
        for key in ChargingWhitelist.keys {
            do {
                log("쓰기 \(key) ← \(hex([allow]))")
                try smc.write(key, bytes: [allow])
            } catch {
                log("오류: \(error)")
                failed = true
            }
            _ = sample()
        }

        var restored = false
        for attempt in 0...(restoreTimeoutMilliseconds / interval) {
            if attempt > 0 { _ = tick(interval) }   // 복구 중에는 시그널을 받아도 멈추지 않는다.
            if sample().allSatisfy({ $0 == [allow] }) {
                restored = true
                break
            }
        }

        guard restored else {
            log("복구 실패: \(restoreTimeoutMilliseconds)ms 동안 00/00이 되지 않음. enable-charging을 직접 실행할 것")
            return 1
        }
        log("복구 완료: 두 키 모두 00")
        if failed { return 1 }
        if let signalNumber { return 128 + signalNumber }
        return 0
    }
}
