import ControllerBridgePresentation
import Testing

/// Settings › Controller's Controller picker (#200): Automatic or a profile by hand, saved for the card's device.
@Suite("Controller picker")
struct ProfilePickerTests {
    static let profiles = [(id: "denon-lc6000-prime", name: "Denon LC6000 PRIME")]

    @Test("The options: Automatic, then each profile by name; Controller not found? is the last item")
    func options() {
        let picker = ProfilePicker(chosenInput: nil, connectedDevice: "LC6000 PRIME", unsupported: nil, profiles: Self.profiles, choices: [:])
        #expect(picker.options == [
            ProfilePicker.Option(id: nil, title: "Automatic (match by device name)"),
            ProfilePicker.Option(id: "denon-lc6000-prime", title: "Denon LC6000 PRIME"),
        ])
        #expect(ProfilePicker.notFoundTitle == "Controller not found?")
    }

    @Test("The device: the card's chosen input, else the one it runs on, else the unsupported one the panel highlights")
    func device() {
        #expect(ProfilePicker(chosenInput: "A", connectedDevice: "B", unsupported: "C", profiles: Self.profiles, choices: [:]).device == "A")
        #expect(ProfilePicker(chosenInput: nil, connectedDevice: "B", unsupported: "C", profiles: Self.profiles, choices: [:]).device == "B")
        #expect(ProfilePicker(chosenInput: nil, connectedDevice: nil, unsupported: "C", profiles: Self.profiles, choices: [:]).device == "C")
    }

    @Test("The selection is the device's saved choice; one naming a profile that's gone shows Automatic")
    func selection() {
        let chosen = ProfilePicker(
            chosenInput: nil, connectedDevice: nil, unsupported: "Mystery DJ 2", profiles: Self.profiles,
            choices: ["Mystery DJ 2": "denon-lc6000-prime"]
        )
        #expect(chosen.selected == "denon-lc6000-prime")
        #expect(chosen.hint == "For Mystery DJ 2")
        let gone = ProfilePicker(chosenInput: "LC6000 PRIME", connectedDevice: nil, unsupported: nil, profiles: Self.profiles,
                                 choices: ["LC6000 PRIME": "gone"])
        #expect(gone.selected == nil)
    }

    @Test("With no device to choose for, the picker is off and says why")
    func noDevice() {
        let picker = ProfilePicker(chosenInput: nil, connectedDevice: nil, unsupported: nil, profiles: Self.profiles, choices: [:])
        #expect(picker.device == nil)
        #expect(!picker.enabled)
        #expect(picker.hint == "Connect your controller to choose its profile")
    }
}
