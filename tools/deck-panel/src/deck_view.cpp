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
// The logo (#651), made from the icon's SVG by deck_logo.py into src/deck_logo.c.
LV_IMAGE_DECLARE(deck_logo);

namespace {

// The deck screen, in pixels (#490's layout). Everything below the header has a fixed place and size, so a change
// redraws only its own box and never moves a neighbor.
constexpr int kMargin = 40;  // the waiting screen's
constexpr int kLeft = 24;
constexpr int kWidth = 704;  // the rows under the header, left of the meter
constexpr int kHeaderX = 100, kHeaderY = 16;
constexpr int kInfoY = 146;  // key, BPM, tempo
constexpr int kTimeY = 190;
constexpr int kProgressY = 280, kProgressH = 36;
constexpr int kBeatY = 328, kBeatH = 24, kBeatGap = 8;
constexpr int kPhaseY = 366, kPhaseH = 28, kMarkerW = 10;
constexpr int kLampY = 410, kLampH = 46, kLampGap = 12;
constexpr int kMeterX = 748, kMeterW = 28, kMeterY = kInfoY, kMeterH = kLampY + kLampH - kInfoY;

const lv_color_t kGray = lv_color_hex(0xA0A0A0);
const lv_color_t kDim = lv_color_hex(0x5A5A5A);  // an unlit lamp's text
const lv_color_t kTrack = lv_color_hex(0x262626);  // bars, unlit blocks and lamps
constexpr uint32_t kProgress = 0xE0E0E0;
constexpr uint32_t kWarning = 0xFF3B30;
constexpr uint32_t kLevel = 0x30D158;

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

/// `fraction` (0-1) of `span`, in whole pixels.
int32_t pixels(float fraction, int span) { return static_cast<int32_t>(std::lround(fraction * span)); }

/// Black is the background: a deck without a color shows white.
lv_color_t deck_color(uint32_t color) { return lv_color_hex(color == 0 ? 0xFFFFFF : color); }

}  // namespace

