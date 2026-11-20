// The deck screen and the waiting screen in LVGL (#620): what the core decides, drawn on the 800x480. The objects are
// built once; each show_* only changes text, colors and what's hidden, so a frame allocates nothing new.
#pragma once

#include <lvgl.h>

#include "deck_core.h"

class DeckScreen : public deck_core::Screen {
public:
    /// Builds both screens' objects on the active screen, both hidden. Call once, after display_init().
    void build();

    void show_waiting(const deck_core::WaitingView& view) override;
    void show_deck(const deck_core::DeckView& view) override;

private:
    /// `text` fitted to the font, set only if it changed: each set redraws the label.
    void set_text(lv_obj_t* label, const char* text);

    lv_obj_t* deck_page_ = nullptr;
    lv_obj_t* deck_number_ = nullptr;
    lv_obj_t* title_ = nullptr;
    lv_obj_t* artist_ = nullptr;
    lv_obj_t* waiting_page_ = nullptr;
    lv_obj_t* headline_ = nullptr;
    lv_obj_t* detail_ = nullptr;
    uint32_t deck_color_ = 0xFFFFFFFF;  ///< none yet
    /// The fitted text is never longer than the source, so the core's sizes do; a member, not on the loop's stack.
    char fitted_[deck_core::kTextBytes];
};
