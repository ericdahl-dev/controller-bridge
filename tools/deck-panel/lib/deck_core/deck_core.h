// The deck panel's portable core (#490, #619): it reads DeckBridge's display feed (ADR 0011), holds the deck in front
// and decides what the screen shows. No board, LVGL, Wi-Fi or UDP here: bytes and the time come in, decisions go out
// through `Screen`, so it builds and is tested on the Mac.
#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

namespace deck_core {

/// The longest title and artist shown, in characters; longer ones are cut and end in "…" (#490).
constexpr size_t kTitleMax = 40;
constexpr size_t kArtistMax = 40;
/// Room for 40 characters of up to 4 bytes each, and the NUL. No text is kept on the heap: the board's small
/// allocations come from the internal RAM LVGL and Wi-Fi use.
/// A key, such as "11B" or "F#m", fits in this many characters.
constexpr size_t kKeyMax = 4;
constexpr size_t kTextBytes = 40 * 4 + 1;
static_assert(kTitleMax <= 40 && kArtistMax <= 40, "kTextBytes holds 40 characters");

/// What the deck screen shows.
struct DeckView {
    int deck = 0;  ///< 1-4; 0 until the feed says
    uint32_t color = 0;  ///< 0xRRGGBB
    char title[kTextBytes] = "";  ///< UTF-8, shortened
    char artist[kTextBytes] = "";
    bool loaded = true;  ///< until the feed says 0
    char key[kKeyMax * 4 + 1] = "";  ///< shortened like the title
    float bpm = 0;
    float tempo = 0;  ///< percent
    bool playing = false, cue = false, sync = false, master = false, loop = false;
    float loop_length = 0;  ///< beats
    int beat = 0;  ///< 1-4; 0 none
    int32_t elapsed = 0, remaining = 0;  ///< whole seconds
    float progress = 0;  ///< 0-1
    float phase = -1;  ///< 0-1, 0.5 in phase; -1 unknown
    float level = 0;  ///< 0-1

    /// Every field: one added later goes here too, or a change to it won't redraw.
    bool operator==(const DeckView& o) const {
        return deck == o.deck && color == o.color && std::strcmp(title, o.title) == 0 &&
               std::strcmp(artist, o.artist) == 0 && loaded == o.loaded && std::strcmp(key, o.key) == 0 &&
               bpm == o.bpm && tempo == o.tempo && playing == o.playing && cue == o.cue && sync == o.sync &&
               master == o.master && loop == o.loop && loop_length == o.loop_length && beat == o.beat &&
               elapsed == o.elapsed && remaining == o.remaining && progress == o.progress && phase == o.phase &&
               level == o.level;
    }
};

/// The panel's network, as the board layer reports it (#620).
enum class Network {
    not_set,  ///< built without Wi-Fi credentials
    joining,  ///< joining, or lost and rejoining
    connected,
};

/// What the waiting screen says.
struct WaitingView {
    char headline[48] = "";
    char detail[96] = "";
    bool logo = false;  ///< the DeckBridge logo above the lines (#651)

    bool operator==(const WaitingView& other) const {
        return std::strcmp(headline, other.headline) == 0 && std::strcmp(detail, other.detail) == 0 &&
               logo == other.logo;
    }
};

/// The board layer draws what the core decides.
struct Screen {
    virtual ~Screen() = default;
    virtual void show_waiting(const WaitingView& view) = 0;
    virtual void show_deck(const DeckView& view) = 0;
};

/// Not thread-safe: feed() and render() must run on one task. On the board, the UDP task copies each payload into a
/// fixed-size queue item (dropped if the queue is full) and the loop task drains the queue into feed(), then calls
/// render() every frame. No heap, no exceptions, no RTTI.
class DeckCore {
public:
    /// No feed for this long and the panel shows the waiting screen (#490).
    static constexpr uint32_t kWaitAfterMs = 3000;
    /// The UDP port the panel listens on for the feed: DeckBridge's default (#616).
    static constexpr uint16_t kFeedPort = 9100;

    /// One UDP payload, a message or a bundle of them (#636), received at `now_ms` (any millisecond clock; it may wrap).
    void feed(const uint8_t* bytes, size_t length, uint32_t now_ms);
    /// What the core holds now, for the perf env's capture (#636); the screen gets it through render().
    const DeckView& view() const { return view_; }
    /// The network's state and the panel's IPv4 address ("" if none), from the board layer.
    /// Until told, the core takes the network as up: on the Mac, and for any board without Wi-Fi of its own.
    void set_network(Network state, const char* ip);
    /// Tells `screen` what to show at `now_ms`, only when that changed since the last call.
    void render(Screen& screen, uint32_t now_ms);

private:
    WaitingView waiting_view() const;
    /// One message: applied if it's one the panel takes; true if it keeps the feed alive.
    bool apply(const uint8_t* bytes, size_t length);

    DeckView view_;
    bool heard_ = false;
    bool goodbye_ = false;  ///< the datagram being read had DeckBridge's goodbye
    uint32_t last_heard_ms_ = 0;
    Network network_ = Network::connected;
    char ip_[16] = "";
    // What the screen was last told.
    bool shown_ = false;
    bool shown_waiting_ = true;
    DeckView shown_view_;
    WaitingView shown_waiting_view_;
};

}  // namespace deck_core
