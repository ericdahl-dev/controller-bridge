#include "hook.h"

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

static void start(hook_state *state, const hook_stock *stock, uint32_t now) {
    const dfw_port port = { .present = present, .send = send, .ctx = state };
    state->stock = stock;
    dfw_init(&state->unit, &port, NULL);
    state->malloc_tried = 0;
    state->shown = 0;
    state->last_uptime = now;
    state->magic = HOOK_MAGIC;
    state->check = ~HOOK_MAGIC;
    if (stock->witness) *stock->witness = HOOK_WITNESS;
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
    state->last_uptime = now;
    state->stock = stock;
    uint8_t op = msg[9];
    if (op == OP_CAPABILITY || op == OP_BEGIN) ensure_frame(state, stock);
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
    state->last_uptime = now;
    state->stock = stock;
    dfw_tick(&state->unit);
    if (state->shown && !state->unit.drawn) {
        state->shown = 0;
        stock->hide();
    }
}
