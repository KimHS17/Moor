import Foundation
import MoorCore

@MainActor
final class BatteryViewModel: ObservableObject {
    @Published private(set) var info: BatteryInfo?

    private let reader: BatteryReading
    private var timer: Timer?

    init(reader: BatteryReading = IOKitBatteryReader(), interval: TimeInterval = 30) {
        self.reader = reader
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        info = reader.read()
    }
}
