import Foundation

/// Prompt lists for a guided capture (#186). Their ids are a contract with the draft-profile tool (#189) and the web
/// capture (#190): rename one and both must follow.
public enum CapturePrompts {
    /// A DJ controller, deck 1 in full plus the deck 2 layer. The idle step comes first, so noise is learned before
    /// any control is pressed. Read from capture-prompts-dj.json, the file the web capture copies (#190), so the app
    /// and the site walk the same steps.
    public static let djController: [CapturePrompt] = {
        do {
            return try JSONDecoder().decode([CapturePrompt].self, from: djControllerJSON)
        } catch {
            preconditionFailure("The bundled capture-prompts-dj.json doesn't decode: \(error)")
        }
    }()

    /// The DJ controller prompt list as shipped: pretty-printed JSON with sorted keys and a trailing newline.
    public static let djControllerJSON: Data = {
        guard let url = Bundle.module.url(forResource: "capture-prompts-dj", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { preconditionFailure("capture-prompts-dj.json is missing from the bundle") }
        return data
    }()
}
