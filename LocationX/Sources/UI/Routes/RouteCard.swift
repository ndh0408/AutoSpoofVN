import CoreLocation
import SwiftUI

/// Thẻ tuyến đường trong danh sách.
///
/// Bố cục: ảnh tuyến bên trái, thông tin ở giữa, nút chạy nhanh bên phải.
/// Số liệu lấy từ chính `SavedRoute` — nay đã được lưu đầy đủ, nên thẻ hiện quãng đường
/// và thời gian thật thay vì `0 m / 0 phút` như trước.
struct RouteCard: View {
    let route: SavedRoute
    var isActive: Bool = false
    let onOpen: () -> Void
    let onQuickStart: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Ở cỡ chữ trợ năng, ảnh thu nhỏ nhường chỗ cho chữ.
    private var showsThumbnail: Bool { typeSize < .accessibility1 }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: AppSpacing.md) {
                if showsThumbnail {
                    RouteThumbnail(coordinates: route.runnableCoordinates,
                                   cacheKey: route.id.uuidString)
                        .frame(width: 76, height: 76)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.xs) {
                        Text(route.name)
                            .font(AppFont.calloutEmphasized)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        if isActive {
                            StatusIndicatorDot(color: AppColor.success, isPulsing: true, size: 6)
                        }
                    }

                    // Quãng đường · thời gian · phương tiện
                    HStack(spacing: AppSpacing.sm) {
                        Label(AppFormat.distance(route.totalDistanceMeters), systemImage: "ruler")
                        Label(AppFormat.duration(route.estimatedDurationSeconds), systemImage: "clock")
                    }
                    .font(AppFont.caption1)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)

                    HStack(spacing: AppSpacing.sm) {
                        Label(route.travelMode.displayName, systemImage: route.travelMode.icon)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.accent)
                        if let used = route.lastUsedAt {
                            Text("· \(Self.relative(used))")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: AppSpacing.xs)

                Button(action: onQuickStart) {
                    Image(systemName: isActive ? "stop.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isActive ? AppColor.danger : AppColor.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            (isActive ? AppColor.danger : AppColor.primary).opacity(0.14),
                            in: Circle()
                        )
                }
                .buttonStyle(.pressable)
                .accessibleButton(label: isActive ? L("a11y.route.stop", route.name) : L("a11y.route.start", route.name),
                                  hint: isActive ? L("a11y.route.stop_hint") : L("a11y.route.start_hint"))
            }
            .padding(.vertical, AppSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [route.name,
                     AppFormat.distance(route.totalDistanceMeters),
                     AppFormat.duration(route.estimatedDurationSeconds),
                     route.travelMode.displayName]
        if isActive { parts.append(L("a11y.route.running")) }
        return parts.joined(separator: ", ")
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "vi_VN")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - ScenarioCard

/// Thẻ kịch bản: tên, số bước, trạng thái chạy.
struct ScenarioCard: View {
    let scenario: Scenario
    var isActive: Bool = false
    var progress: Double = 0
    let onOpen: () -> Void
    let onQuickStart: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: SimulationSource.scenario.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(AppColor.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AppSpacing.xs) {
                        Text(scenario.name)
                            .font(AppFont.calloutEmphasized)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        if isActive {
                            StatusIndicatorDot(color: AppColor.success, isPulsing: true, size: 6)
                        }
                    }
                    Text(subtitle)
                        .font(AppFont.caption1)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                    if isActive, progress > 0 {
                        ProgressView(value: progress)
                            .tint(AppColor.success)
                            .frame(maxWidth: 140)
                    }
                }

                Spacer(minLength: AppSpacing.xs)

                Button(action: onQuickStart) {
                    Image(systemName: isActive ? "stop.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isActive ? AppColor.danger : AppColor.primary)
                        .frame(width: 36, height: 36)
                        .background((isActive ? AppColor.danger : AppColor.primary).opacity(0.14), in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibleButton(label: isActive ? L("a11y.scenario.stop", scenario.name) : L("a11y.scenario.start", scenario.name))
            }
            .padding(.vertical, AppSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
    }

    private var subtitle: String {
        var parts = [L("scenario.step_count", scenario.steps.count)]
        if scenario.isLoop { parts.append(L("scenario.loop")) }
        return parts.joined(separator: " · ")
    }
}
