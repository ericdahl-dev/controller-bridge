// The deck screen and the waiting screen in LVGL (#620, #621): what the core decides, drawn on the 800x480. The objects
// are built once; each show_* compares with what's on screen widget by widget and changes only that, so a frame
// allocates nothing here and a fast field (phase, level, progress) redraws only its own box.
#pragma once

#include <lvgl.h>

#include "deck_core.h"
#include "deck_face.h"

class DeckScreen : public deck_core::Screen {
public:
    /// Builds both screens' objects on the active screen, both hidden. Call once, after display_init().
    void build();

    void show_waiting(const deck_core::WaitingView& view) override;
    void show_deck(const deck_core::DeckView& view) override;

private:
    /// `text` fitted to the font into `shown`, the label's static text, set only if it changed: each set redraws the
    /// label. Static, so LVGL keeps no copy and a change allocates nothing.
    template <size_t N>
    void set_text(lv_obj_t* label, char (&shown)[N], const char* text);

    void draw(const deck_core::Face& f);

    struct Lamp {
        lv_obj_t* box = nullptr;
        lv_obj_t* text = nullptr;
        uint32_t color = 0;  ///< lit
    };

    lv_obj_t* deck_page_ = nullptr;
    lv_obj_t* deck_number_ = nullptr;
    lv_obj_t* title_ = nullptr;
    lv_obj_t* artist_ = nullptr;
    lv_obj_t* key_ = nullptr;
    lv_obj_t* bpm_ = nullptr;
    lv_obj_t* tempo_ = nullptr;
    lv_obj_t* elapsed_ = nullptr;
    lv_obj_t* remaining_ = nullptr;
    lv_obj_t* progress_fill_ = nullptr;
    lv_obj_t* beats_[4] = {};
    lv_obj_t* phase_marker_ = nullptr;
    lv_obj_t* level_fill_ = nullptr;
    Lamp play_, cue_, sync_, master_, loop_;
    lv_obj_t* waiting_page_ = nullptr;
    lv_obj_t* logo_ = nullptr;  ///< above the headline, shown when the view asks for it
    lv_obj_t* headline_ = nullptr;
    lv_obj_t* detail_ = nullptr;

    /// What the deck screen shows now. build() leaves the objects as a default Face draws.
    deck_core::Face shown_;
    /// The fast fields in pixels: most of their 30 updates a second move nothing, so draw nothing.
    int32_t progress_px_ = 0;
    int32_t phase_px_ = 0;  ///< set by build()
    int32_t level_px_ = 0;
    /// Each label's text, which LVGL points at.
    char deck_text_[sizeof shown_.deck] = "";
    char title_text_[sizeof shown_.title] = "";
    char artist_text_[sizeof shown_.artist] = "";
    char key_text_[sizeof shown_.key] = "";
    char bpm_text_[sizeof shown_.bpm] = "";
    char tempo_text_[sizeof shown_.tempo] = "";
    char elapsed_text_[sizeof shown_.elapsed] = "";
    char remaining_text_[sizeof shown_.remaining] = "";
    char loop_text_[16] = "";
    char headline_text_[sizeof deck_core::WaitingView::headline] = "";
    char detail_text_[sizeof deck_core::WaitingView::detail] = "";
    /// The fitted text, before it's compared; a member, not on the loop's stack.
    char fitted_[deck_core::kTextBytes];
};
