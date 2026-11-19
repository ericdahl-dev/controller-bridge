// The drawn display's text (#458): measuring and drawing lines of Windows-1252 codes in the Geist faces the renderer
// uses, laid out as CoreText lays out the renderer's lines (see gen/text_font_gen.swift for what was measured).
#ifndef DFW_TEXT_H
#define DFW_TEXT_H
#include <stddef.h>
#include <stdint.h>

typedef struct dfw_text_face dfw_text_face;

/// Geist-Bold 26 (the one-line title; an untitled deck's words), Geist-Bold 20 (the title on two lines), Geist-Medium
/// 16 (the artist; an untitled deck's caption), GeistMono-SemiBold 22 (key and BPM).
extern const dfw_text_face *const dfw_title26, *const dfw_title20, *const dfw_caption16, *const dfw_mono22;

/// A line's width in pixels. `tracked`: the one-line title's tracking and kerning (the face's own; no other line has
/// either, as the renderer's lines have neither).
float dfw_text_width(const dfw_text_face *face, const uint8_t *codes, size_t count, int tracked);

#endif
