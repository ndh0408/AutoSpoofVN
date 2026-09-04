import CoreLocation
import MapKit
import SwiftUI

// MARK: - Location Search View

struct LocationSearchView: View {
    let onSelect: (SearchResult) -> Void
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @Environment(\.dismiss) private var dismiss

    struct SearchResult: Identifiable {
        let id = UUID()
        let name: String
        let address: String
        let coordinate: CLLocationCoordinate2D
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColor.textTertiary)
                    TextField(L("route.search.placeholder"), text: $query)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppColor.textTertiary)
                        }
                    }
                }
                .padding(AppSpacing.md)
                .background(AppColor.surfaceTertiary)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                .padding()

                // Results
                if results.isEmpty && !query.isEmpty {
                    EmptyStateView(
                        icon: "mappin.slash",
                        title: L("route.search.empty"),
                        message: L("route.search.empty_message")
                    )
                } else {
                    List(results) { result in
                        Button {
                            onSelect(result)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text(result.name)
                                    .font(AppFont.body)
                                Text(result.address)
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(L("route.search.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.close) { dismiss() }
                }
            }
            .onChange(of: query) { _, newValue in
                Task { await search(newValue) }
            }
        }
    }

    private func search(_ text: String) async {
        guard text.count >= 2 else { results = []; return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .pointOfInterest

        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems.map { item in
                SearchResult(
                    name: item.name ?? L("route.search.unnamed"),
                    address: [item.placemark.thoroughfare, item.placemark.locality, item.placemark.country]
                        .compactMap { $0 }.joined(separator: ", "),
                    coordinate: item.placemark.coordinate
                )
            }
        } catch {
            results = []
        }
    }
}
