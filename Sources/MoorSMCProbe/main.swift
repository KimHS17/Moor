import Foundation

private func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func run(_ command: Command) -> Int32 {
    switch command {
    case .read(let keys):
        let smc: SMCConnection
        do {
            smc = try SMCConnection()
        } catch {
            printError("오류: \(error)")
            return 1
        }

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
    }
}

switch Command.parse(Array(CommandLine.arguments.dropFirst())) {
case .success(let command):
    exit(run(command))
case .failure(let error):
    printError("오류: \(error.message)\n\n\(Command.usage)")
    exit(2)
}
