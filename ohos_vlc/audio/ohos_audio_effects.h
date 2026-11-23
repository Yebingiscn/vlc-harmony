/* SPDX-License-Identifier: LGPL-2.1-or-later */
#ifndef VLC_OHOS_AUDIO_EFFECTS_H
#define VLC_OHOS_AUDIO_EFFECTS_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

/* Stable preset IDs shared with AudioEffectsDialog. Never renumber them. */
#define VLC_OHOS_EFFECT_MAX 25
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
/* Returned buffer is owned by the effect; NULL means enqueue the original PCM. */
const uint8_t *ohos_effects_render(ohos_audio_effects *, const uint8_t *, size_t);

#endif
