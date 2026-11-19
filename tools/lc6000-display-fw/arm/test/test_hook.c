// The hook's portable logic (#467), built natively: what the stock firmware's two hook sites hand our code, and what
// our code does with it. The stock side (uptime counter, receive count, malloc, reset witness) is simulated here.
#include <string.h>

#include "harness.h"
#include "hook.h"
#include "draw.h"
#include "upper.h"

#define CAPABILITY_V1 "F0 00 02 0B 7F 10 20 00 02 00 01 F7"
#define BEGIN_V1 "F0 00 02 0B 7F 10 20 00 02 01 01 F7"
#define DECK_2_RED_TRACK "F0 00 02 0B 7F 10 20 00 09 03 02 01 7F 00 00 00 00 01 F7"
#define END_V1 "F0 00 02 0B 7F 10 20 00 02 02 01 F7"
#define STATE_LOADED_PLAYING "F0 00 02 0B 7F 10 20 00 02 07 03 F7"

/// The simulated stock firmware: its RAM, its malloc, and our state's untouched top-of-SRAM home.
static struct {
    uint32_t uptime;
    uint8_t witness;
    uint16_t rx_count;
    uint8_t rx[0x200];
    int mallocs;
    int malloc_fails;
    int hides;
    dfw_pixel heap[DFW_SIZE * DFW_SIZE];
} chip;
static hook_state state;
static recording rec;
static hook_stock stock;
/// Our marker word as the flash holds it: present after a good placement, 0xFFFFFFFF where nothing was placed.
static uint32_t marker_word;

static void *stock_malloc(size_t size) {
    chip.mallocs++;
    if (chip.malloc_fails || size > sizeof chip.heap) return NULL;
    return chip.heap;
}

static void hide(void) { chip.hides++; }

static void present(void *ctx, const dfw_pixel *frame) { (void)frame; ((recording *)ctx)->presents++; }
static void send(void *ctx, const uint8_t *bytes, size_t length) {
    recording *r = ctx;
    r->sends++;
    r->sent_length = length;
    memcpy(r->sent, bytes, length < sizeof r->sent ? length : sizeof r->sent);
}

/// Power-on: stock RAM is zeroed (.bss) and the witness reads 0; our state keeps whatever was there.
static void power_on(void) {
    chip.uptime = 0;
    chip.witness = 0;
    chip.rx_count = 0;
    chip.mallocs = 0;
    chip.malloc_fails = 0;
    chip.hides = 0;
    memset(&rec, 0, sizeof rec);
    marker_word = HOOK_MARKER;
    stock = (hook_stock){ .marker = &marker_word, .uptime = &chip.uptime, .witness = &chip.witness, .rx_count = &chip.rx_count,
                          .malloc = stock_malloc, .hide = hide, .port = { .present = present, .send = send, .ctx = &rec },
                          .drawing = &dfw_drawn };
}

/// A cold first boot: our state is SRAM garbage too.
static void cold_boot(void) {
    memset(&state, 0xA5, sizeof state);
    power_on();
}

/// Puts one message in the stock receive buffer as the dispatcher sees it, and calls the command entry.
static void deliver(uint8_t cmd_override, const char *hex) {
    size_t n = parse_hex(hex, chip.rx, sizeof chip.rx);
    if (cmd_override) chip.rx[6] = cmd_override;
    chip.rx_count = (uint16_t)n;
    uint32_t len = ((uint32_t)chip.rx[7] << 7) | chip.rx[8];
    hook_command(&state, &stock, chip.rx[6], chip.rx, len);
    chip.uptime += 10;
}

static void tick(void) {
    hook_tick(&state, &stock);
    chip.uptime += 10;
}

static void drawing_session(void) {
    deliver(0, CAPABILITY_V1);
    deliver(0, BEGIN_V1);
    deliver(0, DECK_2_RED_TRACK);
    tick();
}

void the_tick_does_nothing_before_our_first_message(void) {
    cold_boot();
    for (int i = 0; i < 100; i++) tick();
    CHECK(rec.presents == 0 && rec.sends == 0 && chip.mallocs == 0);
}

