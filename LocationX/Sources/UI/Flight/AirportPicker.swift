import SwiftUI

/// Chọn sân bay, có tìm kiếm.
///
/// Trước đây danh sách sân bay chỉ hiện dạng cuộn phẳng nhóm theo quốc gia, không tìm
/// kiếm được — với hàng chục sân bay thì tìm bằng mắt là chính.
struct AirportPicker: View {
    let title: String
    let airports: [Airport]
    let onSelect: (Airport) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// Khớp theo mã IATA, tên sân bay, thành phố và quốc gia — người dùng có thể nhớ
    /// bất kỳ thứ nào trong số đó.
    private var matches: [Airport] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return airports }
        return airports.filter { airport in
            [airport.code, airport.name, airport.city, airport.country]
                .contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    /// Nhóm theo quốc gia, giữ Việt Nam lên đầu.
    private var grouped: [(country: String, airports: [Airport])] {
        let dict = Dictionary(grouping: matches, by: \.country)
        return dict.keys.sorted { a, b in
            if a == "Việt Nam" { return true }
            if b == "Việt Nam" { return false }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        .map { ($0, dict[$0]!.sorted { $0.city < $1.city }) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if matches.isEmpty {
                    EmptyStateView(icon: "airplane.circle",
                                   title: L("flight.picker.empty"),
                                   message: L("flight.picker.empty_message"))
                } else {
                    List {
                        ForEach(grouped, id: \.country) { group in
                            Section(group.country) {
                                ForEach(group.airports) { airport in
                                    Button {
                                        AppHaptics.selection()
                                        onSelect(airport)
                                        dismiss()
                                    } label: {
                                        AirportRow(airport: airport)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: L("flight.picker.search"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("action.cancel")) { dismiss() }
                }
            }
        }
    }
}

/// Một dòng sân bay: mã IATA, thành phố, tên đầy đủ.
struct AirportRow: View {
    let airport: Airport
    var trailing: String?

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Text(airport.code)
                .font(AppFont.monoFootnote.weight(.bold))
                .foregroundStyle(AppColor.primary)
                .frame(width: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(airport.city)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textPrimary)
                Text(airport.name)
                    .font(AppFont.caption1)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpacing.sm)

            if let trailing {
                Text(trailing)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(airport.code), \(airport.city), \(airport.country)")
    }
}

/// Ô chọn sân bay đầu/cuối trên màn hình chuyến bay.
struct AirportSelectionField: View {
    let label: String
    let airport: Airport?
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                    if let airport {
                        Text("\(airport.code) · \(airport.city)")
                            .font(AppFont.calloutEmphasized)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                    } else {
                        Text(L("flight.select_airport"))
                            .font(AppFont.callout)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.textQuaternary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(airport.map { "\(label): \($0.code), \($0.city)" } ?? L("flight.select_airport"))
    }
}
