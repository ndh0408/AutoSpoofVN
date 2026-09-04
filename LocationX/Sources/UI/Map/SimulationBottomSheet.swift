import SwiftUI

/// Hai nac cua bang duoi.
enum BottomSheetDetent: CaseIterable {
    case collapsed
    case expanded

    /// Chieu cao theo khong gian con lai phia tren tab bar.
    func height(in available: CGFloat) -> CGFloat {
        switch self {
        case .collapsed: return 168
        case .expanded:  return max(320, available * 0.62)
        }
    }
}

/// Bang thong tin va dieu khien o day man hinh ban do.
///
/// Khong dung `.sheet` cua he thong: sheet he thong se **che mat tab bar**, ma app nay
/// co bon tab. Day la mot bang nam trong bo cuc, keo duoc giua hai nac, luon o tren tab bar.
///
/// Nac thu gon: trang thai, vi tri, toc do, nut hanh dong chinh.
/// Nac mo rong: telemetry day du, thong tin phien, nguon mo phong, tuy chon nang cao.
struct SimulationBottomSheet: View {
    @ObservedObject var coordinator: SimulationCoordinator
    @ObservedObject var flight: FlightManager
    @Binding var detent: BottomSheetDetent
    /// Chieu cao kha dung (da tru safe area va tab bar).
    let availableHeight: CGFloat

    let onStart: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onStop: () -> Void
    let onHalt: () -> Void
    let onOpenSheet: (AppSheet) -> Void
    let onSelectTab: (AppTab) -> Void

