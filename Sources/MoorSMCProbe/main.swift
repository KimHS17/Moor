import Foundation

private func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func openSMC() -> SMCConnection? {
    do {
        return try SMCConnection()
    } catch {
        printError("오류: \(error)")
        return nil
    }
}

private func run(_ command: Command) -> Int32 {
    // 쓰기 명령은 SMC를 열기 전에 권한부터 확인한다.
    if command.requiresRoot && geteuid() != 0 {
        printError("오류: 이 명령은 root 권한이 필요함. sudo로 직접 실행할 것")
        return 1
    }

    guard let smc = openSMC() else { return 1 }

    switch command {
    case .read(let keys):
        var failed = false
        for key in keys {
            do {
                print(try smc.read(key).formatted)
            } catch {
                printError("오류: \(error)")
                failed = true
            }
        }
        return failed ? 1 : 0

    case .enableCharging:
        let controller = ChargingController(smc: smc, log: { print($0) })
        do {
            try controller.enableCharging()
            return 0
        } catch {
            printError("실패: \(error)")
            return 1
        }
    }
}

switch Command.parse(Array(CommandLine.arguments.dropFirst())) {
case .success(let command):
    exit(run(command))
case .failure(let error):
    printError("오류: \(error.message)\n\n\(Command.usage)")
    exit(2)
}
