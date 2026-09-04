import Foundation
import CoreLocation

/// Quan ly chuyen bay toan cau va Che do Vong quanh the gioi tu dong (World Odyssey)
final class FlightManager: ObservableObject {
    static let shared = FlightManager()

    // MARK: - Danh sach San bay Quoc te
    @Published var popularAirports: [Airport] = [
        Airport(code: "HAN", name: "Sân bay Quốc tế Nội Bài", city: "Hà Nội", country: "Việt Nam", latitude: 21.2212, longitude: 105.8072),
        Airport(code: "SGN", name: "Sân bay Quốc tế Tân Sơn Nhất", city: "TP. Hồ Chí Minh", country: "Việt Nam", latitude: 10.8188, longitude: 106.6519),
        Airport(code: "DAD", name: "Sân bay Quốc tế Đà Nẵng", city: "Đà Nẵng", country: "Việt Nam", latitude: 16.0439, longitude: 108.1994),
        Airport(code: "BKK", name: "Suvarnabhumi Airport", city: "Bangkok", country: "Thái Lan", latitude: 13.6900, longitude: 100.7501),
        Airport(code: "SIN", name: "Singapore Changi Airport", city: "Singapore", country: "Singapore", latitude: 1.3644, longitude: 103.9915),
        Airport(code: "ICN", name: "Incheon International Airport", city: "Seoul", country: "Hàn Quốc", latitude: 37.4602, longitude: 126.4407),
        Airport(code: "NRT", name: "Narita International Airport", city: "Tokyo", country: "Nhật Bản", latitude: 35.7720, longitude: 140.3929),
        Airport(code: "HND", name: "Haneda Airport", city: "Tokyo", country: "Nhật Bản", latitude: 35.5494, longitude: 139.7798),
        Airport(code: "CDG", name: "Paris Charles de Gaulle Airport", city: "Paris", country: "Pháp", latitude: 49.0097, longitude: 2.5479),
        Airport(code: "LHR", name: "London Heathrow Airport", city: "London", country: "Anh", latitude: 51.4700, longitude: -0.4543),
        Airport(code: "DXB", name: "Dubai International Airport", city: "Dubai", country: "UAE", latitude: 25.2532, longitude: 55.3657),
        Airport(code: "JFK", name: "John F. Kennedy Airport", city: "New York", country: "Mỹ", latitude: 40.6413, longitude: -73.7781),
        Airport(code: "LAX", name: "Los Angeles Airport", city: "Los Angeles", country: "Mỹ", latitude: 33.9416, longitude: -118.4085),
        Airport(code: "SYD", name: "Sydney Kingsford Smith Airport", city: "Sydney", country: "Úc", latitude: -33.9399, longitude: 151.1753)
    ]

