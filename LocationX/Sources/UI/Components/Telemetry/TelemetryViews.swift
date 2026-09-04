import SwiftUI

// MARK: - MetricView

/// Mot so lieu: nhan nho phia tren, gia tri lon phia duoi, don vi di kem.
/// API giu nguyen tu ban dau (3 file dang dung).
struct MetricView: View {
    let label: String
    let value: String
    let unit: String?
    let icon: String?
    /// Kieu gon dung trong luoi chat cho.
    var compact: Bool = false

    init(_ label: String, value: String, unit: String? = nil,
         icon: String? = nil, compact: Bool = false) {
        self.label = label
        self.value = value
        self.unit = unit
        self.icon = icon
        self.compact = compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack(spacing: AppSpacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppColor.textTertiary)
                }
                Text(label)
                    .font(AppFont.metricLabel)
                    .foregroundStyle(AppColor.textTertiary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    // monospacedDigit: khong co no, so lieu doi lien tuc lam ca hang chu nhay ngang.
                    .font(compact ? AppFont.metricValueCompact : AppFont.metricValue)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)\(unit.map { " " + $0 } ?? "")")
    }
}

/// Bien the co nhan VoiceOver ro rang. API giu nguyen.
struct AccessibleMetric: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        MetricView(label, value: value, unit: unit)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value) \(unit)")
    }
}

// MARK: - MetricRow

/// Mot dong nhan/gia tri — dung trong panel chi tiet va chan doan.
struct MetricRow: View {
    let label: String
    let value: String
    var icon: String?
    var valueColor: Color = AppColor.textPrimary
    var monospaced: Bool = true

    init(_ label: String, value: String, icon: String? = nil,
         valueColor: Color = AppColor.textPrimary, monospaced: Bool = true) {
        self.label = label
        self.value = value
        self.icon = icon
        self.valueColor = valueColor
        self.monospaced = monospaced
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(width: 16)
            }
            Text(label)
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.textSecondary)
            Spacer(minLength: AppSpacing.md)
            Text(value)
                .font(monospaced ? AppFont.monoFootnote : AppFont.footnoteEmphasized)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - TelemetryCard

/// Mot o so lieu doc lap — dung trong `TelemetryGrid`.
struct TelemetryCard: View {
    let label: String
    let value: String
    var unit: String?
    var icon: String?
    var tint: Color = AppColor.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                }
                Text(label)
                    .font(AppFont.metricLabel)
                    .lineLimit(1)
            }
            .foregroundStyle(AppColor.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(AppFont.metricValueCompact)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.md)
        .background(AppColor.surfaceTertiary.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)\(unit.map { " " + $0 } ?? "")")
    }
}

// MARK: - TelemetryGrid

/// Luoi so lieu tu thich ung: 2 cot o co chu thuong, 1 cot khi Dynamic Type lon.
///
/// Dung `LazyVGrid` chu khong phai `HStack` long nhau de chu phong to khong bi cat.
struct TelemetryGrid: View {
    let items: [TelemetryItem]

    @Environment(\.dynamicTypeSize) private var typeSize

    struct TelemetryItem: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        var unit: String?
        var icon: String?
        var tint: Color = AppColor.textPrimary
    }

    private var columns: [GridItem] {
        let count = typeSize >= .accessibility1 ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: AppSpacing.sm), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.sm) {
            ForEach(items) { item in
                TelemetryCard(label: item.label, value: item.value,
                              unit: item.unit, icon: item.icon, tint: item.tint)
            }
        }
    }
}

#Preview("Telemetry") {
    VStack(spacing: AppSpacing.lg) {
        HStack(spacing: AppSpacing.xl) {
            MetricView("Tốc độ", value: "42.3", unit: "km/h", icon: "speedometer")
            MetricView("Hướng", value: "137° ĐN", icon: "location.north.line")
        }
        TelemetryGrid(items: [
            .init(label: "Độ cao", value: "10,500", unit: "m", icon: "arrow.up.to.line"),
            .init(label: "Còn lại", value: "412 km", icon: "ruler"),
            .init(label: "ETA", value: "03:24", icon: "clock"),
            .init(label: "Tiến độ", value: "68%", icon: "chart.bar.fill", tint: AppColor.success),
        ])
        VStack(spacing: AppSpacing.xs) {
            MetricRow("Latitude", value: "21.02850000", icon: "mappin")
            MetricRow("Longitude", value: "105.85420000", icon: "mappin")
        }
    }
    .padding()
}