void DeckScreen::build() {
    lv_obj_t* screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE);

    // The deck. Every object starts as a default Face draws it: no text, bars empty, blocks and lamps off.
    deck_page_ = page(screen);
    deck_number_ = field(deck_page_, kLeft, 12, 70, &geist_mono_semibold_64, deck_color(0));

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
    progress_fill_ = box(progress, 0, 0, 0, kProgressH, lv_color_hex(kProgress));

    // The beat in the bar: four blocks, the lit one in the deck color.
    const int beat_w = (kWidth - 3 * kBeatGap) / 4;
    for (int i = 0; i < 4; ++i) {
        beats_[i] = box(deck_page_, kLeft + i * (beat_w + kBeatGap), kBeatY, beat_w, kBeatH, kTrack);
    }

    // The phase bar: a track, a center mark, and the marker, hidden while the phase is unknown.
    lv_obj_t* phase = box(deck_page_, kLeft, kPhaseY, kWidth, kPhaseH, kTrack);
    box(phase, kWidth / 2 - 1, 0, 2, kPhaseH, kGray);
    phase_px_ = pixels(shown_.phase, kWidth - kMarkerW);
    phase_marker_ = box(phase, phase_px_, 0, kMarkerW, kPhaseH, lv_color_white());
    lv_obj_add_flag(phase_marker_, LV_OBJ_FLAG_HIDDEN);

    // The lamps: lit is the lamp's color with black text.
    const int lamp_w = (kWidth - 4 * kLampGap) / 5;
    Lamp* lamps[] = {&play_, &cue_, &sync_, &master_, &loop_};
    const char* names[] = {"PLAY", "CUE", "SYNC", "MASTER", "LOOP"};
    const uint32_t colors[] = {0x30D158, 0xFF9F0A, 0x0A84FF, 0xFFD60A, 0x64D2FF};
    for (int i = 0; i < 5; ++i) {
        Lamp& lamp = *lamps[i];
        lamp.color = colors[i];
        lamp.box = box(deck_page_, kLeft + i * (lamp_w + kLampGap), kLampY, lamp_w, kLampH, kTrack);
        lv_obj_set_style_radius(lamp.box, 6, 0);
        lamp.text = field(lamp.box, 0, (kLampH - lv_font_get_line_height(small)) / 2, lamp_w, small, kDim,
                          LV_TEXT_ALIGN_CENTER);
        lv_label_set_text_static(lamp.text, names[i]);
    }
    std::snprintf(loop_text_, sizeof loop_text_, "LOOP");
    lv_label_set_text_static(loop_.text, loop_text_);

    // The level meter: a fill from the bottom.
    lv_obj_t* meter = box(deck_page_, kMeterX, kMeterY, kMeterW, kMeterH, kTrack);
    level_fill_ = box(meter, 0, 0, kMeterW, 0, lv_color_hex(kLevel));
    lv_obj_set_align(level_fill_, LV_ALIGN_BOTTOM_LEFT);

    // Waiting: the logo, then why and what to do, in the middle. The logo is opaque RGB565 at its own size and
    // untransformed, so LVGL copies it from flash with no layer and no decoded copy. 192 px: with two headline lines
    // (2x44), three detail lines (3x30) and two 12 px gaps, the column is 394 of the 400 px between the margins.
    waiting_page_ = page(screen);
    lv_obj_set_style_pad_all(waiting_page_, kMargin, 0);
    lv_obj_set_style_pad_row(waiting_page_, 12, 0);
    lv_obj_set_flex_flow(waiting_page_, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(waiting_page_, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    const int waiting_w = board::LCD_WIDTH - 2 * kMargin;
    logo_ = lv_image_create(waiting_page_);
    lv_image_set_src(logo_, &deck_logo);
    lv_obj_add_flag(logo_, LV_OBJ_FLAG_HIDDEN);
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

void DeckScreen::show_waiting(const deck_core::WaitingView& view) {
    set_text(headline_, headline_text_, view.headline);
    set_text(detail_, detail_text_, view.detail);
    set_hidden(logo_, !view.logo);
    set_hidden(deck_page_, true);
    set_hidden(waiting_page_, false);
}

void DeckScreen::show_deck(const deck_core::DeckView& view) {
    draw(deck_core::face(view));
    set_hidden(waiting_page_, true);
    set_hidden(deck_page_, false);
}

void DeckScreen::draw(const deck_core::Face& f) {
    using std::strcmp;
    const bool recolor = f.color != shown_.color;
    if (recolor) lv_obj_set_style_text_color(deck_number_, deck_color(f.color), 0);
    if (strcmp(f.deck, shown_.deck) != 0) set_text(deck_number_, deck_text_, f.deck);
    if (strcmp(f.title, shown_.title) != 0) set_text(title_, title_text_, f.title);
    if (strcmp(f.artist, shown_.artist) != 0) set_text(artist_, artist_text_, f.artist);
    if (strcmp(f.key, shown_.key) != 0) set_text(key_, key_text_, f.key);
    if (strcmp(f.bpm, shown_.bpm) != 0) set_text(bpm_, bpm_text_, f.bpm);
    if (strcmp(f.tempo, shown_.tempo) != 0) set_text(tempo_, tempo_text_, f.tempo);
    if (strcmp(f.elapsed, shown_.elapsed) != 0) set_text(elapsed_, elapsed_text_, f.elapsed);
    if (strcmp(f.remaining, shown_.remaining) != 0) set_text(remaining_, remaining_text_, f.remaining);

    // Fast: progress, phase and level move a box only when a whole pixel changes.
    const int32_t progress = pixels(f.progress, kWidth);
    if (progress != progress_px_) {
        progress_px_ = progress;
        lv_obj_set_width(progress_fill_, progress);
    }
    if (f.end_warning != shown_.end_warning) {
        lv_obj_set_style_bg_color(progress_fill_, lv_color_hex(f.end_warning ? kWarning : kProgress), 0);
    }
    if (f.beat != shown_.beat || recolor) {
        for (int i = 0; i < 4; ++i) {
            const bool was = shown_.beat == i + 1, lit = f.beat == i + 1;
            if (lit) lv_obj_set_style_bg_color(beats_[i], deck_color(f.color), 0);
            else if (was) lv_obj_set_style_bg_color(beats_[i], kTrack, 0);
        }
    }
    if (f.phase_shown) {
        const int32_t x = pixels(f.phase, kWidth - kMarkerW);
        if (x != phase_px_) {
            phase_px_ = x;
            lv_obj_set_x(phase_marker_, x);
        }
    }
    set_hidden(phase_marker_, !f.phase_shown);
    const int32_t level = pixels(f.level, kMeterH);
    if (level != level_px_) {
        level_px_ = level;
        lv_obj_set_height(level_fill_, level);
    }

    // The lamps.
    struct {
        Lamp& lamp;
        bool on, was;
    } lamps[] = {{play_, f.playing, shown_.playing}, {cue_, f.cue, shown_.cue}, {sync_, f.sync, shown_.sync},
                 {master_, f.master, shown_.master}, {loop_, f.loop, shown_.loop}};
    for (auto& l : lamps) {
        if (l.on == l.was) continue;
        lv_obj_set_style_bg_color(l.lamp.box, l.on ? lv_color_hex(l.lamp.color) : kTrack, 0);
        lv_obj_set_style_text_color(l.lamp.text, l.on ? lv_color_black() : kDim, 0);
    }
    if (strcmp(f.loop_length, shown_.loop_length) != 0) {
        char text[sizeof loop_text_] = "LOOP";
        if (f.loop_length[0]) std::snprintf(text, sizeof text, "LOOP %s", f.loop_length);
        set_text(loop_.text, loop_text_, text);
    }

    shown_ = f;
}
