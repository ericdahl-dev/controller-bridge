import ControllerBridgePresentation
import Testing

/// Quit from the panel (#131): the question is asked inside the panel, so it can't be hidden, and every path ends in
/// a quit or back to idle.
@Suite("Quit flow")
struct QuitFlowTests {
    @Test("With nothing live to stop, Quit quits at once")
    func quitsAtOnce() {
        var flow = QuitFlow()
        #expect(flow.pressQuit(asks: false) == .quitNow)
    }

    @Test("While feedback is live, Quit asks first, in the panel; confirming quits")
    func asksThenQuits() {
        var flow = QuitFlow()
        #expect(flow.pressQuit(asks: true) == nil)
        #expect(flow.confirming)
        #expect(QuitFlow.question == "Quit? The controller stops sending to Syndicate.")
        #expect(flow.confirm() == .quitNow)
    }

    @Test("Cancel, or the panel closing, puts the question away")
    func cancelAndCloseReset() {
        var flow = QuitFlow()
        _ = flow.pressQuit(asks: true)
        flow.cancel()
        #expect(!flow.confirming)
        _ = flow.pressQuit(asks: true)
        flow.panelClosed()
        #expect(!flow.confirming)
    }

    @Test("Asked once, a second Quit press quits, even if feedback stopped meanwhile")
    func secondPressQuits() {
        var flow = QuitFlow()
        _ = flow.pressQuit(asks: true)
        #expect(flow.pressQuit(asks: false) == .quitNow)
    }
}
