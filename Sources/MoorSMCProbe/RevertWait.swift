import Foundation

enum WaitOutcome: Equatable {
    case timeout
    case signal(Int32)
}

/// 충전을 차단하고, `revertAfter`가 있으면 `wait`가 돌아온 뒤 충전 허용으로 복구한다.
/// 종료 코드를 돌려준다: 성공 0, 시그널로 끝나 복구했으면 128+시그널 번호, 실패 1.
func runDisable(
    controller: ChargingController,
    revertAfter: Int?,
    wait: (Int) -> WaitOutcome
) -> Int32 {
    do {
        try controller.disableCharging()
    } catch {
        controller.log("실패: \(error)")
        return 1
    }

    guard let revertAfter else {
        controller.log("주의: 차단은 enable-charging을 실행할 때까지 남음")
        return 0
    }

    controller.log("\(revertAfter)초 뒤 또는 SIGINT/SIGTERM/SIGHUP을 받으면 충전 허용으로 복구함")
    let outcome = wait(revertAfter)
    switch outcome {
    case .timeout: controller.log("시간이 지나 복구를 시작함")
    case .signal(let number): controller.log("시그널 \(number)을 받아 복구를 시작함")
    }

    do {
        try controller.enableCharging()
    } catch {
        controller.log("복구 실패: \(error). enable-charging을 직접 실행할 것")
        return 1
    }

    if case .signal(let number) = outcome { return 128 + number }
    return 0
}

/// SIGINT/SIGTERM/SIGHUP을 기다린다. 만들어진 순간부터 시그널을 기록하므로,
/// `wait`를 부르기 전에 받은 시그널도 놓치지 않는다. SIGKILL은 잡을 수 없다.
final class SignalWaiter {
    private static let signals = [SIGINT, SIGTERM, SIGHUP]

    private let queue = DispatchQueue(label: "moor.smcprobe.signals")
    private let semaphore = DispatchSemaphore(value: 0)
    private var sources: [DispatchSourceSignal] = []
    private var received: Int32?

    init() {
        for number in Self.signals {
            // 기본 동작(즉시 종료)을 끄고 디스패치 소스로만 받는다.
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { [weak self] in
                guard let self, self.received == nil else { return }
                self.received = number
                self.semaphore.signal()
            }
            source.resume()
            sources.append(source)
        }
    }

    deinit {
        for source in sources { source.cancel() }
        for number in Self.signals { signal(number, SIG_DFL) }
    }

    /// 벽시계 기준으로 기다리므로 잠자기 시간도 포함된다.
    func wait(seconds: Int) -> WaitOutcome {
        _ = semaphore.wait(wallTimeout: .now() + .seconds(seconds))
        return queue.sync { received.map(WaitOutcome.signal) ?? .timeout }
    }
}