    // MARK: - Danh sach Diem den Du lich The gioi
    @Published var worldDestinations: [WorldDestination] = [
        WorldDestination(
            name: "Tokyo",
            country: "Nhật Bản",
            timeZoneOffsetHours: 9.0,
            airport: Airport(code: "NRT", name: "Narita Airport", city: "Tokyo", country: "Nhật Bản", latitude: 35.7720, longitude: 140.3929),
            hotelName: "Aman Tokyo (Chiyoda)",
            hotelCoordinate: CoordinateCodable(latitude: 35.6882, longitude: 139.7645),
            spots: [
                SightseeingSpot(name: "Ngã tư Shibuya", category: "Khu mua sắm", latitude: 35.6595, longitude: 139.7005, dwellMinutes: 90),
                SightseeingSpot(name: "Chùa Senso-ji Asakusa", category: "Văn hoá", latitude: 35.7148, longitude: 139.7967, dwellMinutes: 120),
                SightseeingSpot(name: "Tháp Tokyo Tower", category: "Danh lam", latitude: 35.6586, longitude: 139.7454, dwellMinutes: 60),
                SightseeingSpot(name: "Chợ cá Tsukiji Outer", category: "Ẩm thực", latitude: 35.6655, longitude: 139.7707, dwellMinutes: 90),
                SightseeingSpot(name: "Công viên Shinjuku Gyoen", category: "Thiên nhiên", latitude: 35.6852, longitude: 139.7100, dwellMinutes: 90)
            ],
            stayDays: 3
        ),
        WorldDestination(
            name: "Bangkok",
            country: "Thái Lan",
            timeZoneOffsetHours: 7.0,
            airport: Airport(code: "BKK", name: "Suvarnabhumi Airport", city: "Bangkok", country: "Thái Lan", latitude: 13.6900, longitude: 100.7501),
            hotelName: "Mandarin Oriental Bangkok",
            hotelCoordinate: CoordinateCodable(latitude: 13.7234, longitude: 100.5146),
            spots: [
                SightseeingSpot(name: "Hoàng cung Grand Palace", category: "Lịch sử", latitude: 13.7500, longitude: 100.4913, dwellMinutes: 120),
                SightseeingSpot(name: "Chùa Wat Arun", category: "Văn hoá", latitude: 13.7437, longitude: 100.4889, dwellMinutes: 90),
                SightseeingSpot(name: "Siam Paragon / CentralWorld", category: "Mua sắm", latitude: 13.7466, longitude: 100.5348, dwellMinutes: 120),
                SightseeingSpot(name: "Chợ đêm Jodd Fairs", category: "Ẩm thực", latitude: 13.7570, longitude: 100.5678, dwellMinutes: 120)
            ],
            stayDays: 2
        ),
        WorldDestination(
            name: "Singapore",
            country: "Singapore",
            timeZoneOffsetHours: 8.0,
            airport: Airport(code: "SIN", name: "Changi Airport", city: "Singapore", country: "Singapore", latitude: 1.3644, longitude: 103.9915),
            hotelName: "Marina Bay Sands",
            hotelCoordinate: CoordinateCodable(latitude: 1.2834, longitude: 103.8607),
            spots: [
                SightseeingSpot(name: "Gardens by the Bay", category: "Thiên nhiên", latitude: 1.2816, longitude: 103.8636, dwellMinutes: 120),
                SightseeingSpot(name: "Công viên Sư tử Merlion", category: "Danh lam", latitude: 1.2868, longitude: 103.8545, dwellMinutes: 60),
                SightseeingSpot(name: "Đại lộ Orchard Road", category: "Mua sắm", latitude: 1.3048, longitude: 103.8318, dwellMinutes: 120),
                SightseeingSpot(name: "Đảo Sentosa Resort", category: "Giải trí", latitude: 1.2494, longitude: 103.8303, dwellMinutes: 180)
            ],
            stayDays: 2
        ),
        WorldDestination(
            name: "Paris",
            country: "Pháp",
            timeZoneOffsetHours: 2.0,
            airport: Airport(code: "CDG", name: "Charles de Gaulle Airport", city: "Paris", country: "Pháp", latitude: 49.0097, longitude: 2.5479),
            hotelName: "Hôtel Plaza Athénée",
            hotelCoordinate: CoordinateCodable(latitude: 48.8660, longitude: 2.3040),
            spots: [
                SightseeingSpot(name: "Tháp Eiffel", category: "Danh lam", latitude: 48.8584, longitude: 2.2945, dwellMinutes: 120),
                SightseeingSpot(name: "Bảo tàng Louvre", category: "Nghệ thuật", latitude: 48.8606, longitude: 2.3376, dwellMinutes: 180),
                SightseeingSpot(name: "Khải Hoàn Môn Arc de Triomphe", category: "Lịch sử", latitude: 48.8738, longitude: 2.2950, dwellMinutes: 60),
                SightseeingSpot(name: "Nhà thờ Đức Bà Paris", category: "Văn hoá", latitude: 48.8530, longitude: 2.3499, dwellMinutes: 90)
            ],
            stayDays: 3
        ),
        WorldDestination(
            name: "New York",
            country: "Mỹ",
            timeZoneOffsetHours: -4.0,
            airport: Airport(code: "JFK", name: "JFK Airport", city: "New York", country: "Mỹ", latitude: 40.6413, longitude: -73.7781),
            hotelName: "The Plaza Hotel (Fifth Ave)",
            hotelCoordinate: CoordinateCodable(latitude: 40.7645, longitude: -73.9744),
            spots: [
                SightseeingSpot(name: "Quảng trường Times Square", category: "Thành phố", latitude: 40.7580, longitude: -73.9855, dwellMinutes: 90),
                SightseeingSpot(name: "Công viên Central Park", category: "Thiên nhiên", latitude: 40.7829, longitude: -73.9654, dwellMinutes: 120),
                SightseeingSpot(name: "Toà nhà Empire State", category: "Danh lam", latitude: 40.7484, longitude: -73.9857, dwellMinutes: 90),
                SightseeingSpot(name: "Tượng Nữ thần Tự do", category: "Lịch sử", latitude: 40.6892, longitude: -74.0445, dwellMinutes: 150)
            ],
            stayDays: 3
        ),
        WorldDestination(
            name: "Seoul",
            country: "Hàn Quốc",
            timeZoneOffsetHours: 9.0,
            airport: Airport(code: "ICN", name: "Incheon Airport", city: "Seoul", country: "Hàn Quốc", latitude: 37.4602, longitude: 126.4407),
            hotelName: "The Shilla Seoul",
            hotelCoordinate: CoordinateCodable(latitude: 37.5562, longitude: 127.0050),
            spots: [
                SightseeingSpot(name: "Cung điện Gyeongbokgung", category: "Lịch sử", latitude: 37.5796, longitude: 126.9770, dwellMinutes: 120),
                SightseeingSpot(name: "Tháp Namsan Tower", category: "Danh lam", latitude: 37.5512, longitude: 126.9882, dwellMinutes: 90),
                SightseeingSpot(name: "Phố mua sắm Myeongdong", category: "Mua sắm", latitude: 37.5636, longitude: 126.9839, dwellMinutes: 120),
                SightseeingSpot(name: "Phố cổ Bukchon Hanok", category: "Văn hoá", latitude: 37.5826, longitude: 126.9835, dwellMinutes: 90)
            ],
            stayDays: 2
        ),
        WorldDestination(
            name: "Dubai",
            country: "UAE",
            timeZoneOffsetHours: 4.0,
            airport: Airport(code: "DXB", name: "Dubai Airport", city: "Dubai", country: "UAE", latitude: 25.2532, longitude: 55.3657),
            hotelName: "Burj Al Arab Jumeirah",
            hotelCoordinate: CoordinateCodable(latitude: 25.1412, longitude: 55.1852),
            spots: [
                SightseeingSpot(name: "Toà tháp Burj Khalifa", category: "Danh lam", latitude: 25.1972, longitude: 55.2744, dwellMinutes: 90),
                SightseeingSpot(name: "Trung tâm Dubai Mall", category: "Mua sắm", latitude: 25.1985, longitude: 55.2796, dwellMinutes: 150),
                SightseeingSpot(name: "Đảo cọ Palm Jumeirah", category: "Nghỉ dưỡng", latitude: 25.1124, longitude: 55.1390, dwellMinutes: 120)
            ],
            stayDays: 2
        ),
        WorldDestination(
            name: "Sydney",
            country: "Úc",
            timeZoneOffsetHours: 10.0,
            airport: Airport(code: "SYD", name: "Sydney Airport", city: "Sydney", country: "Úc", latitude: -33.9399, longitude: 151.1753),
            hotelName: "Park Hyatt Sydney",
            hotelCoordinate: CoordinateCodable(latitude: -33.8557, longitude: 151.2093),
            spots: [
                SightseeingSpot(name: "Nhà hát Opera Sydney", category: "Danh lam", latitude: -33.8568, longitude: 151.2153, dwellMinutes: 120),
                SightseeingSpot(name: "Cầu Cảng Sydney Harbour", category: "Danh lam", latitude: -33.8523, longitude: 151.2108, dwellMinutes: 60),
                SightseeingSpot(name: "Bãi biển Bondi Beach", category: "Bãi biển", latitude: -33.8915, longitude: 151.2767, dwellMinutes: 180)
            ],
            stayDays: 2
        )
    ]

