enum Command: Equatable {
    case read([FourCC])

    static let usage = """
        사용법: MoorSMCProbe read <KEY> [<KEY> ...]

          read   SMC 키의 타입, 크기, 값을 16진수로 출력한다. (읽기 전용)
                 예: MoorSMCProbe read CH0B CH0C
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
        default:
            return .failure(UsageError(message: "알 수 없는 서브커맨드 '\(name)'"))
        }
    }
}
