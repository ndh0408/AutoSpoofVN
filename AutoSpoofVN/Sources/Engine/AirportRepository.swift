import Foundation

/// Kho sân bay quốc tế — tách khỏi FlightManager god object.
struct AirportRepository {
    static let shared = AirportRepository()

    let airports: [Airport] = [
        // Việt Nam
        Airport(code: "HAN", name: "Sân bay Quốc tế Nội Bài", city: "Hà Nội", country: "Việt Nam", latitude: 21.2212, longitude: 105.8072),
        Airport(code: "SGN", name: "Sân bay Quốc tế Tân Sơn Nhất", city: "TP. Hồ Chí Minh", country: "Việt Nam", latitude: 10.8188, longitude: 106.6519),
        Airport(code: "DAD", name: "Sân bay Quốc tế Đà Nẵng", city: "Đà Nẵng", country: "Việt Nam", latitude: 16.0439, longitude: 108.1994),
        Airport(code: "CXR", name: "Sân bay Cam Ranh", city: "Nha Trang", country: "Việt Nam", latitude: 11.9983, longitude: 109.2193),
        Airport(code: "PQC", name: "Sân bay Phú Quốc", city: "Phú Quốc", country: "Việt Nam", latitude: 10.1698, longitude: 103.9931),
        Airport(code: "VDO", name: "Sân bay Vân Đồn", city: "Quảng Ninh", country: "Việt Nam", latitude: 21.1178, longitude: 107.4143),
        Airport(code: "HPH", name: "Sân bay Cát Bi", city: "Hải Phòng", country: "Việt Nam", latitude: 20.8194, longitude: 106.7250),
        Airport(code: "HUI", name: "Sân bay Phú Bài", city: "Huế", country: "Việt Nam", latitude: 16.4015, longitude: 107.7028),
        // Đông Nam Á
        Airport(code: "BKK", name: "Suvarnabhumi Airport", city: "Bangkok", country: "Thái Lan", latitude: 13.6900, longitude: 100.7501),
        Airport(code: "SIN", name: "Singapore Changi Airport", city: "Singapore", country: "Singapore", latitude: 1.3644, longitude: 103.9915),
        Airport(code: "KUL", name: "Kuala Lumpur International", city: "Kuala Lumpur", country: "Malaysia", latitude: 2.7456, longitude: 101.7099),
        Airport(code: "CGK", name: "Soekarno-Hatta Airport", city: "Jakarta", country: "Indonesia", latitude: -6.1256, longitude: 106.6558),
        Airport(code: "MNL", name: "Ninoy Aquino Airport", city: "Manila", country: "Philippines", latitude: 14.5086, longitude: 121.0197),
        Airport(code: "RGN", name: "Yangon International", city: "Yangon", country: "Myanmar", latitude: 16.9073, longitude: 96.1332),
        // Đông Á
        Airport(code: "ICN", name: "Incheon International", city: "Seoul", country: "Hàn Quốc", latitude: 37.4602, longitude: 126.4407),
        Airport(code: "NRT", name: "Narita International", city: "Tokyo", country: "Nhật Bản", latitude: 35.7720, longitude: 140.3929),
        Airport(code: "HND", name: "Haneda Airport", city: "Tokyo", country: "Nhật Bản", latitude: 35.5494, longitude: 139.7798),
        Airport(code: "KIX", name: "Kansai International", city: "Osaka", country: "Nhật Bản", latitude: 34.4320, longitude: 135.2304),
        Airport(code: "PEK", name: "Beijing Capital", city: "Bắc Kinh", country: "Trung Quốc", latitude: 40.0799, longitude: 116.6031),
        Airport(code: "PVG", name: "Shanghai Pudong", city: "Thượng Hải", country: "Trung Quốc", latitude: 31.1443, longitude: 121.8083),
        Airport(code: "HKG", name: "Hong Kong International", city: "Hồng Kông", country: "Hồng Kông", latitude: 22.3080, longitude: 113.9185),
        Airport(code: "TPE", name: "Taiwan Taoyuan", city: "Đài Bắc", country: "Đài Loan", latitude: 25.0797, longitude: 121.2342),
        // Châu Âu
        Airport(code: "CDG", name: "Paris Charles de Gaulle", city: "Paris", country: "Pháp", latitude: 49.0097, longitude: 2.5479),
        Airport(code: "LHR", name: "London Heathrow", city: "London", country: "Anh", latitude: 51.4700, longitude: -0.4543),
        Airport(code: "FRA", name: "Frankfurt Airport", city: "Frankfurt", country: "Đức", latitude: 50.0379, longitude: 8.5622),
        Airport(code: "AMS", name: "Amsterdam Schiphol", city: "Amsterdam", country: "Hà Lan", latitude: 52.3105, longitude: 4.7683),
        Airport(code: "FCO", name: "Rome Fiumicino", city: "Rome", country: "Ý", latitude: 41.8003, longitude: 12.2389),
        Airport(code: "IST", name: "Istanbul Airport", city: "Istanbul", country: "Thổ Nhĩ Kỳ", latitude: 41.2608, longitude: 28.7419),
        // Trung Đông
        Airport(code: "DXB", name: "Dubai International", city: "Dubai", country: "UAE", latitude: 25.2532, longitude: 55.3657),
        Airport(code: "DOH", name: "Hamad International", city: "Doha", country: "Qatar", latitude: 25.2731, longitude: 51.6081),
        // Châu Mỹ
        Airport(code: "JFK", name: "John F. Kennedy", city: "New York", country: "Mỹ", latitude: 40.6413, longitude: -73.7781),
        Airport(code: "LAX", name: "Los Angeles International", city: "Los Angeles", country: "Mỹ", latitude: 33.9416, longitude: -118.4085),
        Airport(code: "SFO", name: "San Francisco International", city: "San Francisco", country: "Mỹ", latitude: 37.6213, longitude: -122.3790),
        Airport(code: "YVR", name: "Vancouver International", city: "Vancouver", country: "Canada", latitude: 49.1947, longitude: -123.1790),
        Airport(code: "GRU", name: "São Paulo Guarulhos", city: "São Paulo", country: "Brazil", latitude: -23.4356, longitude: -46.4731),
        // Châu Úc
        Airport(code: "SYD", name: "Sydney Kingsford Smith", city: "Sydney", country: "Úc", latitude: -33.9399, longitude: 151.1753),
        Airport(code: "MEL", name: "Melbourne Airport", city: "Melbourne", country: "Úc", latitude: -37.6690, longitude: 144.8410),
        Airport(code: "AKL", name: "Auckland Airport", city: "Auckland", country: "New Zealand", latitude: -37.0082, longitude: 174.7850),
    ]

    func find(code: String) -> Airport? {
        airports.first { $0.code.uppercased() == code.uppercased() }
    }

    func search(query: String) -> [Airport] {
        guard !query.isEmpty else { return airports }
        let q = query.lowercased()
        return airports.filter {
            $0.code.lowercased().contains(q) ||
            $0.name.lowercased().contains(q) ||
            $0.city.lowercased().contains(q) ||
            $0.country.lowercased().contains(q)
        }
    }

    var byCountry: [(String, [Airport])] {
        let grouped = Dictionary(grouping: airports) { $0.country }
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var vietnamese: [Airport] { airports.filter { $0.country == "Việt Nam" } }
}