void a_capability_ask_allocates_the_frame_once_and_is_answered(void) {
    cold_boot();
    deliver(0, CAPABILITY_V1);
    deliver(0, CAPABILITY_V1);
    deliver(0, CAPABILITY_V1);
    tick();
    CHECK(chip.mallocs == 1);
    CHECK(rec.sends == 3);
    CHECK(state.unit.frame == chip.heap);
}

void a_failed_allocation_means_no_answer_and_no_second_try(void) {
    cold_boot();
    chip.malloc_fails = 1;
    deliver(0, CAPABILITY_V1);
    deliver(0, CAPABILITY_V1);
    tick();
    CHECK(chip.mallocs == 1);
    CHECK(rec.sends == 0);
}

void begin_with_no_frame_allocates_it(void) {
    cold_boot();
    deliver(0, BEGIN_V1);
    deliver(0, DECK_2_RED_TRACK);
    tick();
    CHECK(chip.mallocs == 1);
    CHECK(state.unit.drawn == 1);
    CHECK(rec.presents == 1);
}

void begin_after_a_failed_allocation_stays_in_stock_mode(void) {
    // begin is passed on (agent3, #491): with no frame dfw presents nothing, so the screen is never taken.
    cold_boot();
    chip.malloc_fails = 1;
    deliver(0, BEGIN_V1);
    deliver(0, DECK_2_RED_TRACK);
    deliver(0, BEGIN_V1);
    tick();
    CHECK(chip.mallocs == 1);
    CHECK(rec.presents == 0 && chip.hides == 0);
}

void a_repeated_begin_never_allocates_again(void) {
    cold_boot();
    drawing_session();
    for (int i = 0; i < 5; i++) deliver(0, BEGIN_V1);
    tick();
    CHECK(chip.mallocs == 1);
}

void other_commands_are_left_to_stock(void) {
    cold_boot();
    deliver(0x7F, CAPABILITY_V1);
    deliver(0x21, BEGIN_V1);
    deliver(0x72, BEGIN_V1);
    tick();
    CHECK(chip.mallocs == 0 && rec.sends == 0 && state.magic != HOOK_MAGIC);
}

void a_message_longer_than_the_bytes_received_is_ignored(void) {
    cold_boot();
    size_t n = parse_hex(CAPABILITY_V1, chip.rx, sizeof chip.rx);
    chip.rx_count = (uint16_t)(n - 1);  // the F7 hasn't arrived
    hook_command(&state, &stock, 0x20, chip.rx, 2);
    tick();
    CHECK(chip.mallocs == 0 && rec.sends == 0);
}

void a_message_without_f7_at_its_declared_end_is_ignored(void) {
    cold_boot();
    size_t n = parse_hex(CAPABILITY_V1, chip.rx, sizeof chip.rx);
    chip.rx[n - 1] = 0x00;
    chip.rx[n] = 0xF7;
    chip.rx_count = (uint16_t)(n + 1);
    hook_command(&state, &stock, 0x20, chip.rx, 2);
    tick();
    CHECK(chip.mallocs == 0 && rec.sends == 0);
}

void without_the_marker_nothing_runs(void) {
    cold_boot();
    marker_word = 0xFFFFFFFFu;
    deliver(0, CAPABILITY_V1);
    deliver(0, BEGIN_V1);
    tick();
    CHECK(chip.mallocs == 0 && rec.sends == 0 && rec.presents == 0);
}

void messages_are_copied_out_of_the_stock_buffer(void) {
    // begin, deck and state can share one USB packet; stock reuses its buffer, so nothing may point into it.
    cold_boot();
    deliver(0, BEGIN_V1);
    memset(chip.rx, 0x00, sizeof chip.rx);
    deliver(0, DECK_2_RED_TRACK);
    memset(chip.rx, 0x00, sizeof chip.rx);
    deliver(0, STATE_LOADED_PLAYING);
    memset(chip.rx, 0x00, sizeof chip.rx);
    tick();
    CHECK(state.unit.drawn == 1);
    CHECK(state.unit.deck.number == 2 && state.unit.deck.r == 255 && state.unit.deck.g == 0);
    CHECK(state.unit.flags == 3);
}

