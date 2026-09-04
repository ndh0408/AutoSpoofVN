//
//  LocationXWidgetsBundle.swift
//  LocationXWidgets
//
//  Live Activity & Dynamic Island cho LocationX.
//
//  Nguyen tac: widget KHONG tu viet chu tieng Viet/tieng Anh nao. Moi chuoi hien thi
//  deu do ung dung tinh san va truyen qua ContentState — target nay khong bien dich
//  LocalizationManager va khong co thu muc .lproj, nen chu viet cung o day se vinh vien
//  mot thu tieng du nguoi dung doi ngon ngu trong app.
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LocationXWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LocationXLiveActivity()
    }
}

// MARK: - Mau sac theo trang thai

private extension SpoofActivityAttributes.ContentState {
    /// Mau chu dao theo trang thai. Khong dung mot mau xanh cho moi truong hop:
    /// nguoi dung liec qua phai phan biet duoc dang chay / tam dung / da dung han.
    var tint: Color {
        if isHalted { return .orange }
        return isRunning ? .green : .yellow
    }

    var symbol: String {
        if isHalted { return "location.slash.fill" }
        if flightNumber != nil { return "airplane" }
        return isRunning ? "location.fill" : "pause.fill"
    }

    /// Dong tieu de phu: tuyen bay / ten tuyen duong, neu khong thi nguon dang chay.
    var subtitle: String {
        if let route = routeText, !route.isEmpty { return route }
        return activeSource
    }
}

// MARK: - Widget

struct LocationXLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpoofActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(context.state.tint)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(s.stateName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: s.symbol)
                            .foregroundStyle(s.tint)
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    MetricPair(value: Int(s.speedKmh).description, unit: "km/h", tint: s.tint)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let progress = s.flightProgress {
                            ProgressView(value: progress, total: 1)
                                .tint(s.tint)
                        }

                        HStack(spacing: 14) {
                            if let altitude = s.altitudeMeters, altitude > 0 {
                                InlineStat(symbol: "arrow.up.to.line",
                                           text: "\(Int(altitude)) m", tint: s.tint)
                            }
                            if let eta = s.etaText {
                                InlineStat(symbol: "clock", text: eta, tint: s.tint)
                            }
                            if let progressText = s.progressText, s.altitudeMeters == nil {
                                InlineStat(symbol: "chart.bar.fill", text: progressText, tint: s.tint)
                            }
                            Spacer(minLength: 0)
                        }
                        .font(.caption2)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                // Vung nay chi rong khoang 40pt. Nhoi ca icon lan chu vao day thi chu bi
                // cat con vai ky tu vo nghia — chi de mot bieu tuong.
                Image(systemName: s.symbol)
                    .foregroundStyle(s.tint)
            } compactTrailing: {
                // So khong don vi. Ban truoc ghi "42k" — de bi doc nham la 42 nghin.
                Text(Int(s.speedKmh).description)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(s.tint)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: s.symbol)
                    .foregroundStyle(s.tint)
            }
        }
    }
}

// MARK: - Man hinh khoa

private struct LockScreenView: View {
    let state: SpoofActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.stateName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(state.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                MetricPair(value: Int(state.speedKmh).description, unit: "km/h", tint: state.tint)
            }

            if let progress = state.flightProgress {
                VStack(spacing: 4) {
                    ProgressView(value: progress, total: 1)
                        .tint(state.tint)
                    HStack {
                        if let flightNo = state.flightNumber {
                            Text(flightNo)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let progressText = state.progressText {
                            Text(progressText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            footer
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: state.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(state.tint)

            Text(state.subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            // Chi bao trang thai: cham mau + CHU. Khong bao gio chi dua vao mau.
            HStack(spacing: 5) {
                Circle()
                    .fill(state.tint)
                    .frame(width: 7, height: 7)
                Text(state.statusLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(state.tint)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(state.tint.opacity(0.15)))
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            InlineStat(symbol: "mappin.and.ellipse", text: state.coordinateText, tint: state.tint)

            if let altitude = state.altitudeMeters, altitude > 0 {
                InlineStat(symbol: "arrow.up.to.line", text: "\(Int(altitude)) m", tint: state.tint)
            }
            if let eta = state.etaText {
                InlineStat(symbol: "clock", text: eta, tint: state.tint)
            }

            Spacer(minLength: 0)
        }
        .font(.caption2)
    }
}

// MARK: - Manh ghep dung chung

/// So lieu lon kem don vi. `monospacedDigit` de con so doi lien tuc khong lam nhay bo cuc.
private struct MetricPair: View {
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(unit)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// Mot so lieu nho nam ngang: icon + chu.
private struct InlineStat: View {
    let symbol: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .monospacedDigit()
        }
    }
}
