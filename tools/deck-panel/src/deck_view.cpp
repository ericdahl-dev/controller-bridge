#include "deck_view.h"

#include <cstdio>
#include <cstring>

#include "board_pins.h"
#include "font_fallback.h"

namespace {

constexpr int kMargin = 40;
const lv_color_t kGray = lv_color_hex(0xA0A0A0);

/// A full-screen page with no style of its own on the black screen, laid out as a column.
lv_obj_t* page(lv_obj_t* parent, lv_flex_align_t main, lv_flex_align_t cross) {
    lv_obj_t* box = lv_obj_create(parent);
    lv_obj_remove_style_all(box);
    lv_obj_set_size(box, board::LCD_WIDTH, board::LCD_HEIGHT);
    lv_obj_set_style_pad_all(box, kMargin, 0);
    lv_obj_set_style_pad_row(box, 12, 0);
    lv_obj_remove_flag(box, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_flow(box, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(box, main, cross, cross);
    lv_obj_add_flag(box, LV_OBJ_FLAG_HIDDEN);
    return box;
}

/// A label the page's width, in `font` and `color`, wrapped and cut at `lines`. Not LVGL's dot mode: it measures
/// against the label's old height, so a one-line label never grows, and it writes dots into the text. Never scroll
/// mode, which redraws every frame. The core already cuts at 40 characters with "...", so the cut is a backstop.
lv_obj_t* label(lv_obj_t* parent, const lv_font_t* font, lv_color_t color, lv_text_align_t align, int lines) {
    lv_obj_t* l = lv_label_create(parent);
    lv_obj_set_width(l, board::LCD_WIDTH - 2 * kMargin);
    lv_obj_set_style_text_font(l, font, 0);
    lv_obj_set_style_text_color(l, color, 0);
    lv_obj_set_style_text_align(l, align, 0);
    lv_obj_set_style_max_height(l, lv_font_get_line_height(font) * lines, 0);
    lv_label_set_long_mode(l, LV_LABEL_LONG_WRAP);
    lv_label_set_text_static(l, "");
    return l;
}

void set_hidden(lv_obj_t* obj, bool hidden) {
    if (lv_obj_has_flag(obj, LV_OBJ_FLAG_HIDDEN) == hidden) return;
    if (hidden) lv_obj_add_flag(obj, LV_OBJ_FLAG_HIDDEN);
    else lv_obj_remove_flag(obj, LV_OBJ_FLAG_HIDDEN);
}

}  // namespace

void DeckScreen::build() {
    lv_obj_t* screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);

    // The deck: its number top left in its color, then title and artist.
    deck_page_ = page(screen, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_START);
    deck_number_ = label(deck_page_, &lv_font_montserrat_48, lv_color_white(), LV_TEXT_ALIGN_LEFT, 1);
    lv_obj_set_style_margin_bottom(deck_number_, 24, 0);
    title_ = label(deck_page_, &lv_font_montserrat_28, lv_color_white(), LV_TEXT_ALIGN_LEFT, 2);
    artist_ = label(deck_page_, &lv_font_montserrat_20, kGray, LV_TEXT_ALIGN_LEFT, 2);

    // Waiting: why, and what to do, in the middle.
    waiting_page_ = page(screen, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    headline_ = label(waiting_page_, &lv_font_montserrat_28, lv_color_white(), LV_TEXT_ALIGN_CENTER, 2);
    detail_ = label(waiting_page_, &lv_font_montserrat_20, kGray, LV_TEXT_ALIGN_CENTER, 3);
}

void DeckScreen::set_text(lv_obj_t* label, const char* text) {
    font_fallback::fit(text, fitted_, sizeof fitted_);
    if (std::strcmp(lv_label_get_text(label), fitted_) == 0) return;
    lv_label_set_text(label, fitted_);
}

void DeckScreen::show_waiting(const deck_core::WaitingView& view) {
    static_assert(sizeof view.headline <= sizeof fitted_ && sizeof view.detail <= sizeof fitted_, "fitted_ holds both");
    set_text(headline_, view.headline);
    set_text(detail_, view.detail);
    set_hidden(deck_page_, true);
    set_hidden(waiting_page_, false);
}

void DeckScreen::show_deck(const deck_core::DeckView& view) {
    // Before the feed says which deck: no number, rather than "Deck 0".
    char number[12] = "";
    if (view.deck > 0) std::snprintf(number, sizeof number, "Deck %d", view.deck);
    set_text(deck_number_, number);
    // Black is the background: a deck without a color shows white.
    const uint32_t color = view.color == 0 ? 0xFFFFFF : view.color;
    if (color != deck_color_) {
        deck_color_ = color;
        lv_obj_set_style_text_color(deck_number_, lv_color_hex(color), 0);
    }
    // An empty deck sends "" for both (ADR 0011).
    const bool empty = view.title[0] == 0 && view.artist[0] == 0;
    set_text(title_, empty ? "No track loaded" : view.title);
    set_text(artist_, view.artist);
    set_hidden(waiting_page_, true);
    set_hidden(deck_page_, false);
}
