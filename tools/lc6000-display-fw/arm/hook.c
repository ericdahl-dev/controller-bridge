#include "hook.h"
#include "upper.h"

/// The ops that may need the frame (#456): the capability ask and begin.
enum { OP_CAPABILITY = 0x00, OP_BEGIN = 0x01 };

static int marker_present(const hook_stock *stock) { return *stock->marker == HOOK_MARKER; }

static int valid(const hook_state *state) { return state->magic == HOOK_MAGIC && state->check == ~HOOK_MAGIC; }

/// The counter wraps after 4.97 days: a backwards step from within 10 s of the top is that, not a reboot.
#define HOOK_WRAP_WINDOW 100000u

/// A reset since our state was last good: the witness was cleared, or the uptime counter went back other than by
/// wrapping (a reboot whose first call came early).
static int reset_seen(const hook_state *state, const hook_stock *stock, uint32_t now) {
    if (stock->witness && *stock->witness == 0) return 1;
    return now < state->last_uptime && state->last_uptime < 0xFFFFFFFFu - HOOK_WRAP_WINDOW;
}

/// Our port to dfw: it notes that the screen is ours, then presents through stock's side.
static void present(void *ctx, const dfw_pixel *frame) {
    hook_state *state = ctx;
    state->shown = 1;
    state->stock->port.present(state->stock->port.ctx, frame);
}

static void send(void *ctx, const uint8_t *bytes, size_t length) {
    hook_state *state = ctx;
    state->stock->port.send(state->stock->port.ctx, bytes, length);
}

/// Moves our clock on by the counter's step since we last looked (unsigned, so a wrap is just a step).
static void advance(hook_state *state, uint32_t now) {
    state->sub_ms += now - state->last_uptime;
    state->now_ms += state->sub_ms / 10;
    state->sub_ms %= 10;
    state->last_uptime = now;
}

static void start(hook_state *state, const hook_stock *stock, uint32_t now) {
    const dfw_port port = { .present = present, .send = send, .ctx = state };
    state->stock = stock;
    // With block B given, B alone decides the drawing (#501).
    dfw_init(&state->unit, &port, NULL, stock->upper ? NULL : stock->drawing);
    state->malloc_tried = 0;
    state->shown = 0;
    state->last_uptime = now;
    state->now_ms = 0;
    state->sub_ms = 0;
    state->upper_checked = 0;
    state->magic = HOOK_MAGIC;
    state->check = ~HOOK_MAGIC;
    if (stock->witness) *stock->witness = HOOK_WITNESS;
}

/// Checks B once per boot, at the first capability ask or begin (#501): about 1 ms for today's B, 45 ms for all
/// 512 KB, once. Never at boot, so our code still runs only after our first message. Once B checks out, the unit
/// draws through B's entry.
static void check_upper(hook_state *state, const hook_stock *stock) {
    if (!stock->upper || state->upper_checked) return;
    state->upper_checked = 1;
    uint32_t entry = upper_check(stock->upper);
    if (!entry) return;
    state->upper_drawing.draw = (void (*)(dfw_pixel *, const struct dfw_unit *))(uintptr_t)entry;
    state->unit.drawing = &state->upper_drawing;
}

/// The one stock malloc, ever, per boot: a frame for the capability ask or begin. Never freed.
static void ensure_frame(hook_state *state, const hook_stock *stock) {
    if (state->unit.frame || state->malloc_tried) return;
    state->malloc_tried = 1;
    dfw_pixel *frame = stock->malloc(sizeof(dfw_pixel) * DFW_SIZE * DFW_SIZE);
    if (frame) dfw_set_frame(&state->unit, frame);
}

void hook_command(hook_state *state, const hook_stock *stock, uint8_t cmd, const uint8_t *msg, uint32_t len) {
    if (cmd != HOOK_CMD || !marker_present(stock)) return;
    uint32_t total = len + 10;
    if (len == 0 || total > *stock->rx_count || msg[9 + len] != 0xF7) return;
    uint32_t now = *stock->uptime;
    if (!valid(state) || reset_seen(state, stock, now)) start(state, stock, now);
    advance(state, now);
    state->stock = stock;
    uint8_t op = msg[9];
    if (op == OP_CAPABILITY || op == OP_BEGIN) {
        check_upper(state, stock);
        ensure_frame(state, stock);
    }
    // A begin with no frame is still passed on: dfw then presents nothing, so the screen stays stock's.
    dfw_message(&state->unit, msg, total);
}

void hook_tick(hook_state *state, const hook_stock *stock) {
    if (!marker_present(stock) || !valid(state)) return;
    uint32_t now = *stock->uptime;
    if (reset_seen(state, stock, now)) {
        state->magic = 0;
        return;
    }
    advance(state, now);
    state->stock = stock;
    dfw_tick(&state->unit, state->now_ms);
    if (state->shown && !state->unit.drawn) {
        state->shown = 0;
        stock->hide();
    }
}
