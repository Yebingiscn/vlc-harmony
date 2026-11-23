/* SPDX-License-Identifier: LGPL-2.1-or-later */
#ifndef VLC_OHOS_AUDIO_EFFECTS_H
#define VLC_OHOS_AUDIO_EFFECTS_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

/* Stable preset IDs shared with AudioEffectsDialog. Never renumber them. */
#define VLC_OHOS_EFFECT_ACCOMPANIMENT 26
#define VLC_OHOS_EFFECT_VOCALS 27
#define VLC_OHOS_EFFECT_MAX VLC_OHOS_EFFECT_VOCALS
#define VLC_OHOS_EFFECT_VAR "ohos-audio-effect"
#define VLC_OHOS_EFFECT_STATUS_VAR "ohos-audio-effect-status"

typedef struct ohos_audio_effects ohos_audio_effects;
typedef enum {
    OHOS_PCM_S16,
    OHOS_PCM_S32,
    OHOS_PCM_FLOAT,
} ohos_pcm_type;

ohos_audio_effects *ohos_effects_open(int preset, unsigned rate, ohos_pcm_type type);
void ohos_effects_close(ohos_audio_effects *effect);
/* A stem-only switch can reuse the running separation model and its PCM. */
bool ohos_effects_select_stem(ohos_audio_effects *, int preset);

typedef enum {
    OHOS_EFFECT_WAIT,   /* Keep the graph; more input may produce output. */
    OHOS_EFFECT_READY,
    OHOS_EFFECT_ERROR,  /* Play the uncommitted dry PCM before closing the graph. */
} ohos_effect_result;

typedef struct {
    const char *reason;
    int status;
    size_t requested, pulled, padded;
    int32_t returned;
    bool finished;
} ohos_effect_report;

bool ohos_effects_feed(ohos_audio_effects *, const uint8_t *, size_t);
size_t ohos_effects_pending(const ohos_audio_effects *);
/* Peek the oldest contiguous dry PCM, including bytes already pulled by the graph. */
const uint8_t *ohos_effects_dry(const ohos_audio_effects *, size_t *);
void ohos_effects_consume(ohos_audio_effects *, size_t);
/* READY leaves output ownership with the effect until the next render.
 * The caller commits those bytes with consume() only after accepting the result. */
ohos_effect_result ohos_effects_render(ohos_audio_effects *, const uint8_t **,
                                      size_t *, ohos_effect_report *);

#endif