    @GestureState private var dragTranslation: CGFloat = 0
    @State private var showHaltConfirmation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            if detent == .expanded {
                expandedContent
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: currentHeight, alignment: .top)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: AppRadius.sheet,
                                   bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0,
                                   topTrailingRadius: AppRadius.sheet,
                                   style: .continuous)
                .fill(AppMaterial.sheet)
                .appShadow(AppShadow.sheet)
        )
        .appAnimation(AppAnimation.sheetDrag, value: detent)
        .confirmationDialog(L("map.halt.title"), isPresented: $showHaltConfirmation, titleVisibility: .visible) {
            Button(L("map.halt.action"), role: .destructive) {
                AppHaptics.stop()
                onHalt()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L("map.halt.message"))
        }
    }

    // MARK: - Chieu cao & cu chi keo

    private var currentHeight: CGFloat {
        let base = detent.height(in: availableHeight)
        let dragged = base - dragTranslation
        let minHeight = BottomSheetDetent.collapsed.height(in: availableHeight)
        let maxHeight = BottomSheetDetent.expanded.height(in: availableHeight)
        // Cho keo qua nguong mot chut de co cam giac dan hoi, nhung khong vuot han.
        return min(max(dragged, minHeight - 24), maxHeight + 24)
    }

    /// Cu chi gan o vung header, khong gan ca bang: gan ca bang thi `ScrollView`
    /// ben trong khong cuon duoc nua.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.height - value.translation.height
                let combined = value.translation.height + velocity * 0.25
                let target: BottomSheetDetent = combined < -40 ? .expanded
                    : combined > 40 ? .collapsed
                    : detent
                if target != detent {
                    AppHaptics.selection()
                    withAppAnimation(AppAnimation.sheetDrag) { detent = target }
                }
            }
    }

    // MARK: - Header (nac thu gon)

    private var header: some View {
        VStack(spacing: AppSpacing.md) {
            grabber

            HStack(alignment: .center, spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    HStack(spacing: AppSpacing.xs) {
                        SimulationStatusView(state: coordinator.state)
                        if let source = coordinator.activeSource, coordinator.state.isActive {
                            SourceBadge(source: source)
                        }
                    }
                    Text(AppFormat.coordinate(coordinator.currentCoordinate))
                        .font(AppFont.monoFootnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: AppSpacing.sm)

                if coordinator.state.isActive {
                    MetricView(L("telemetry.speed"),
                               value: AppFormat.speed(coordinator.telemetry.speedKmh),
                               unit: "km/h", compact: true)
                        .fixedSize()
                }
            }

            controlRow
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.md)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onTapGesture {
            withAppAnimation(AppAnimation.sheetDrag) {
                detent = detent == .collapsed ? .expanded : .collapsed
            }
        }
    }

    private var grabber: some View {
        Capsule()
            .fill(AppColor.textQuaternary)
            .frame(width: 36, height: 5)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.xs)
            .accessibilityElement()
            .accessibilityLabel(detent == .collapsed ? L("a11y.sheet.expand") : L("a11y.sheet.collapse"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                withAppAnimation(AppAnimation.sheetDrag) {
                    detent = detent == .collapsed ? .expanded : .collapsed
                }
            }
    }

    private var controlRow: some View {
        HStack(spacing: AppSpacing.sm) {
            PrimarySimulationButton(state: coordinator.state,
                                    startTitle: startTitle,
                                    onStart: onStart,
                                    onPause: onPause,
                                    onResume: onResume)
            if coordinator.state.canStop {
                StopSimulationButton(state: coordinator.state, compact: true, onStop: onStop)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .appAnimation(AppAnimation.spring, value: coordinator.state.canStop)
    }

    private var startTitle: String {
        coordinator.isHalted ? L("map.start_again") : L("map.start_spoof")
    }

    // MARK: - Noi dung mo rong

    private var expandedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                if coordinator.state.isActive {
                    telemetrySection
                    sessionSection
                } else {
                    sourcesSection
                }
                advancedSection
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.xs)
            .padding(.bottom, AppSpacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Telemetry

    private var telemetrySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(title: L("telemetry.title")) {
                Button(L("common.details")) { onOpenSheet(.telemetryDetail) }
                    .font(AppFont.footnoteEmphasized)
            }
            TelemetryGrid(items: telemetryItems)
        }
    }

    /// Chi hien nhung o CO du lieu that. O rong lam bang trong day nhung khong noi gi.
    private var telemetryItems: [TelemetryGrid.TelemetryItem] {
        let t = coordinator.telemetry
        var items: [TelemetryGrid.TelemetryItem] = [
            .init(label: L("telemetry.speed"), value: AppFormat.speed(t.speedKmh), unit: "km/h", icon: "speedometer"),
            .init(label: L("telemetry.heading"), value: AppFormat.heading(t.headingDegrees), icon: "location.north.line"),
        ]
        if t.altitudeMeters > 0 || flight.isFlying {
            items.append(.init(label: L("telemetry.altitude"), value: AppFormat.altitude(t.altitudeMeters), icon: "arrow.up.to.line"))
        }
        if t.elapsedTime > 0 {
            items.append(.init(label: L("telemetry.elapsed"), value: AppFormat.duration(t.elapsedTime), icon: "clock"))
        }
        if t.distanceTravelledMeters > 0 {
            items.append(.init(label: L("telemetry.travelled"), value: AppFormat.distance(t.distanceTravelledMeters), icon: "ruler"))
        }
        if t.distanceRemainingMeters > 0 {
            items.append(.init(label: L("telemetry.remaining"), value: AppFormat.distance(t.distanceRemainingMeters), icon: "flag.checkered"))
        }
        if t.routeProgress > 0 {
            items.append(.init(label: L("telemetry.progress"), value: AppFormat.percent(t.routeProgress),
                               icon: "chart.bar.fill", tint: AppColor.success))
        }
        if let eta = t.estimatedArrival {
            items.append(.init(label: L("route.eta"), value: AppFormat.arrivalTime(eta), icon: "calendar.badge.clock"))
        }
        return items
    }

    // MARK: Phien

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(L("map.session.title"))
            VStack(spacing: AppSpacing.xs) {
                if let source = coordinator.activeSource {
                    MetricRow(L("map.session.source"), value: source.displayName, icon: source.icon, monospaced: false)
                }
                if let session = coordinator.session {
                    MetricRow(L("map.session.travel_mode"), value: session.travelMode.displayName,
                              icon: session.travelMode.icon, monospaced: false)
                    if let name = session.routeName {
                        MetricRow(L("map.session.route"), value: name, icon: "map", monospaced: false)
                    }
                    MetricRow(L("map.session.max_speed"), value: "\(AppFormat.speed(session.maxSpeedKmh)) km/h",
                              icon: "gauge.high")
                }
                MetricRow(L("settings.device"), value: coordinator.deviceState.displayName,
                          icon: coordinator.deviceState.icon,
                          valueColor: coordinator.deviceState.tint, monospaced: false)
            }
            .appCard(padding: AppSpacing.md, background: AppColor.surfaceTertiary.opacity(0.5))
        }
    }

    // MARK: Nguon mo phong (khi dang ranh)

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(title: L("map.sources.title"), subtitle: L("map.sources.subtitle")) { EmptyView() }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: AppSpacing.sm),
                                GridItem(.flexible(), spacing: AppSpacing.sm)],
                      spacing: AppSpacing.sm) {
                SourceTile(title: L("map.source.route.title"), subtitle: L("map.source.route.subtitle"),
                           symbol: SimulationSource.route.icon, tint: AppColor.primary) {
                    onOpenSheet(.routeBuilder)
                }
                SourceTile(title: L("map.source.scenario.title"), subtitle: L("map.source.scenario.subtitle"),
                           symbol: SimulationSource.scenario.icon, tint: AppColor.accent) {
                    onOpenSheet(.scenarioStudio)
                }
                SourceTile(title: L("map.source.routine.title"), subtitle: L("map.source.routine.subtitle"),
                           symbol: SimulationSource.routine.icon, tint: AppColor.warning) {
                    onOpenSheet(.routineStudio)
                }
                SourceTile(title: L("map.source.flight.title"), subtitle: L("map.source.flight.subtitle"),
                           symbol: SimulationSource.flight.icon, tint: AppColor.success) {
                    onSelectTab(.flight)
                }
            }
        }
    }

    // MARK: Nang cao

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(L("common.advanced"))

            VStack(spacing: 0) {
                noiseRow
                HairlineDivider(inset: AppSpacing.md)
                AdvancedRow(title: L("map.manual_coordinate"), symbol: "character.cursor.ibeam") {
                    onOpenSheet(.manualCoordinate)
                }
                HairlineDivider(inset: AppSpacing.md)
                AdvancedRow(title: L("diagnostics.title"), symbol: "stethoscope") {
                    onOpenSheet(.diagnostics)
                }
                HairlineDivider(inset: AppSpacing.md)
                // `halt()` truoc day KHONG co duong vao nao tu man hinh chinh — chi nam trong
                // Device Manager. Day la cong tac an toan quan trong nhat cua app.
                AdvancedRow(title: L("map.halt.action"), symbol: "location.slash",
                            tint: AppColor.danger, showsChevron: false) {
                    showHaltConfirmation = true
                }
            }
            .appCard(padding: 0, background: AppColor.surfaceTertiary.opacity(0.5))
        }
    }

    private var noiseRow: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 14))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(L("map.noise.title"))
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
                Text(coordinator.noiseConfig.enabled
                     ? L("map.noise.radius", coordinator.noiseConfig.radiusMeters)
                     : L("map.noise.off"))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer(minLength: AppSpacing.sm)
            Picker(L("map.noise.title"), selection: noiseBinding) {
                ForEach(GPSNoiseConfig.presets, id: \.0) { name, _ in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.md)
    }

    /// Ghi thang vao `coordinator.noiseConfig` — nguon su that duy nhat, khong ban sao cuc bo.
    private var noiseBinding: Binding<String> {
        Binding(
            get: {
                GPSNoiseConfig.presets.first { $0.1 == coordinator.noiseConfig }?.0
                    ?? String(format: "%.0fm", coordinator.noiseConfig.radiusMeters)
            },
            set: { name in
                guard let preset = GPSNoiseConfig.presets.first(where: { $0.0 == name }) else { return }
                AppHaptics.selection()
                coordinator.noiseConfig = preset.1
            }
        )
    }
}

// MARK: - Thanh phan phu

/// O chon nguon mo phong o nac mo rong.
private struct SourceTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(AppFont.calloutEmphasized)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.md)
            .background(AppColor.surfaceTertiary.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Mot hang trong nhom "Nang cao".
private struct AdvancedRow: View {
    let title: String
    let symbol: String
    var tint: Color = AppColor.textPrimary
    var showsChevron: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(tint == AppColor.textPrimary ? AppColor.textSecondary : tint)
                    .frame(width: 22)
                Text(title)
                    .font(AppFont.callout)
                    .foregroundStyle(tint)
                Spacer()
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.textQuaternary)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(minHeight: AppSpacing.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(.isButton)
    }
}