    // MARK: - Trạng thái Chuyến bay & Tour du lịch
    @Published var activeFlight: FlightSimulation? = nil
    @Published var flightTimeWarpMultiplier: Double = 1.0 // 1x, 5x, 10x, 30x, 60x, 120x
    @Published var isFlying: Bool = false
    @Published var isAutoWorldOdysseyEnabled: Bool = false // Chế độ tự động chu du vòng quanh thế giới
    @Published var currentDestinationIndex: Int = 0
    @Published var currentDayInDestination: Int = 1
    @Published var activeDestination: WorldDestination? = nil
    @Published var activeTourSpotIndex: Int = 0
    @Published var destinationLocalTime: String = ""
    @Published var flightPathCoordinates: [CLLocationCoordinate2D] = []
    /// Toc do len/xuong (m/s). Duong = dang leo cao.
    ///
    /// Suy ra tu chenh lech do cao giua hai tick — FlightManager la noi duy nhat biet
    /// chuoi do cao theo thoi gian, nen tinh o day chu khong phai o tang giao dien.
    @Published private(set) var verticalSpeedMps: Double = 0
    private var lastAltitudeSample: (altitude: Double, at: Date)?

    private var flightTimer: Timer?
    private var tourTimer: Timer?
    private var transitionTimer: Timer?

