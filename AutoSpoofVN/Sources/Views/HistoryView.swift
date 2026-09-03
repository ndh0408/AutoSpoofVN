import SwiftUI

/// Lịch sử mô phỏng — xem lại và phát lại các phiên trước.
struct HistoryView: View {
    @StateObject private var history = HistoryManager.shared
    @StateObject private var replay = ReplayEngine.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if history.records.isEmpty {
                    EmptyStateView(
                        icon: "clock.arrow.circlepath",
                        title: "Chưa có lịch sử",
                        message: "Các phiên mô phỏng sẽ được ghi lại tự động."
                    )
                } else {
                    List {
                        if replay.isPlaying {
                            Section("Đang phát lại") {
                                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                    HStack {
                                        StatusBadge("Phát lại", color: .purple, icon: "arrow.counterclockwise")
                                        Spacer()
                                        Text("\(Int(replay.playbackSpeed))x")
                                            .font(AppFont.mono)
                                    }
                                    ProgressView(value: replay.progress)
                                    HStack {
                                        Button("1x") { replay.playbackSpeed = 1 }
                                        Button("5x") { replay.playbackSpeed = 5 }
                                        Button("10x") { replay.playbackSpeed = 10 }
                                        Spacer()
                                        Button("Dừng", role: .destructive) { replay.stop() }
                                    }
                                    .font(AppFont.footnote.weight(.medium))
                                }
                            }
                        }

                        // Group by date
                        let grouped = Dictionary(grouping: history.records) { record in
                            Calendar.current.startOfDay(for: record.startedAt)
                        }
                        let sortedDates = grouped.keys.sorted(by: >)

                        ForEach(sortedDates, id: \.self) { date in
                            Section(dateHeader(date)) {
                                ForEach(grouped[date] ?? []) { record in
                                    HistoryRow(record: record) {
                                        replay.play(record: record)
                                    }
                                }
                                .onDelete { indices in
                                    let records = grouped[date] ?? []
                                    for i in indices {
                                        history.deleteRecord(id: records[i].id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lịch sử")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") { dismiss() }
                }
                if !history.records.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Xoá tất cả", role: .destructive) { history.clearAll() }
                            .font(AppFont.footnote)
                    }
                }
            }
        }
    }

    private func dateHeader(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Hôm nay" }
        if Calendar.current.isDateInYesterday(date) { return "Hôm qua" }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }
}

struct HistoryRow: View {
    let record: SimulationRecord
    let onReplay: () -> Void

    var body: some View {
        HStack {
            Image(systemName: record.source.icon)
                .font(.title3)
                .foregroundStyle(AppColor.primary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(record.routeName ?? record.source.displayName)
                    .font(AppFont.body)
                HStack(spacing: AppSpacing.sm) {
                    Text(timeString(record.startedAt))
                        .font(AppFont.caption)
                    Text("•")
                        .foregroundStyle(AppColor.textTertiary)
                    Text(distanceString(record.distanceMeters))
                        .font(AppFont.caption)
                    Text("•")
                        .foregroundStyle(AppColor.textTertiary)
                    Text(durationString(record.durationSeconds))
                        .font(AppFont.caption)
                }
                .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            if record.replayData != nil {
                Button(action: onReplay) {
                    Image(systemName: "play.circle")
                        .font(.title3)
                        .foregroundStyle(AppColor.primary)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private func timeString(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    private func distanceString(_ meters: Double) -> String {
        meters > 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters)
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        return m > 60 ? String(format: "%dh%02dm", m/60, m%60) : "\(m) phút"
    }
}
