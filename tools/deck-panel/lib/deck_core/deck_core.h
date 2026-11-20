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
constexpr size_t kTextBytes = 40 * 4 + 1;
static_assert(kTitleMax <= 40 && kArtistMax <= 40, "kTextBytes holds 40 characters");

/// What the deck screen shows.
struct DeckView {
    int deck = 0;  ///< 1-4; 0 until the feed says
    uint32_t color = 0;  ///< 0xRRGGBB
    char title[kTextBytes] = "";  ///< UTF-8, shortened
    char artist[kTextBytes] = "";

    /// Every field: one #617 adds goes here too, or a change to it won't redraw.
    bool operator==(const DeckView& other) const {
        return deck == other.deck && color == other.color && std::strcmp(title, other.title) == 0 &&
               std::strcmp(artist, other.artist) == 0;
    }
};

/// The board layer draws what the core decides.
struct Screen {
    virtual ~Screen() = default;
    virtual void show_waiting() = 0;
    virtual void show_deck(const DeckView& view) = 0;
};

/// Not thread-safe: feed() and render() must run on one task. On the board, the UDP task copies each payload into a
/// fixed-size queue item (dropped if the queue is full) and the loop task drains the queue into feed(), then calls
/// render() every frame. No heap, no exceptions, no RTTI.
class DeckCore {
public:
    /// No feed for this long and the panel shows the waiting screen (#490).
    static constexpr uint32_t kWaitAfterMs = 3000;

    /// One UDP payload, received at `now_ms` (any millisecond clock; it may wrap).
    void feed(const uint8_t* bytes, size_t length, uint32_t now_ms);
    /// Tells `screen` what to show at `now_ms`, only when that changed since the last call.
    void render(Screen& screen, uint32_t now_ms);

private:
    DeckView view_;
    bool heard_ = false;
    uint32_t last_heard_ms_ = 0;
    // What the screen was last told.
    bool shown_ = false;
    bool shown_waiting_ = true;
    DeckView shown_view_;
};

}  // namespace deck_core
