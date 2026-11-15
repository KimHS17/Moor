import SwiftUI
import MoorCore

struct MenuBarLabel: View {
    let info: BatteryInfo?

    var body: some View {
        if let info {
            Label("\(info.percent)%", systemImage: info.isCharging ? "battery.100.bolt" : "battery.100")
        } else {
            Label("--", systemImage: "battery.0")
        }
    }
}

struct MenuContentView: View {
    @ObservedObject var model: BatteryViewModel

    var body: some View {
        if let info = model.info {
            Text("배터리: \(info.percent)%")
            Text("상태: \(statusText(info))")
            Text("사이클 수: \(info.cycleCount)")
            Text(String(format: "온도: %.1f°C", info.temperatureCelsius))
        } else {
            Text("배터리 정보를 읽을 수 없음")
        }
        Divider()
        Button("새로고침") { model.refresh() }
        Button("종료") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func statusText(_ info: BatteryInfo) -> String {
        if info.isCharging { return "충전 중" }
        return info.isPluggedIn ? "전원 연결됨 (충전 안 함)" : "배터리 사용 중"
    }
}