void a_reboot_seen_through_the_witness_resets_drawn_mode(void) {
    // The required case: the first call after the reboot comes later than the count saved before it, so the
    // uptime comparison alone can't see the reboot. The witness (cleared by every reset) does.
    cold_boot();
    drawing_session();
    CHECK(state.unit.drawn == 1);
    uint32_t saved = state.last_uptime;
    power_on();
    chip.uptime = saved + 100000;
    for (int i = 0; i < 10; i++) tick();
    CHECK(rec.presents == 0);
    CHECK(state.magic != HOOK_MAGIC);
    deliver(0, DECK_2_RED_TRACK);  // a stray message doesn't bring drawing back: the unit starts fresh, not drawn
    tick();
    CHECK(state.unit.drawn == 0 && state.unit.frame == NULL && rec.presents == 0);
    deliver(0, BEGIN_V1);
    tick();
    CHECK(chip.mallocs == 1);  // the new boot's heap, allocated afresh
}

void without_the_witness_a_late_first_call_keeps_the_old_session(void) {
    // What the uptime comparison alone would do in the required case: it misses the reboot, keeps drawn mode and a
    // frame pointer into the old boot's heap. That's why the hook doesn't rely on it alone.
    cold_boot();
    drawing_session();
    uint32_t saved = state.last_uptime;
    power_on();
    stock.witness = NULL;
    chip.uptime = saved + 100000;
    tick();
    CHECK(state.magic == HOOK_MAGIC && state.unit.drawn == 1);
}

void an_uptime_that_went_backwards_resets_too(void) {
    cold_boot();
    drawing_session();
    chip.witness = 0xF0;  // say the witness survived (it can't, but the counter alone must still catch this)
    chip.uptime = 5;
    tick();
    CHECK(state.magic != HOOK_MAGIC);
}

void a_counter_wrap_keeps_the_session_and_its_frame(void) {
    // The 100 us counter wraps after 4.97 days. A false reset there would drop the frame and allocate again later:
    // a 157 KB leak every wrap. A backwards step from within 10 s of the top is a wrap, not a reboot.
    cold_boot();
    chip.uptime = 0xFFFFFF00u;
    drawing_session();
    chip.uptime = 0x10;
    tick();
    CHECK(state.magic == HOOK_MAGIC && state.unit.drawn == 1);
    deliver(0, BEGIN_V1);
    deliver(0, CAPABILITY_V1);
    tick();
    CHECK(chip.mallocs == 1);
}

void a_backwards_step_from_low_in_the_count_is_a_reboot(void) {
    cold_boot();
    chip.uptime = 0xFFFFFFFFu - 200000u;  // 20 s below the top: outside the 10 s wrap window
    drawing_session();
    chip.witness = HOOK_WITNESS;  // only the counter can tell here
    chip.uptime = 0x10;
    chip.mallocs = 0;
    tick();
    CHECK(state.magic != HOOK_MAGIC);
    deliver(0, BEGIN_V1);
    tick();
    CHECK(chip.mallocs == 1);  // one malloc in the new boot's heap
}

/// Ticks with the 100 us counter `units` further on, in one step.
static void tick_after(uint32_t units) {
    chip.uptime += units;
    hook_tick(&state, &stock);
}

void three_seconds_of_silence_turn_the_screen_stale(void) {
    // dfw's clock is milliseconds; the stock counter is 100 us, so 30,000 counts are 3 s (#464).
    cold_boot();
    drawing_session();
    tick_after(29000);
    CHECK(!dfw_stale(&state.unit));
    tick_after(2000);
    CHECK(dfw_stale(&state.unit));
}

void the_millisecond_clock_runs_on_across_a_counter_wrap(void) {
    // counter / 10 would jump back by 429,496 ms at the wrap and look like a long silence; our clock doesn't.
    cold_boot();
    chip.uptime = 0xFFFFFF00u;
    drawing_session();
    tick_after(20000);  // 2 s on, across the wrap
    CHECK(state.magic == HOOK_MAGIC);
    CHECK(!dfw_stale(&state.unit));
    tick_after(11000);
    CHECK(dfw_stale(&state.unit));
}

