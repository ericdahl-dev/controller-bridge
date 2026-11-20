// The deck panel's portable core (#490, #619): it reads DeckBridge's display feed (ADR 0011), holds the deck in front
// and decides what the screen shows. No board, LVGL, Wi-Fi or UDP here: bytes and the time come in, decisions go out
// through `Screen`, so it builds and is tested on the Mac.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace deck_core {

/// The longest title and artist shown, in characters; longer ones are cut and end in "…" (#490).
constexpr size_t kTitleMax = 40;
constexpr size_t kArtistMax = 40;

/// What the deck screen shows.
struct DeckView {
    int deck = 0;  ///< 1-4; 0 until the feed says
    uint32_t color = 0;  ///< 0xRRGGBB
    std::string title;
    std::string artist;

    bool operator==(const DeckView& other) const {
        return deck == other.deck && color == other.color && title == other.title && artist == other.artist;
    }
};

/// The board layer draws what the core decides.
struct Screen {
    virtual ~Screen() = default;
    virtual void show_waiting() = 0;
    virtual void show_deck(const DeckView& view) = 0;
};

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