    private init() {}

    // MARK: - Khởi động Tour Vòng Quanh Thế Giới (Auto World Odyssey)
    func toggleAutoWorldOdyssey() {
        isAutoWorldOdysseyEnabled.toggle()
        if isAutoWorldOdysseyEnabled {
            if activeDestination == nil {
                currentDestinationIndex = 0
                currentDayInDestination = 1
                let firstDest = worldDestinations[0]
                startFlightToDestination(firstDest)
            } else {
                startDestinationTour(destination: activeDestination!)
            }
        } else {
            // Tắt chế độ chu du phải dừng HẲN, kể cả chuyến bay đang giữa trời.
            //
            // Bản trước chỉ huỷ `tourTimer` và `transitionTimer`, bỏ quên `flightTimer` —
            // nên người dùng tắt chế độ này giữa chuyến bay thì máy bay vẫn tiếp tục bay
            // và tiếp tục ghi toạ độ, `isFlying` vẫn `true`, nguồn `.flight` không được nhả.
            if isFlying {
                stopFlight()
            } else {
                tourTimer?.invalidate()
                tourTimer = nil
                transitionTimer?.invalidate()
                transitionTimer = nil
            }
            activeDestination = nil
            RoutineManager.shared.statusDescription = L("flight.world_tour.stopped")
        }
    }

