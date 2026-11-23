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

struct ohos_audio_effects {
    void *library;
    OH_AudioSuiteEngine *engine;
    OH_AudioSuitePipeline *pipeline;
    OH_AudioNode *input, *effect, *output;
    bool started;
    unsigned frame_bytes;
    const uint8_t *input_data;
    size_t input_left;
    bool padded;
#define DECLARE_ENGINE(name) __typeof__(&OH_AudioSuiteEngine_##name) engine_##name;
    ENGINE_API(DECLARE_ENGINE)
#undef DECLARE_ENGINE
#define DECLARE_BUILDER(name) __typeof__(&OH_AudioSuiteNodeBuilder_##name) builder_##name;
    BUILDER_API(DECLARE_BUILDER)
#undef DECLARE_BUILDER
    uint8_t scratch[65536];
};

static OH_AudioNode_Type preset_node(int preset)
{
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

static int32_t request_pcm(OH_AudioNode *node, void *user, void *out, int32_t bytes, bool *finished)
{
    (void)node;
    ohos_audio_effects *s = user;
    *finished = false;
    if (bytes <= 0)
        return 0;
    size_t n = (size_t)bytes < s->input_left ? (size_t)bytes : s->input_left;
    n -= n % s->frame_bytes;
    if (n > 0) {
        memcpy(out, s->input_data, n);
        s->input_data += n;
        s->input_left -= n;
    }
    /* Don't block, and don't let a device repeatedly pull an empty input.
     * A render using these synthetic bytes is rejected by the caller. */
    if (n != (size_t)bytes) {
        memset((uint8_t *)out + n, 0, (size_t)bytes - n);
        s->padded = true;
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
    OH_AudioNodeBuilder *builder = NULL;
    s->library = dlopen("libohaudiosuite.so", RTLD_NOW | RTLD_LOCAL);
    if (!s->library) goto error;
#define LOAD_ENGINE(name) \
    s->engine_##name = (__typeof__(s->engine_##name))dlsym(s->library, "OH_AudioSuiteEngine_" #name); \
    if (!s->engine_##name) goto error;
    ENGINE_API(LOAD_ENGINE)
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

const uint8_t *ohos_effects_render(ohos_audio_effects *s, const uint8_t *data, size_t bytes)
{
    if (!s || !data || !bytes || bytes > sizeof(s->scratch) || bytes % s->frame_bytes)
        return NULL;
    s->input_data = data;
    s->input_left = bytes;
    s->padded = false;
    int32_t rendered = 0;
    bool finished = false;
    OH_AudioSuite_Result status = s->engine_RenderFrame(s->pipeline, s->scratch, (int32_t)bytes,
                                                       &rendered, &finished);
    const bool complete = s->input_left == 0;
    s->input_data = NULL;
    s->input_left = 0;
    /* A short frame, read-ahead, or error can leave the effect's internal
     * buffers at a different position. Never enqueue that frame or reuse
     * that graph after failure; the caller keeps the untouched input. */
    return status == AUDIOSUITE_SUCCESS && !finished && !s->padded &&
           complete && rendered == (int32_t)bytes ? s->scratch : NULL;
}
