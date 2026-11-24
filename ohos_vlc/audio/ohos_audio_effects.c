/* SPDX-License-Identifier: LGPL-2.1-or-later */
#include "ohos_audio_effects.h"

#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <ohaudiosuite/native_audio_suite_engine.h>

/* One software effect, operating on decoded interleaved stereo PCM. No
 * AudioSuite symbol is required for loading the player or the aout plugin. */
#define ENGINE_API(X) \
    X(Create) X(Destroy) X(CreatePipeline) X(DestroyPipeline) X(StartPipeline) \
    X(StopPipeline) X(CreateNode) X(DestroyNode) X(ConnectNodes) X(RenderFrame) \
    X(IsNodeTypeSupported)
#define BUILDER_API(X) X(Create) X(Destroy) X(Reset) X(SetNodeType) X(SetFormat) X(SetRequestDataCallback)

#define RENDER_MS 20u
#define LOOKAHEAD_MS 60u
#define STALL_MS 120u
#define SEPARATION_LOOKAHEAD_MS 100u
#define SEPARATION_STALL_MS 160u
#define PCM_CAPACITY 65536u
#define OUTPUT_CAPACITY (48000u * 8u * RENDER_MS / 1000u)

struct ohos_audio_effects {
    void *library;
    OH_AudioSuiteEngine *engine;
    OH_AudioSuitePipeline *pipeline;
    OH_AudioNode *input, *effect, *output;
    bool started;
    unsigned frame_bytes;
    unsigned bytes_per_second;
    int stem; /* -1 for ordinary effects, 0 for vocals, 1 for accompaniment. */
    /* Keep originals until their output is committed. fed may run ahead
     * of rendered output because of effects and resampler buffering. */
    size_t head, pending, fed;
    size_t pulled, padded;
    bool invalid_pull;
#define DECLARE_ENGINE(name) __typeof__(&OH_AudioSuiteEngine_##name) engine_##name;
    ENGINE_API(DECLARE_ENGINE)
#undef DECLARE_ENGINE
    __typeof__(&OH_AudioSuiteEngine_MultiRenderFrame) engine_MultiRenderFrame;
#define DECLARE_BUILDER(name) __typeof__(&OH_AudioSuiteNodeBuilder_##name) builder_##name;
    BUILDER_API(DECLARE_BUILDER)
#undef DECLARE_BUILDER
    _Alignas(float) uint8_t scratch[OUTPUT_CAPACITY];
    _Alignas(float) uint8_t other_stem[OUTPUT_CAPACITY];
    uint8_t pcm[PCM_CAPACITY];
};

static int stem_index(int preset)
{
    if (preset == VLC_OHOS_EFFECT_VOCALS) return 0;
    if (preset == VLC_OHOS_EFFECT_ACCOMPANIMENT) return 1;
    return -1;
}

bool ohos_effects_select_stem(ohos_audio_effects *s, int preset)
{
    int stem = stem_index(preset);
    if (!s || s->stem < 0 || stem < 0)
        return false;
    s->stem = stem;
    return true;
}

static OH_AudioNode_Type preset_node(int preset)
{
    if (stem_index(preset) >= 0) return EFFECT_MULTII_OUTPUT_NODE_TYPE_AUDIO_SEPARATION;
    if (preset >= 1 && preset <= 4) return EFFECT_NODE_TYPE_SOUND_FIELD;
    if (preset >= 5 && preset <= 7) return EFFECT_NODE_TYPE_SPACE_RENDER;
    if (preset >= 8 && preset <= 11) return EFFECT_NODE_TYPE_VOICE_BEAUTIFIER;
    if (preset >= 12 && preset <= 15) return EFFECT_NODE_TYPE_ENVIRONMENT_EFFECT;
    return EFFECT_NODE_TYPE_GENERAL_VOICE_CHANGE;
}

