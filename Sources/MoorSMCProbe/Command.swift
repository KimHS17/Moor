enum Command: Equatable {
    case read([FourCC])
    case enableCharging
    case disableCharging(revertAfter: Int?)

    static let revertAfterRange = 1...86_400

    /// SMC 쓰기를 하는 명령은 root로 실행해야 한다.
    var requiresRoot: Bool {
        switch self {
        case .read: return false
        case .enableCharging, .disableCharging: return true
        }
    }

    static let usage = """
        사용법:
          MoorSMCProbe read <KEY> [<KEY> ...]
          sudo MoorSMCProbe enable-charging
          sudo MoorSMCProbe disable-charging [--revert-after <초>]

          read             SMC 키의 타입, 크기, 값을 16진수로 출력한다. (읽기 전용)
                           예: MoorSMCProbe read CH0B CH0C
          enable-charging  CH0B, CH0C에 00을 써서 충전을 허용한다. (복구용, root 필요)
          disable-charging CH0B, CH0C에 02를 써서 충전을 차단한다. (root 필요)
                           --revert-after <초>  지정한 시간(1~86400초)이 지나거나
                           SIGINT/SIGTERM/SIGHUP을 받으면 00으로 복구한다.
                           옵션이 없으면 한 번 쓰고 끝나며, 차단은 enable-charging을
                           실행할 때까지 남는다.
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
        default:
            return .failure(UsageError(message: "알 수 없는 서브커맨드 '\(name)'"))
        }
    }
}