    // MARK: - Bắt đầu Chuyến bay Cầu tròn Đại cung (500 - 900 km/h)
    func startFlight(origin: Airport, destination: Airport, speedKmh: Double = 800.0) {
        _ = SpoofEngine.shared.acquire(.flight)
        let totalDist = GeodesicMath.distanceKm(from: origin.coordinate.clCoordinate, to: destination.coordinate.clCoordinate)
        let flightNum = "VN\(Int.random(in: 100...999))"

        let sim = FlightSimulation(
            flightNumber: flightNum,
            origin: origin,
            destination: destination,
            cruisingSpeedKmh: speedKmh,
            currentSpeedKmh: 200.0,
            phase: .takeoff,
            progressFraction: 0.0,
            totalDistanceKm: totalDist,
            remainingDistanceKm: totalDist,
            estimatedMinutesRemaining: (totalDist / speedKmh) * 60.0,
            altitudeMeters: 1000.0
        )

        self.activeFlight = sim
        self.isFlying = true

        // Tạo 100 điểm đại cung Slerp mượt mà
        var pathCoords: [CLLocationCoordinate2D] = []
        for i in 0...100 {
            let f = Double(i) / 100.0
            let pt = GeodesicMath.interpolateGreatCircle(from: origin.coordinate.clCoordinate, to: destination.coordinate.clCoordinate, fraction: f)
            pathCoords.append(pt)
        }
        self.flightPathCoordinates = pathCoords

        // Đặt vị trí xuất phát tại sân bay
        _ = SpoofEngine.shared.submit(latitude: origin.coordinate.latitude, longitude: origin.coordinate.longitude, from: .flight)

        RoutineManager.shared.currentState = .flying
        RoutineManager.shared.statusDescription = "Chuyến bay [\(flightNum)]: \(origin.code) ➔ \(destination.code) (\(Int(speedKmh)) km/h)"
        RoutineManager.shared.currentSpeedKmh = speedKmh

        startFlightLoop()
    }

    func startFlightToDestination(_ dest: WorldDestination, fromOrigin: Airport? = nil) {
        let origin: Airport
        if let from = fromOrigin {
            origin = from
        } else if let cur = activeDestination {
            origin = cur.airport
        } else {
            origin = popularAirports.first(where: { $0.code == "HAN" }) ?? popularAirports[0]
        }

        self.activeDestination = dest
        startFlight(origin: origin, destination: dest.airport, speedKmh: 820.0)
    }

    // MARK: - Flight Loop (Cập nhật toạ độ GPS máy bay liên tục)
    private func startFlightLoop() {
        flightTimer?.invalidate()
        let intervalSeconds: Double = 1.0

        flightTimer = CommonTimer.scheduled(every: intervalSeconds) { [weak self] _ in
            guard let self = self, var flight = self.activeFlight else { return }

            let effectiveSpeedKmh = flight.cruisingSpeedKmh * self.flightTimeWarpMultiplier
            let kmPerSecond = effectiveSpeedKmh / 3600.0
            let kmAdvanced = kmPerSecond * intervalSeconds

            let newRemainingKm = max(0, flight.remainingDistanceKm - kmAdvanced)
            let newProgress = max(0.0, min(1.0, 1.0 - (newRemainingKm / max(1.0, flight.totalDistanceKm))))

            let currentAlt: Double
            let currentSpd: Double
            let phase: FlightPhase

            if newProgress < 0.05 {
                phase = .takeoff
                currentSpd = 350.0 + (flight.cruisingSpeedKmh - 350.0) * (newProgress / 0.05)
                currentAlt = 500.0 + 9500.0 * (newProgress / 0.05)
            } else if newProgress > 0.92 {
                phase = .descent
                let descFrac = (newProgress - 0.92) / 0.08
                currentSpd = flight.cruisingSpeedKmh - (flight.cruisingSpeedKmh - 220.0) * descFrac
                currentAlt = 10000.0 - 9700.0 * descFrac
            } else {
                phase = .cruising
                currentSpd = flight.cruisingSpeedKmh
                currentAlt = 10500.0 + Double.random(in: -40...40)
            }

            let curCoord = GeodesicMath.interpolateGreatCircle(
                from: flight.origin.coordinate.clCoordinate,
                to: flight.destination.coordinate.clCoordinate,
                fraction: newProgress
            )

            _ = SpoofEngine.shared.submit(latitude: curCoord.latitude, longitude: curCoord.longitude, from: .flight)

            flight.progressFraction = newProgress
            flight.remainingDistanceKm = newRemainingKm
            flight.currentSpeedKmh = currentSpd
            flight.altitudeMeters = currentAlt
            flight.phase = phase

            // Toc do len/xuong: chenh lech do cao chia cho thoi gian that giua hai mau.
            // Dung thoi gian THAT chu khong phai `intervalSeconds`, vi he so tua thoi gian
            // lam mot tick tuong duong nhieu giay bay.
            let now = Date()
            if let last = self.lastAltitudeSample {
                let dt = now.timeIntervalSince(last.at)
                if dt > 0.01 {
                    self.verticalSpeedMps = (currentAlt - last.altitude) / dt
                }
            }
            self.lastAltitudeSample = (currentAlt, now)
            flight.estimatedMinutesRemaining = (newRemainingKm / flight.cruisingSpeedKmh) * 60.0

            self.activeFlight = flight
            RoutineManager.shared.currentSpeedKmh = currentSpd
            RoutineManager.shared.statusDescription = "Bay [\(flight.flightNumber)]: \(flight.origin.code) ➔ \(flight.destination.code) | Cao: \(Int(currentAlt))m | \(Int(newRemainingKm)) km còn lại"

            if newProgress >= 1.0 {
                self.handleFlightArrival(flight)
            }
        }
    }