static bool configure(ohos_audio_effects *s, int preset)
{
    /* Resolve the selected node's setter only. Older systems may expose the
     * base suite but not every effect's configuration entry point. */
#define SETTER(name) __typeof__(&OH_AudioSuiteEngine_##name) set = \
    (__typeof__(set))dlsym(s->library, "OH_AudioSuiteEngine_" #name)
    switch (preset_node(preset)) {
        case EFFECT_MULTII_OUTPUT_NODE_TYPE_AUDIO_SEPARATION:
            return true;
        case EFFECT_NODE_TYPE_SOUND_FIELD: {
            SETTER(SetSoundFieldType);
            return set && set(s->effect, (OH_SoundFieldType)preset) == AUDIOSUITE_SUCCESS;
        }
        case EFFECT_NODE_TYPE_SPACE_RENDER: {
            if (preset == 5) {
                SETTER(SetSpaceRenderPositionParams);
                OH_AudioSuite_SpaceRenderPositionParams p = { .x = 0.f, .y = 0.f, .z = 1.5f };
                return set && set(s->effect, p) == AUDIOSUITE_SUCCESS;
            }
            if (preset == 6) {
                SETTER(SetSpaceRenderRotationParams);
                OH_AudioSuite_SpaceRenderRotationParams p = {
                    .x = 0.f, .y = 0.f, .z = 1.5f,
                    .surroundTime = 16, .surroundDirection = SPACE_RENDER_CW,
                };
                return set && set(s->effect, p) == AUDIOSUITE_SUCCESS;
            }
            SETTER(SetSpaceRenderExtensionParams);
            OH_AudioSuite_SpaceRenderExtensionParams p = { .extRadius = 2.f, .extAngle = 100 };
            return set && set(s->effect, p) == AUDIOSUITE_SUCCESS;
        }
        case EFFECT_NODE_TYPE_VOICE_BEAUTIFIER: {
            SETTER(SetVoiceBeautifierType);
            return set && set(s->effect, (OH_VoiceBeautifierType)(preset - 7)) == AUDIOSUITE_SUCCESS;
        }
        case EFFECT_NODE_TYPE_ENVIRONMENT_EFFECT: {
            SETTER(SetEnvironmentType);
            return set && set(s->effect, (OH_EnvironmentType)(preset - 11)) == AUDIOSUITE_SUCCESS;
        }
        case EFFECT_NODE_TYPE_GENERAL_VOICE_CHANGE: {
            SETTER(SetGeneralVoiceChangeType);
            return set && set(s->effect, (OH_AudioSuite_GeneralVoiceChangeType)(preset - 15)) == AUDIOSUITE_SUCCESS;
        }
        default: return false;
    }
#undef SETTER
}

static bool buffer_pcm(ohos_audio_effects *s, const uint8_t *data, size_t bytes)
{
    if (!data || !bytes || bytes % s->frame_bytes != 0 ||
        bytes > PCM_CAPACITY - s->pending)
        return false;
    size_t tail = (s->head + s->pending) % PCM_CAPACITY;
    size_t first = bytes < PCM_CAPACITY - tail ? bytes : PCM_CAPACITY - tail;
    memcpy(s->pcm + tail, data, first);
    memcpy(s->pcm, data + first, bytes - first);
    s->pending += bytes;
    return true;
}

static size_t lookahead_bytes(const ohos_audio_effects *s)
{
    return s->bytes_per_second * (s->stem >= 0 ? SEPARATION_LOOKAHEAD_MS : LOOKAHEAD_MS) / 1000u;
}

size_t ohos_effects_feed_chunk(ohos_audio_effects *s, const uint8_t *data, size_t bytes)
{
    if (bytes % s->frame_bytes != 0)
        return 0;
    /* Allow an extra render quantum for prefetch. After that, interleave small
     * writes and renders so a large decoder block can't fill the entire ring
     * before a priming render has a chance to produce output. */
    size_t quantum = s->bytes_per_second * RENDER_MS / 1000u;
    size_t target = lookahead_bytes(s) + quantum;
    size_t limit = s->pending < target ? target - s->pending : quantum;
    size_t room = PCM_CAPACITY - s->pending;
    size_t chunk = bytes < limit ? bytes : limit;
    if (chunk > room)
        chunk = room;
    return buffer_pcm(s, data, chunk) ? chunk : 0;
}

size_t ohos_effects_pending(const ohos_audio_effects *s)
{
    return s ? s->pending : 0;
}

const uint8_t *ohos_effects_dry(const ohos_audio_effects *s, size_t *bytes)
{
    *bytes = s->pending < PCM_CAPACITY - s->head ? s->pending : PCM_CAPACITY - s->head;
    return s->pcm + s->head;
}

void ohos_effects_consume(ohos_audio_effects *s, size_t bytes)
{
    s->head = (s->head + bytes) % PCM_CAPACITY;
    s->pending -= bytes;
    s->fed = bytes <= s->fed ? s->fed - bytes : 0;
}

static int32_t request_pcm(OH_AudioNode *node, void *user, void *out, int32_t bytes, bool *finished)
{
    (void)node;
    ohos_audio_effects *s = user;
    *finished = false;
    if (bytes <= 0 || (size_t)bytes % s->frame_bytes != 0) {
        s->invalid_pull = true;
        if (bytes > 0 && out) {
            memset(out, 0, (size_t)bytes);
            return bytes;
        }
        return 0;
    }
    if (!out) {
        s->invalid_pull = true;
        return 0;
    }
    size_t unread = s->pending - s->fed;
    size_t n = (size_t)bytes < unread ? (size_t)bytes : unread;
    if (n > 0) {
        size_t pos = (s->head + s->fed) % PCM_CAPACITY;
        size_t first = n < PCM_CAPACITY - pos ? n : PCM_CAPACITY - pos;
        memcpy(out, s->pcm + pos, first);
        memcpy((uint8_t *)out + first, s->pcm, n - first);
        s->fed += n;
        s->pulled += n;
    }
    /* Don't block, and don't let a device repeatedly pull an empty input.
     * A render using these synthetic bytes is rejected by the caller. */
    if (n != (size_t)bytes) {
        memset((uint8_t *)out + n, 0, (size_t)bytes - n);
        s->padded += (size_t)bytes - n;
    }
    return bytes;
}

static bool node_create(ohos_audio_effects *s, OH_AudioNodeBuilder *b, OH_AudioNode_Type type,
                        const OH_AudioFormat *format, OH_AudioNode **result)
{
    return s->builder_Reset(b) == AUDIOSUITE_SUCCESS &&
           s->builder_SetNodeType(b, type) == AUDIOSUITE_SUCCESS &&
           (!format || s->builder_SetFormat(b, *format) == AUDIOSUITE_SUCCESS) &&
           (type != INPUT_NODE_TYPE_DEFAULT ||
            s->builder_SetRequestDataCallback(b, request_pcm, s) == AUDIOSUITE_SUCCESS) &&
           s->engine_CreateNode(s->pipeline, b, result) == AUDIOSUITE_SUCCESS;
}

void ohos_effects_close(ohos_audio_effects *s)
{
    if (!s) return;
    if (s->started) s->engine_StopPipeline(s->pipeline);
    if (s->output) s->engine_DestroyNode(s->output);
    if (s->effect) s->engine_DestroyNode(s->effect);
    if (s->input) s->engine_DestroyNode(s->input);
    if (s->pipeline) s->engine_DestroyPipeline(s->pipeline);
    if (s->engine) s->engine_Destroy(s->engine);
    if (s->library) dlclose(s->library);
    free(s);
}

ohos_audio_effects *ohos_effects_open(int preset, unsigned rate, ohos_pcm_type pcm)
{
    if (preset < 1 || preset > VLC_OHOS_EFFECT_MAX || (rate != 44100 && rate != 48000))
        return NULL;
    OH_Audio_SampleFormat sample;
    switch (pcm) {
        case OHOS_PCM_S16: sample = AUDIO_SAMPLE_S16LE; break;
        case OHOS_PCM_S32: sample = AUDIO_SAMPLE_S32LE; break;
        case OHOS_PCM_FLOAT: sample = AUDIO_SAMPLE_F32LE; break;
        default: return NULL;
    }
    OH_AudioFormat format = {
        .samplingRate = (OH_Audio_SampleRate)rate,
        .channelLayout = CH_LAYOUT_STEREO, .channelCount = 2,
        .encodingType = AUDIO_ENCODING_TYPE_RAW, .sampleFormat = sample,
    };
    ohos_audio_effects *s = calloc(1, sizeof(*s));
    if (!s) return NULL;
    s->frame_bytes = pcm == OHOS_PCM_S16 ? 4 : 8;
    s->bytes_per_second = rate * s->frame_bytes;
    s->stem = stem_index(preset);
    OH_AudioNodeBuilder *builder = NULL;
    s->library = dlopen("libohaudiosuite.so", RTLD_NOW | RTLD_LOCAL);
    if (!s->library) goto error;
#define LOAD_ENGINE(name) \
    s->engine_##name = (__typeof__(s->engine_##name))dlsym(s->library, "OH_AudioSuiteEngine_" #name); \
    if (!s->engine_##name) goto error;
    ENGINE_API(LOAD_ENGINE)
    if (s->stem >= 0) {
        LOAD_ENGINE(MultiRenderFrame)
    }
#undef LOAD_ENGINE
#define LOAD_BUILDER(name) \
    s->builder_##name = (__typeof__(s->builder_##name))dlsym(s->library, "OH_AudioSuiteNodeBuilder_" #name); \
    if (!s->builder_##name) goto error;
    BUILDER_API(LOAD_BUILDER)
#undef LOAD_BUILDER
    OH_AudioNode_Type node = preset_node(preset);
    bool supported = false;
    if (s->engine_IsNodeTypeSupported(node, &supported) != AUDIOSUITE_SUCCESS || !supported ||
        s->engine_Create(&s->engine) != AUDIOSUITE_SUCCESS ||
        s->engine_CreatePipeline(s->engine, &s->pipeline, AUDIOSUITE_PIPELINE_REALTIME_MODE) != AUDIOSUITE_SUCCESS ||
        s->builder_Create(&builder) != AUDIOSUITE_SUCCESS ||
        !node_create(s, builder, INPUT_NODE_TYPE_DEFAULT, &format, &s->input) ||
        !node_create(s, builder, node, NULL, &s->effect) ||
        !node_create(s, builder, OUTPUT_NODE_TYPE_DEFAULT, &format, &s->output) ||
        !configure(s, preset) ||
        s->engine_ConnectNodes(s->input, s->effect) != AUDIOSUITE_SUCCESS ||
        s->engine_ConnectNodes(s->effect, s->output) != AUDIOSUITE_SUCCESS ||
        s->engine_StartPipeline(s->pipeline) != AUDIOSUITE_SUCCESS)
        goto error;
    s->started = true;
    s->builder_Destroy(builder);
    return s;
error:
    if (builder) s->builder_Destroy(builder);
    ohos_effects_close(s);
    return NULL;
}

ohos_effect_result ohos_effects_render(ohos_audio_effects *s, const uint8_t **output,
                                      size_t *bytes, ohos_effect_report *report)
{
    *output = NULL;
    *bytes = 0;
    *report = (ohos_effect_report){0};
    /* Request a fixed render quantum, not an arbitrary decoder block size.
     * At 44.1 kHz stereo float the input node alone pulls 7056 bytes (20 ms).
     * Reserve several quanta so effects can pull ahead without padding. */
    if (s->pending < lookahead_bytes(s))
        return OHOS_EFFECT_WAIT;
    s->pulled = s->padded = 0;
    s->invalid_pull = false;
    report->requested = s->bytes_per_second * RENDER_MS / 1000u;
    if (s->stem >= 0) {
        /* Both buffers use the configured output-node format, identical to
         * the renderer. AudioSuite converts the model's 48 kHz float PCM. */
        void *outputs[2];
        outputs[s->stem] = s->scratch;
        outputs[1 - s->stem] = s->other_stem;
        OH_AudioDataArray array = {
            .audioDataArray = outputs, .arraySize = 2,
            .requestFrameSize = (int32_t)report->requested,
        };
        report->status = s->engine_MultiRenderFrame(s->pipeline, &array,
                                                   &report->returned, &report->finished);
    } else {
        report->status = s->engine_RenderFrame(s->pipeline, s->scratch, (int32_t)report->requested,
                                              &report->returned, &report->finished);
    }
    report->pulled = s->pulled;
    report->padded = s->padded;
    if (s->invalid_pull)
        report->reason = "invalid input request";
    else if (s->padded)
        report->reason = "input exhausted during render";
    else if (report->status != AUDIOSUITE_SUCCESS)
        report->reason = "engine render error";
    else if (report->finished)
        report->reason = "unexpected end of stream";
    else if (report->returned < 0 || (size_t)report->returned > report->requested ||
             (size_t)report->returned % s->frame_bytes != 0 ||
             (size_t)report->returned > s->fed)
        report->reason = "invalid render output size";
    else if (report->returned > 0) {
        *output = s->scratch;
        *bytes = (size_t)report->returned;
        return OHOS_EFFECT_READY;
    } else if (s->pending >= s->bytes_per_second *
               (s->stem >= 0 ? SEPARATION_STALL_MS : STALL_MS) / 1000u) {
        report->reason = "no render progress";
    } else {
        return OHOS_EFFECT_WAIT;
    }
    return OHOS_EFFECT_ERROR;
}
