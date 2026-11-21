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
        std::string headline;  ///< the waiting screen's
        std::string detail;
        bool logo = false;  ///< the waiting screen's DeckBridge logo
        deck_core::DeckView view;  ///< the whole deck view, as shown
    };
    std::vector<Shown> shown;

    void show_waiting(const deck_core::WaitingView& view) override {
        Shown s;
        s.headline = view.headline;
        s.detail = view.detail;
        s.logo = view.logo;
        shown.push_back(s);
    }
    void show_deck(const deck_core::DeckView& view) override {
        Shown s;
        s.waiting = false;
        s.deck = view.deck;
        s.color = view.color;
        s.title = view.title;
        s.artist = view.artist;
        s.view = view;
        shown.push_back(s);
    }
    const Shown& last() const { return shown.back(); }
};