    // MARK: - Khi Máy bay Hạ cánh
    private func handleFlightArrival(_ flight: FlightSimulation) {
        flightTimer?.invalidate()
        self.isFlying = false
        var completed = flight
        completed.phase = .landed
        completed.currentSpeedKmh = 0.0
        completed.remainingDistanceKm = 0.0
        completed.altitudeMeters = 0.0
        self.activeFlight = completed

        if let dest = self.activeDestination {
            RoutineManager.shared.currentState = .commutingAirport
            RoutineManager.shared.statusDescription = "Đã hạ cánh tại sân bay \(dest.airport.name). Đang di chuyển taxi về \(dest.hotelName)..."
            RoutineManager.shared.currentSpeedKmh = 40.0

            // Mô phỏng di chuyển từ Sân bay về Khách sạn
            simulateAirportTransfer(from: dest.airport.coordinate.clCoordinate, to: dest.hotelCoordinate.clCoordinate, stateName: .commutingAirport, label: "Taxi từ sân bay về khách sạn") { [weak self] in
                guard let self = self else { return }
                self.setupDestinationRoutine(destination: dest)
            }
        } else {
            RoutineManager.shared.currentState = .resting
            RoutineManager.shared.statusDescription = "Đã hạ cánh an toàn tại \(flight.destination.name) (\(flight.destination.code))"
            RoutineManager.shared.currentSpeedKmh = 0.0
        }
    }

    // MARK: - Thiết lập Thói quen Sinh hoạt Điểm đến
    func setupDestinationRoutine(destination: WorldDestination) {
        _ = SpoofEngine.shared.acquire(.flight)
        self.activeDestination = destination
        self.currentDayInDestination = 1

        // Cat giu dia diem that cua nguoi dung truoc khi ghi de bang dia diem du lich.
        RoutineManager.shared.beginTravelOverride()
        RoutineManager.shared.homeLocation = destination.hotelCoordinate.clCoordinate
        if let firstSpot = destination.spots.first {
            RoutineManager.shared.workLocation = firstSpot.coordinate.clCoordinate
        }
        if destination.spots.count > 1 {
            RoutineManager.shared.cafeLocation = destination.spots[1].coordinate.clCoordinate
        }

        var newBookmarks: [PlaceBookmark] = [
            PlaceBookmark(name: "Khách sạn: \(destination.hotelName)", latitude: destination.hotelCoordinate.latitude, longitude: destination.hotelCoordinate.longitude)
        ]
        for s in destination.spots {
            newBookmarks.append(PlaceBookmark(name: "[\(s.category)] \(s.name)", latitude: s.coordinate.latitude, longitude: s.coordinate.longitude))
        }
        RoutineManager.shared.bookmarks = newBookmarks

        _ = SpoofEngine.shared.submit(latitude: destination.hotelCoordinate.latitude, longitude: destination.hotelCoordinate.longitude, from: .flight)
        RoutineManager.shared.currentState = .hotel
        RoutineManager.shared.statusDescription = "Đã nhận phòng tại \(destination.hotelName) (\(destination.name), \(destination.country))"
        RoutineManager.shared.currentSpeedKmh = 0.0

        startDestinationTour(destination: destination)
    }

