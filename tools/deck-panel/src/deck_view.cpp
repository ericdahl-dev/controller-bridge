#include "deck_view.h"

#include <cmath>
#include <cstdio>
#include <cstring>

#include "board_pins.h"
#include "font_fallback.h"

// Geist (OFL), converted by fonts/make_fonts.sh into src/fonts/.
LV_FONT_DECLARE(geist_semibold_36)
LV_FONT_DECLARE(geist_regular_24)
LV_FONT_DECLARE(geist_mono_medium_32)
LV_FONT_DECLARE(geist_mono_semibold_64)

namespace {

using namespace deck_core::layout;

namespace palette = deck_core::palette;
const lv_color_t kGray = lv_color_hex(palette::kGray);
const lv_color_t kDim = lv_color_hex(palette::kDim);
const lv_color_t kTrack = lv_color_hex(palette::kTrack);

/// A full-screen page with no style of its own on the black screen, hidden.
lv_obj_t* page(lv_obj_t* parent) {
    lv_obj_t* box = lv_obj_create(parent);
    lv_obj_remove_style_all(box);
    lv_obj_set_size(box, board::LCD_WIDTH, board::LCD_HEIGHT);
    lv_obj_remove_flag(box, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(box, LV_OBJ_FLAG_HIDDEN);
    return box;
}

/// An opaque box: bars, blocks, markers. Opaque and untransformed, so drawing it needs no layer.
lv_obj_t* box(lv_obj_t* parent, int x, int y, int w, int h, lv_color_t color) {
    lv_obj_t* b = lv_obj_create(parent);
    lv_obj_remove_style_all(b);
    lv_obj_remove_flag(b, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_remove_flag(b, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_pos(b, x, y);
    lv_obj_set_size(b, w, h);
    lv_obj_set_style_bg_color(b, color, 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    return b;
}

/// A label `width` wide, in `font` and `color`, wrapped and cut at `lines`. Not LVGL's dot mode: it measures
/// against the label's old height, so a one-line label never grows, and it writes dots into the text. Never scroll
/// mode, which redraws every frame. The core already cuts at 40 characters with "…", so the cut is a backstop.
lv_obj_t* label(lv_obj_t* parent, int width, const lv_font_t* font, lv_color_t color, lv_text_align_t align,
                int lines) {
    lv_obj_t* l = lv_label_create(parent);
    lv_obj_set_width(l, width);
    lv_obj_set_style_text_font(l, font, 0);
    lv_obj_set_style_text_color(l, color, 0);
    lv_obj_set_style_text_align(l, align, 0);
    lv_obj_set_style_max_height(l, lv_font_get_line_height(font) * lines, 0);
    lv_label_set_long_mode(l, LV_LABEL_LONG_WRAP);
    lv_label_set_text_static(l, "");
    return l;
}

/// A one-line label with a fixed place and size, so a new text redraws that box and nothing else.
lv_obj_t* field(lv_obj_t* parent, int x, int y, int w, const lv_font_t* font, lv_color_t color,
                lv_text_align_t align = LV_TEXT_ALIGN_LEFT) {
    lv_obj_t* l = lv_label_create(parent);
    lv_obj_set_pos(l, x, y);
    lv_obj_set_size(l, w, lv_font_get_line_height(font));
    lv_obj_set_style_text_font(l, font, 0);
    lv_obj_set_style_text_color(l, color, 0);
    lv_obj_set_style_text_align(l, align, 0);
    lv_label_set_long_mode(l, LV_LABEL_LONG_CLIP);
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

    // The deck. Every object starts as a default Face draws it: no text, bars empty, blocks and lamps off.
    deck_page_ = page(screen);
    deck_number_ = field(deck_page_, kLeft, 12, 70, &geist_mono_semibold_64, lv_color_hex(shown_.deck_color));

    // Title (up to two lines) and artist across the top; the artist follows the title's height, inside this box.
    lv_obj_t* header = lv_obj_create(deck_page_);
    lv_obj_remove_style_all(header);
    lv_obj_remove_flag(header, LV_OBJ_FLAG_SCROLLABLE);
    const int header_w = board::LCD_WIDTH - kLeft - kHeaderX;
    lv_obj_set_pos(header, kHeaderX, kHeaderY);
    lv_obj_set_size(header, header_w, kInfoY - kHeaderY - 6);
    lv_obj_set_style_pad_row(header, 4, 0);
    lv_obj_set_flex_flow(header, LV_FLEX_FLOW_COLUMN);
    title_ = label(header, header_w, &geist_semibold_36, lv_color_white(), LV_TEXT_ALIGN_LEFT, 2);
    artist_ = label(header, header_w, &geist_regular_24, kGray, LV_TEXT_ALIGN_LEFT, 1);

    // Key, BPM, tempo: gray names on the values' baseline (Geist 24's sits 8 px lower in its line than Mono 32's).
    const lv_font_t* small = &geist_regular_24;
    const lv_font_t* mono = &geist_mono_medium_32;
    // Names' widths from the font: Key 42, BPM 53, Tempo 76 px. Values: "F#m", "1000.00", "+100.00%" in 19.2 px cells.
    lv_label_set_text_static(field(deck_page_, kLeft, kInfoY + 8, 48, small, kGray), "Key");
    key_ = field(deck_page_, 76, kInfoY, 100, mono, lv_color_white());
    lv_label_set_text_static(field(deck_page_, 200, kInfoY + 8, 60, small, kGray), "BPM");
    bpm_ = field(deck_page_, 264, kInfoY, 150, mono, lv_color_white());
    lv_label_set_text_static(field(deck_page_, 438, kInfoY + 8, 84, small, kGray), "Tempo");
    tempo_ = field(deck_page_, 526, kInfoY, 180, mono, lv_color_white());

    // Elapsed left, remaining right, large, in mono so the digits don't jitter.
    elapsed_ = field(deck_page_, kLeft, kTimeY, kWidth / 2, &geist_mono_semibold_64, lv_color_white());
    remaining_ = field(deck_page_, kLeft + kWidth / 2, kTimeY, kWidth / 2, &geist_mono_semibold_64, lv_color_white(),
                       LV_TEXT_ALIGN_RIGHT);

    // The progress bar: a fill on a track, its width the progress.
    lv_obj_t* progress = box(deck_page_, kLeft, kProgressY, kWidth, kProgressH, kTrack);
    progress_fill_ = box(progress, 0, 0, 0, kProgressH, lv_color_hex(shown_.progress_color));

    // The beat in the bar: four blocks, the lit one in the deck color.
    const int beat_w = (kWidth - 3 * kBeatGap) / 4;
    for (int i = 0; i < 4; ++i) {
        beats_[i] = box(deck_page_, kLeft + i * (beat_w + kBeatGap), kBeatY, beat_w, kBeatH, kTrack);
    }

    // The phase bar: a track, a center mark, and the marker, hidden while the phase is unknown.
    lv_obj_t* phase = box(deck_page_, kLeft, kPhaseY, kWidth, kPhaseH, kTrack);
    box(phase, kWidth / 2 - 1, 0, 2, kPhaseH, kGray);
    phase_px_ = deck_core::layout::kPhaseTravel / 2;
    phase_marker_ = box(phase, phase_px_, 0, kMarkerW, kPhaseH, lv_color_white());
    lv_obj_add_flag(phase_marker_, LV_OBJ_FLAG_HIDDEN);

    // The lamps: lit is the lamp's color with black text.
    const int lamp_w = (kWidth - 4 * kLampGap) / 5;
    Lamp* lamps[] = {&play_, &cue_, &sync_, &master_, &loop_};
    const char* names[] = {"PLAY", "CUE", "SYNC", "MASTER", "LOOP"};
    for (int i = 0; i < 5; ++i) {
        Lamp& lamp = *lamps[i];
        lamp.box = box(deck_page_, kLeft + i * (lamp_w + kLampGap), kLampY, lamp_w, kLampH, kTrack);
        lv_obj_set_style_radius(lamp.box, 6, 0);
        lamp.text = field(lamp.box, 0, (kLampH - lv_font_get_line_height(small)) / 2, lamp_w, small, kDim,
                          LV_TEXT_ALIGN_CENTER);
        lv_label_set_text_static(lamp.text, names[i]);
    }
    std::snprintf(loop_text_, sizeof loop_text_, "%s", shown_.loop_label);
    lv_label_set_text_static(loop_.text, loop_text_);

    // The level meter: a fill from the bottom.
    lv_obj_t* meter = box(deck_page_, kMeterX, kMeterY, kMeterW, kMeterH, kTrack);
    level_fill_ = box(meter, 0, 0, kMeterW, 0, lv_color_hex(palette::kLevel));
    lv_obj_set_align(level_fill_, LV_ALIGN_BOTTOM_LEFT);

    // Waiting: why, and what to do, in the middle.
    waiting_page_ = page(screen);
    lv_obj_set_style_pad_all(waiting_page_, kMargin, 0);
    lv_obj_set_style_pad_row(waiting_page_, 12, 0);
    lv_obj_set_flex_flow(waiting_page_, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(waiting_page_, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    const int waiting_w = board::LCD_WIDTH - 2 * kMargin;
    headline_ = label(waiting_page_, waiting_w, &geist_semibold_36, lv_color_white(), LV_TEXT_ALIGN_CENTER, 2);
    detail_ = label(waiting_page_, waiting_w, &geist_regular_24, kGray, LV_TEXT_ALIGN_CENTER, 3);
}

template <size_t N>
void DeckScreen::set_text(lv_obj_t* label, char (&shown)[N], const char* text) {
    static_assert(N <= sizeof fitted_, "fitted_ holds it");
    font_fallback::fit(text, fitted_, N);
    if (std::strcmp(shown, fitted_) == 0) return;
    std::memcpy(shown, fitted_, N);
    lv_label_set_text_static(label, shown);
}

void DeckScreen::show_waiting(const deck_core::WaitingView& view, const deck_core::WaitingChanges&) {
    set_text(headline_, headline_text_, view.headline);
    set_text(detail_, detail_text_, view.detail);
    set_hidden(deck_page_, true);
    set_hidden(waiting_page_, false);
}

void DeckScreen::show_deck(const deck_core::Face& face, const deck_core::Changes&) {
    draw(face);
    set_hidden(waiting_page_, true);
    set_hidden(deck_page_, false);
}

void DeckScreen::draw(const deck_core::Face& f) {
    using std::strcmp;
    if (f.deck_color != shown_.deck_color) lv_obj_set_style_text_color(deck_number_, lv_color_hex(f.deck_color), 0);
    if (strcmp(f.deck, shown_.deck) != 0) set_text(deck_number_, deck_text_, f.deck);
    if (strcmp(f.title, shown_.title) != 0) set_text(title_, title_text_, f.title);
    if (strcmp(f.artist, shown_.artist) != 0) set_text(artist_, artist_text_, f.artist);
    if (strcmp(f.key, shown_.key) != 0) set_text(key_, key_text_, f.key);
    if (strcmp(f.bpm, shown_.bpm) != 0) set_text(bpm_, bpm_text_, f.bpm);
    if (strcmp(f.tempo, shown_.tempo) != 0) set_text(tempo_, tempo_text_, f.tempo);
    if (strcmp(f.elapsed, shown_.elapsed) != 0) set_text(elapsed_, elapsed_text_, f.elapsed);
    if (strcmp(f.remaining, shown_.remaining) != 0) set_text(remaining_, remaining_text_, f.remaining);

    // Fast: progress, phase and level move a box only when a whole pixel changes.
    const int32_t progress = f.progress_px;
    if (progress != progress_px_) {
        progress_px_ = progress;
        lv_obj_set_width(progress_fill_, progress);
    }
    if (f.progress_color != shown_.progress_color) {
        lv_obj_set_style_bg_color(progress_fill_, lv_color_hex(f.progress_color), 0);
    }
    for (int i = 0; i < 4; ++i) {
        if (f.beat_color[i] != shown_.beat_color[i]) lv_obj_set_style_bg_color(beats_[i], lv_color_hex(f.beat_color[i]), 0);
    }
    const bool marker = f.phase_px != deck_core::kPhaseHidden;
    if (marker && f.phase_px != phase_px_) {
        phase_px_ = f.phase_px;
        lv_obj_set_x(phase_marker_, f.phase_px);
    }
    set_hidden(phase_marker_, !marker);
    const int32_t level = f.level_px;
    if (level != level_px_) {
        level_px_ = level;
        lv_obj_set_height(level_fill_, level);
    }

    // The lamps.
    Lamp* lamps[] = {&play_, &cue_, &sync_, &master_, &loop_};
    for (int i = 0; i < deck_core::kLamps; ++i) {
        if (f.lamp_color[i] != shown_.lamp_color[i]) lv_obj_set_style_bg_color(lamps[i]->box, lv_color_hex(f.lamp_color[i]), 0);
        if (f.lamp_text_color[i] != shown_.lamp_text_color[i]) {
            lv_obj_set_style_text_color(lamps[i]->text, lv_color_hex(f.lamp_text_color[i]), 0);
        }
    }
    if (strcmp(f.loop_label, shown_.loop_label) != 0) set_text(loop_.text, loop_text_, f.loop_label);

    shown_ = f;
}