void garbage_with_the_magic_but_a_bad_check_word_is_fresh_state(void) {
    cold_boot();
    state.magic = HOOK_MAGIC;
    state.check = 0;
    state.unit.drawn = 1;
    chip.witness = 0xF0;
    for (int i = 0; i < 5; i++) tick();
    CHECK(rec.presents == 0);
    deliver(0, DECK_2_RED_TRACK);
    tick();
    CHECK(state.unit.drawn == 0);
}

void end_hands_the_screen_back_once(void) {
    cold_boot();
    drawing_session();
    CHECK(rec.presents == 1 && chip.hides == 0);
    deliver(0, END_V1);
    tick();
    tick();
    CHECK(chip.hides == 1);
    deliver(0, BEGIN_V1);
    deliver(0, DECK_2_RED_TRACK);
    tick();
    CHECK(rec.presents == 2 && chip.hides == 1);
}

void nothing_is_hidden_that_was_never_shown(void) {
    cold_boot();
    deliver(0, CAPABILITY_V1);
    deliver(0, END_V1);
    tick();
    CHECK(chip.hides == 0);
}

/// Block B as the upper flash holds it (#501): erased, unless a test writes one. The good one's CRC, 0x22B5DF72, is
/// zlib's CRC-32 of its bytes from +16 to its end (worked out with Python's zlib, not this code).
static uint8_t upper[0x80000]; /* the upper flash: sectors 8-11 */

static void put_word(uint8_t *at, uint32_t word) {
    for (int i = 0; i < 4; i++) at[i] = (uint8_t)(word >> (8 * i));
}

static void good_upper(void) {
    memset(upper, 0xFF, sizeof upper);
    put_word(upper + 0, UPPER_MARKER);
    put_word(upper + 4, UPPER_VERSION);
    put_word(upper + 8, 29);
    put_word(upper + 12, 0x22B5DF72u);
    put_word(upper + 16, 0x08080015u);
    memcpy(upper + 20, "123456789", 9);
}

void a_good_upper_block_gives_its_draw_entry(void) {
    good_upper();
    CHECK(upper_check(upper) == 0x08080015u);
}

void erased_upper_flash_has_no_block(void) {
    memset(upper, 0xFF, sizeof upper);
    CHECK(upper_check(upper) == 0);
}

void a_block_for_another_version_is_refused(void) {
    good_upper();
    put_word(upper + 4, UPPER_VERSION + 1);
    CHECK(upper_check(upper) == 0);
}

void a_block_whose_CRC_doesnt_match_is_refused(void) {
    good_upper();
    upper[24] ^= 1;
    CHECK(upper_check(upper) == 0);
}

void a_length_past_the_sector_or_inside_the_header_is_refused(void) {
    good_upper();
    put_word(upper + 8, UPPER_LIMIT + 4);
    CHECK(upper_check(upper) == 0);
    put_word(upper + 8, UPPER_HEADER - 1);
    CHECK(upper_check(upper) == 0);
    put_word(upper + 8, 0);
    CHECK(upper_check(upper) == 0);
}

void an_entry_that_isnt_Thumb_code_inside_the_block_is_refused(void) {
    // Each entry with its own good CRC (Python's zlib), so only the entry check can refuse it.
    static const struct { uint32_t entry, crc; } bad[] = {
        { 0x08080014u, 0xFF2306F7u }, /* no Thumb bit */
        { 0x0808001Fu, 0x18EAB954u }, /* past the end of B */
        { 0x08080011u, 0xE20CB5E4u }, /* inside the header */
        { 0x00000015u, 0x8BA17EC3u }, /* nowhere near B */
    };
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        good_upper();
        put_word(upper + 16, bad[i].entry);
        put_word(upper + 12, bad[i].crc);
        CHECK(upper_check(upper) == 0);
    }
}