    // MARK: - Tour Du Lịch Toàn Diện Từng Ngày (Sightseeing, Dining, Nightlife, Hotel)
    func startDestinationTour(destination: WorldDestination) {
        tourTimer?.invalidate()
        activeTourSpotIndex = 0

        evaluateTourSchedule(destination: destination)

        tourTimer = CommonTimer.scheduled(every: 60.0) { [weak self] _ in
            guard let self = self, let dest = self.activeDestination else { return }
            self.evaluateTourSchedule(destination: dest)
        }
    }

    private func evaluateTourSchedule(destination: WorldDestination) {
        // Tính giờ địa phương tại thành phố đích
        let gmtDate = Date()
        let localHour = (Calendar.current.component(.hour, from: gmtDate) + Int(destination.timeZoneOffsetHours - 7.0) + 24) % 24
        let localMinute = Calendar.current.component(.minute, from: gmtDate)
        destinationLocalTime = String(format: "%02d:%02d (%@, UTC%@%d)", localHour, localMinute, destination.name, destination.timeZoneOffsetHours >= 0 ? "+" : "", Int(destination.timeZoneOffsetHours))

        switch localHour {
        case 23...24, 0...7:
            // 23:00 - 07:30: Ngủ tại khách sạn
            RoutineManager.shared.currentState = .hotel
            RoutineManager.shared.statusDescription = "Đang ngủ tại khách sạn \(destination.hotelName)"
            RoutineManager.shared.currentSpeedKmh = 0.0
            _ = SpoofEngine.shared.submit(latitude: destination.hotelCoordinate.latitude, longitude: destination.hotelCoordinate.longitude, from: .flight)

        case 8:
            // 08:00 - 08:59: Ăn sáng khách sạn
            RoutineManager.shared.currentState = .dining
            RoutineManager.shared.statusDescription = "Ăn buffet sáng tại nhà hàng khách sạn"
            RoutineManager.shared.currentSpeedKmh = 0.0
            _ = SpoofEngine.shared.submit(latitude: destination.hotelCoordinate.latitude, longitude: destination.hotelCoordinate.longitude, from: .flight)

        case 9...11:
            // 09:00 - 11:59: Điểm tham quan sáng (Sightseeing Spot 1)
            if !destination.spots.isEmpty {
                let spot = destination.spots[0]
                RoutineManager.shared.currentState = .sightseeing
                RoutineManager.shared.statusDescription = "Đang tham quan \(spot.name) [\(spot.category)]"
                RoutineManager.shared.currentSpeedKmh = 3.5
                _ = SpoofEngine.shared.submit(latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude, from: .flight)
            }

        case 12:
            // 12:00 - 13:00: Ăn trưa tại quán ăn nổi tiếng
            if let foodSpot = destination.spots.first(where: { $0.category.contains("Ẩm thực") }) ?? destination.spots.first {
                RoutineManager.shared.currentState = .dining
                RoutineManager.shared.statusDescription = "Ăn trưa & trải nghiệm ẩm thực tại \(foodSpot.name)"
                RoutineManager.shared.currentSpeedKmh = 0.0
                _ = SpoofEngine.shared.submit(latitude: foodSpot.coordinate.latitude, longitude: foodSpot.coordinate.longitude, from: .flight)
            }

        case 13...17:
            // 13:00 - 17:59: Điểm tham quan chiều (Sightseeing Spot 2 & 3)
            let spotIndex = (destination.spots.count > 1) ? ((localHour % 2 == 0) ? 1 : (destination.spots.count > 2 ? 2 : 1)) : 0
            let spot = destination.spots[spotIndex]
            RoutineManager.shared.currentState = .sightseeing
            RoutineManager.shared.statusDescription = "Đang khám phá \(spot.name) [\(spot.category)]"
            RoutineManager.shared.currentSpeedKmh = 4.0
            _ = SpoofEngine.shared.submit(latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude, from: .flight)

        case 18...21:
            // 18:00 - 21:59: Ăn tối & Dạo phố đêm (Nightlife & Shopping)
            if let shopSpot = destination.spots.first(where: { $0.category.contains("Mua sắm") || $0.category.contains("Thành phố") }) {
                RoutineManager.shared.currentState = .dining
                RoutineManager.shared.statusDescription = "Ăn tối & dạo phố mua sắm tại \(shopSpot.name)"
                RoutineManager.shared.currentSpeedKmh = 3.8
                _ = SpoofEngine.shared.submit(latitude: shopSpot.coordinate.latitude, longitude: shopSpot.coordinate.longitude, from: .flight)
            } else {
                RoutineManager.shared.currentState = .wandering
                RoutineManager.shared.statusDescription = "Dạo phố đêm trung tâm \(destination.name)"
                RoutineManager.shared.currentSpeedKmh = 3.5
                let delta = Double.random(in: -0.002...0.002)
                _ = SpoofEngine.shared.submit(latitude: destination.hotelCoordinate.latitude + delta, longitude: destination.hotelCoordinate.longitude + delta, from: .flight)
            }

        default:
            // 22:00: Về lại khách sạn
            RoutineManager.shared.currentState = .hotel
            RoutineManager.shared.statusDescription = "Về lại khách sạn \(destination.hotelName) nghỉ ngơi"
            RoutineManager.shared.currentSpeedKmh = 0.0
            _ = SpoofEngine.shared.submit(latitude: destination.hotelCoordinate.latitude, longitude: destination.hotelCoordinate.longitude, from: .flight)
        }
    }

