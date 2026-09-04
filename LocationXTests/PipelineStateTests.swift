import XCTest
@testable import LocationX

/// Trang thai duong truyen hien tren thanh trang thai, o man Chan doan va o tab Cai dat.
///
/// Truoc day no bam vao `SpoofEngine.isLoopbackConnected` — mot co ma sau khi bo FFI
/// khong bao gio thanh true, nen app bao "Chua ket noi" vinh vien ke ca luc mo phong
/// dang chay hoan hao. Bo test nay khoa lai bang suy dien moi.
final class PipelineStateTests: XCTestCase {

    /// Khong co may chu toa do thi khong con gi de noi ve Shadowrocket ca:
    /// day la loi cua chinh app, phai bao truoc moi thu khac.
    func testServerDownBeatsEverythingElse() {
        let state = SimulationCoordinator.pipelineState(installed: true,
                                                        imported: true,
                                                        vpnActive: true,
                                                        serverRunning: false)
        guard case .error = state else {
            return XCTFail("may chu tat phai la .error, nhan duoc \(state)")
        }
        XCTAssertFalse(state.isConnected)
    }

    func testNotInstalledIsAnError() {
        let state = SimulationCoordinator.pipelineState(installed: false,
                                                        imported: false,
                                                        vpnActive: false,
                                                        serverRunning: true)
        guard case .error = state else {
            return XCTFail("chua cai Shadowrocket phai la .error, nhan duoc \(state)")
        }
    }

    /// Da cai nhung chua import module: chua the ket noi, nhung cung KHONG phai loi —
    /// nguoi dung chi moi di duoc nua duong trong phan huong dan.
    func testInstalledButNoModuleIsDisconnectedNotError() {
        let state = SimulationCoordinator.pipelineState(installed: true,
                                                        imported: false,
                                                        vpnActive: false,
                                                        serverRunning: true)
        XCTAssertEqual(state, .disconnected)
    }

    func testModuleImportedButVPNOffIsConnecting() {
        let state = SimulationCoordinator.pipelineState(installed: true,
                                                        imported: true,
                                                        vpnActive: false,
                                                        serverRunning: true)
        XCTAssertEqual(state, .connecting)
    }

    func testFullChainIsConnectedAndNamesShadowrocket() {
        let state = SimulationCoordinator.pipelineState(installed: true,
                                                        imported: true,
                                                        vpnActive: true,
                                                        serverRunning: true)
        XCTAssertEqual(state, .connected(transport: "Shadowrocket"))
        XCTAssertTrue(state.isConnected)
    }

    /// Chi mot to hop duy nhat duoc coi la ket noi. Neu ai do noi long dieu kien,
    /// test nay do — va do la dieu mong muon: thanh trang thai bao xanh khi to a do
    /// chua toi duoc ung dung nao la kieu sai te nhat trong ca app nay.
    func testExactlyOneCombinationCountsAsConnected() {
        var connectedCount = 0
        for installed in [false, true] {
            for imported in [false, true] {
                for vpn in [false, true] {
                    for server in [false, true] {
                        let state = SimulationCoordinator.pipelineState(installed: installed,
                                                                        imported: imported,
                                                                        vpnActive: vpn,
                                                                        serverRunning: server)
                        if state.isConnected { connectedCount += 1 }
                    }
                }
            }
        }
        XCTAssertEqual(connectedCount, 1)
    }
}
