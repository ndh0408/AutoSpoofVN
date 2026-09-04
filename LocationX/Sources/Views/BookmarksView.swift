import CoreLocation
import MapKit
import SwiftUI

/// Bookmarks + Recent Locations — truy cập nhanh địa điểm yêu thích.
struct BookmarksView: View {
    @State private var bookmarks: [LocationBookmark] = PersistenceManager.shared.loadBookmarks()
    @State private var showAddSheet = false
    @State private var selectedCategory: BookmarkCategory?
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [LocationBookmark] {
        var result = bookmarks
        if let cat = selectedCategory { result = result.filter { $0.category == cat } }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.address ?? "").localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if bookmarks.isEmpty {
                    EmptyStateView(
                        icon: "bookmark",
                        title: L("empty.bookmarks"),
                        message: L("empty.bookmarks.message"),
                        actionTitle: L("bookmarks.add")
                    ) { showAddSheet = true }
                } else {
                    VStack(spacing: 0) {
                        // Category filter
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.sm) {
                                CategoryChip(label: L("common.all"), icon: "bookmark", selected: selectedCategory == nil) {
                                    selectedCategory = nil
                                }
                                ForEach(BookmarkCategory.allCases, id: \.self) { cat in
                                    CategoryChip(label: cat.displayName, icon: cat.icon, selected: selectedCategory == cat) {
                                        selectedCategory = cat
                                    }
                                }
                            }
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.sm)
                        }

                        List {
                            ForEach(filtered) { bookmark in
                                Button {
                                    SimulationCoordinator.shared.setManualLocation(bookmark.coordinate.clCoordinate)
                                    updateLastUsed(bookmark)
                                    dismiss()
                                } label: {
                                    HStack(spacing: AppSpacing.md) {
                                        Image(systemName: bookmark.category.icon)
                                            .font(.title3)
                                            .foregroundStyle(AppColor.primary)
                                            .frame(width: 32)
                                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                            Text(bookmark.name).font(AppFont.body)
                                            if let addr = bookmark.address {
                                                Text(addr).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                                            }
                                            Text(String(format: "%.4f, %.4f", bookmark.coordinate.latitude, bookmark.coordinate.longitude))
                                                .font(AppFont.mono).foregroundStyle(AppColor.textTertiary)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .onDelete { indices in
                                bookmarks.remove(atOffsets: indices)
                                PersistenceManager.shared.saveBookmarks(bookmarks)
                            }
                        }
                        .listStyle(.plain)
                        .searchable(text: $searchText, prompt: L("bookmarks.search_prompt"))
                    }
                }
            }
            .navigationTitle(L("bookmarks.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button(L("action.close")) { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAddSheet = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddBookmarkView { bookmark in
                    bookmarks.insert(bookmark, at: 0)
                    PersistenceManager.shared.saveBookmarks(bookmarks)
                    showAddSheet = false
                }
            }
        }
    }

    private func updateLastUsed(_ bookmark: LocationBookmark) {
        if let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[idx].lastUsedAt = Date()
            PersistenceManager.shared.saveBookmarks(bookmarks)
        }
    }
}

struct CategoryChip: View {
    let label: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: icon).font(.caption)
                Text(label).font(AppFont.caption)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(selected ? AppColor.primary.opacity(0.15) : AppColor.surfaceTertiary)
            .foregroundStyle(selected ? AppColor.primary : AppColor.textSecondary)
            .clipShape(Capsule())
        }
    }
}

struct AddBookmarkView: View {
    let onSave: (LocationBookmark) -> Void
    @State private var name = ""
    @State private var lat = ""
    @State private var lon = ""
    @State private var category: BookmarkCategory = .custom
    @State private var searchResults: [LocationSearchView.SearchResult] = []
    @State private var searchQuery = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(L("bookmarks.section.search")) {
                    TextField(L("bookmarks.search_place"), text: $searchQuery)
                        .autocorrectionDisabled()
                    if !searchResults.isEmpty {
                        ForEach(searchResults) { result in
                            Button {
                                name = result.name
                                lat = String(format: "%.6f", result.coordinate.latitude)
                                lon = String(format: "%.6f", result.coordinate.longitude)
                                searchResults = []
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(result.name).font(AppFont.body)
                                    Text(result.address).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                                }
                            }
                        }
                    }
                }

                Section(L("bookmarks.section.details")) {
                    TextField(L("bookmarks.field.name"), text: $name)
                    TextField("Latitude", text: $lat).keyboardType(.decimalPad)
                    TextField("Longitude", text: $lon).keyboardType(.decimalPad)
                    Picker(L("bookmarks.field.category"), selection: $category) {
                        ForEach(BookmarkCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                }
            }
            .navigationTitle(L("bookmarks.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button(L("action.cancel")) { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("action.save")) {
                        guard let latD = Double(lat), let lonD = Double(lon),
                              (-90...90).contains(latD), (-180...180).contains(lonD) else { return }
                        let bm = LocationBookmark(name: name.isEmpty ? "Bookmark" : name,
                                                  coordinate: CLLocationCoordinate2D(latitude: latD, longitude: lonD),
                                                  category: category)
                        onSave(bm)
                    }.fontWeight(.semibold)
                }
            }
            .onChange(of: searchQuery) { _, q in Task { await search(q) } }
        }
    }

    private func search(_ text: String) async {
        guard text.count >= 2 else { searchResults = []; return }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        do {
            let resp = try await MKLocalSearch(request: req).start()
            searchResults = resp.mapItems.map {
                LocationSearchView.SearchResult(
                    name: $0.name ?? "", address: $0.placemark.title ?? "",
                    coordinate: $0.placemark.coordinate)
            }
        } catch { searchResults = [] }
    }
}