    // MARK: - Mô phỏng Trung chuyển Xe (Airport Transfer)
    private func simulateAirportTransfer(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, stateName: RoutineState, label: String, onComplete: @escaping () -> Void) {
        let steps = 30
        var coords: [CLLocationCoordinate2D] = []
        for i in 0...steps {
            let f = Double(i) / Double(steps)
            let lat = from.latitude + (to.latitude - from.latitude) * f
            let lon = from.longitude + (to.longitude - from.longitude) * f
            coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        var idx = 0
        transitionTimer?.invalidate()
        transitionTimer = CommonTimer.scheduled(every: 1.5) { [weak self] timer in
            if idx < coords.count {
                _ = SpoofEngine.shared.submit(latitude: coords[idx].latitude, longitude: coords[idx].longitude, from: .flight)
                idx += 1
            } else {
                timer.invalidate()
                self?.transitionTimer = nil
                onComplete()
            }
        }
    }

    func stopFlight() {
        verticalSpeedMps = 0
        lastAltitudeSample = nil
        flightTimer?.invalidate()
        tourTimer?.invalidate()
        transitionTimer?.invalidate()
        isFlying = false
        activeFlight = nil
        flightPathCoordinates.removeAll()
        RoutineManager.shared.currentSpeedKmh = 0.0
        RoutineManager.shared.statusDescription = "Đã dừng chuyến bay / tour"
        // Tra lai nha / co quan / quan ca phe / bookmark that cua nguoi dung.
        RoutineManager.shared.endTravelOverride()
        activeDestination = nil
        SpoofEngine.shared.release(.flight)
    }
}