void a_block_past_sector_8_is_checked_whole(void) {
    // 0x20020 bytes: past sector 8 into sector 9, zeros after the good B's bytes. CRC from Python's zlib.
    good_upper();
    memset(upper + 29, 0, 0x20020 - 29);
    put_word(upper + 8, 0x20020);
    put_word(upper + 12, 0x40575571u);
    CHECK(upper_check(upper) == 0x08080015u);
    upper[0x2001F] = 1;
    CHECK(upper_check(upper) == 0);
}

/// The hook block draws only with the table stock hands it (#501): with none (the drawing block not yet checked), the
/// capability ask gets no answer and nothing is drawn, so the app falls back to images.
void with_no_drawing_from_stock_the_capability_ask_gets_no_answer(void) {
    cold_boot();
    stock.drawing = NULL;
    deliver(0, CAPABILITY_V1);
    deliver(0, BEGIN_V1);
    deliver(0, DECK_2_RED_TRACK);
    tick();
    CHECK(rec.sends == 0 && rec.presents == 0);
}

const test_case all_tests[] = {
    { "with no drawing from stock the capability ask gets no answer",
      with_no_drawing_from_stock_the_capability_ask_gets_no_answer },
    { "end hands the screen back once", end_hands_the_screen_back_once },
    { "nothing is hidden that was never shown", nothing_is_hidden_that_was_never_shown },
    { "the tick does nothing before our first message", the_tick_does_nothing_before_our_first_message },
    { "a capability ask allocates the frame once and is answered", a_capability_ask_allocates_the_frame_once_and_is_answered },
    { "a failed allocation means no answer and no second try", a_failed_allocation_means_no_answer_and_no_second_try },
    { "begin with no frame allocates it", begin_with_no_frame_allocates_it },
    { "begin after a failed allocation stays in stock mode", begin_after_a_failed_allocation_stays_in_stock_mode },
    { "a repeated begin never allocates again", a_repeated_begin_never_allocates_again },
    { "other commands are left to stock", other_commands_are_left_to_stock },
    { "a message longer than the bytes received is ignored", a_message_longer_than_the_bytes_received_is_ignored },
    { "a message without F7 at its declared end is ignored", a_message_without_f7_at_its_declared_end_is_ignored },
    { "without the marker nothing runs", without_the_marker_nothing_runs },
    { "messages are copied out of the stock buffer", messages_are_copied_out_of_the_stock_buffer },
    { "a reboot seen through the witness resets drawn mode", a_reboot_seen_through_the_witness_resets_drawn_mode },
    { "without the witness a late first call keeps the old session", without_the_witness_a_late_first_call_keeps_the_old_session },
    { "an uptime that went backwards resets too", an_uptime_that_went_backwards_resets_too },
    { "a counter wrap keeps the session and its frame", a_counter_wrap_keeps_the_session_and_its_frame },
    { "a backwards step from low in the count is a reboot", a_backwards_step_from_low_in_the_count_is_a_reboot },
    { "garbage with the magic but a bad check word is fresh state", garbage_with_the_magic_but_a_bad_check_word_is_fresh_state },
    { "three seconds of silence turn the screen stale", three_seconds_of_silence_turn_the_screen_stale },
    { "the millisecond clock runs on across a counter wrap", the_millisecond_clock_runs_on_across_a_counter_wrap },
    { "a good upper block gives its draw entry", a_good_upper_block_gives_its_draw_entry },
    { "erased upper flash has no block", erased_upper_flash_has_no_block },
    { "a block for another version is refused", a_block_for_another_version_is_refused },
    { "a block whose CRC doesn't match is refused", a_block_whose_CRC_doesnt_match_is_refused },
    { "a length past the sector or inside the header is refused", a_length_past_the_sector_or_inside_the_header_is_refused },
    { "an entry that isn't Thumb code inside the block is refused", an_entry_that_isnt_Thumb_code_inside_the_block_is_refused },
    { "a block past sector 8 is checked whole", a_block_past_sector_8_is_checked_whole },
    { 0, 0 },
};

/// The shared harness also walks agent3's drawing table; the hook's tests have none of their own.
const test_case draw_tests[] = { { 0, 0 } };
const test_case draw_live_tests[] = { { 0, 0 } };
