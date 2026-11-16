enum Command: Equatable {
    case read([FourCC])
    case watch(seconds: Int)
    case enableCharging
    case disableCharging(revertAfter: Int?)
    case set(SetPlan)

    static let revertAfterRange = 1...86_400
    static let watchSecondsRange = 1...3_600

    /// SMC 쓰기를 하는 명령은 root로 실행해야 한다.
    var requiresRoot: Bool {
        switch self {
        case .read, .watch: return false
        case .enableCharging, .disableCharging, .set: return true
        }
    }

    static let usage = """
        사용법:
          MoorSMCProbe read <KEY> [<KEY> ...]
          MoorSMCProbe watch --seconds <초>
          sudo MoorSMCProbe enable-charging
          sudo MoorSMCProbe disable-charging [--revert-after <초>]
          sudo MoorSMCProbe set <B값> <C값|-> [--order bc|cb] --hold <초>

          read             SMC 키의 타입, 크기, 값을 16진수로 출력한다. (읽기 전용)
                           예: MoorSMCProbe read CH0B CH0C
          watch            CH0B, CH0C를 200ms마다 읽어 시각과 함께 출력한다. (읽기 전용, 1~3600초)
          enable-charging  CH0B, CH0C에 00을 써서 충전을 허용한다. (복구용, root 필요)
          disable-charging CH0B, CH0C에 02를 써서 충전을 차단한다. (root 필요)
                           --revert-after <초>  지정한 시간(1~86400초)이 지나거나
                           SIGINT/SIGTERM/SIGHUP을 받으면 00으로 복구한다.
                           옵션이 없으면 한 번 쓰고 끝나며, 차단은 enable-charging을
                           실행할 때까지 남는다.
          set              실험용. CH0B에 <B값>, CH0C에 <C값>을 쓴다. (root 필요)
                           값은 00 또는 02만 받고, C값이 - 이면 CH0C는 쓰지 않는다.
                           --order bc|cb  쓰는 순서 (기본 bc: CH0B 먼저)
                           --hold <초>    유지 시간(1~120초, 필수). 그동안 200ms마다 값을
                           출력하고, 끝나면 두 키에 00을 써서 00/00이 될 때까지 출력한다.
                           시그널, 오류, 정상 종료 모두에서 00으로 복구한다.
        """
}

struct UsageError: Error, Equatable {
    let message: String
}

extension Command {
    /// 실행 파일 이름을 뺀 인자 목록을 해석한다.
    static func parse(_ arguments: [String]) -> Result<Command, UsageError> {
        guard let name = arguments.first else {
            return .failure(UsageError(message: "서브커맨드가 필요함"))
        }
        let rest = Array(arguments.dropFirst())

        switch name {
        case "read":
            guard !rest.isEmpty else {
                return .failure(UsageError(message: "read: 키를 하나 이상 지정해야 함"))
            }
            var keys: [FourCC] = []
            for argument in rest {
                guard let key = FourCC(argument) else {
                    return .failure(UsageError(message: "read: 잘못된 키 '\(argument)' (ASCII 4글자여야 함)"))
                }
                keys.append(key)
            }
            return .success(.read(keys))
        case "watch":
            guard rest.count == 2, rest[0] == "--seconds" else {
                return .failure(UsageError(message: "watch: --seconds <초>가 필요함"))
            }
            guard let seconds = Int(rest[1]), watchSecondsRange.contains(seconds) else {
                return .failure(UsageError(message: "watch: --seconds는 1~3600 사이 정수여야 함"))
            }
            return .success(.watch(seconds: seconds))
        case "enable-charging":
            guard rest.isEmpty else {
                return .failure(UsageError(message: "enable-charging: 인자를 받지 않음"))
            }
            return .success(.enableCharging)
        case "disable-charging":
            if rest.isEmpty { return .success(.disableCharging(revertAfter: nil)) }
            guard rest.count == 2, rest[0] == "--revert-after" else {
                return .failure(UsageError(message: "disable-charging: 옵션은 --revert-after <초>만 받음"))
            }
            guard let seconds = Int(rest[1]), revertAfterRange.contains(seconds) else {
                return .failure(UsageError(message: "disable-charging: --revert-after는 1~86400 사이 정수여야 함"))
            }
            return .success(.disableCharging(revertAfter: seconds))
        case "set":
            return parseSet(rest)
        default:
            return .failure(UsageError(message: "알 수 없는 서브커맨드 '\(name)'"))
        }
    }

    private static func chargingValue(_ text: String) -> ChargingValue? {
        switch text {
        case "00": return .allow
        case "02": return .block
        default: return nil
        }
    }

    private static func parseSet(_ arguments: [String]) -> Result<Command, UsageError> {
        func fail(_ message: String) -> Result<Command, UsageError> {
            .failure(UsageError(message: "set: " + message))
        }

        guard arguments.count >= 2 else { return fail("<B값> <C값|->이 필요함") }
        guard let b = chargingValue(arguments[0]) else {
            return fail("B값은 00 또는 02만 허용함 ('\(arguments[0])')")
        }
        let c: ChargingValue?
        if arguments[1] == "-" {
            c = nil
        } else if let value = chargingValue(arguments[1]) {
            c = value
        } else {
            return fail("C값은 00, 02 또는 - 만 허용함 ('\(arguments[1])')")
        }

        var order: SetPlan.Order?
        var hold: Int?
        var index = 2
        while index < arguments.count {
            let option = arguments[index]
            guard index + 1 < arguments.count else { return fail("\(option)에 값이 필요함") }
            let value = arguments[index + 1]
            switch option {
            case "--order":
                guard order == nil, let parsed = SetPlan.Order(rawValue: value) else {
                    return fail("--order는 bc 또는 cb를 한 번만 받음")
                }
                order = parsed
            case "--hold":
                guard hold == nil, let seconds = Int(value), SetPlan.holdRange.contains(seconds) else {
                    return fail("--hold는 1~120 사이 정수를 한 번만 받음")
                }
                hold = seconds
            default:
                return fail("알 수 없는 옵션 '\(option)'")
            }
            index += 2
        }

        guard let hold else { return fail("--hold <초>는 필수임") }
        return .success(.set(SetPlan(b: b, c: c, order: order ?? .bc, holdSeconds: hold)))
    }
}
