// The screen stub: records what the core decided to show, as the board layer would draw it.
#pragma once

#include <string>
#include <vector>

#include "deck_core.h"

struct ScreenStub : deck_core::Screen {
    struct Shown {
        bool waiting = true;
        int deck = 0;
        uint32_t color = 0;
        std::string title;
        std::string artist;
    };
    std::vector<Shown> shown;

    void show_waiting() override { shown.push_back(Shown{}); }
    void show_deck(const deck_core::DeckView& view) override {
        shown.push_back(Shown{false, view.deck, view.color, view.title, view.artist});
    }
    const Shown& last() const { return shown.back(); }
};
