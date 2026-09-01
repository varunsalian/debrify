// JNI shim for the prebuilt ten-vad library (see ../../../third_party/ten-vad).
// Deliberately minimal: the Kotlin side owns lifetime and threading; every
// call here is a straight pass-through with argument validation.
#include <jni.h>
#include <stdint.h>
#include <string.h>

#include "ten_vad.h"

#define JNI_FN(name) Java_com_debrify_app_util_TenVad_##name

JNIEXPORT jlong JNICALL JNI_FN(nativeCreate)(JNIEnv *env, jclass clazz, jint hop_size, jfloat threshold) {
    (void)env; (void)clazz;
    if (hop_size <= 0) return 0;
    ten_vad_handle_t handle = NULL;
    if (ten_vad_create(&handle, (size_t)hop_size, threshold) != 0 || handle == NULL) return 0;
    return (jlong)(intptr_t)handle;
}

// Returns the voice flag (0/1) on success, -1 on any failure. The probability
// lands in out[0].
JNIEXPORT jint JNICALL JNI_FN(nativeProcess)(JNIEnv *env, jclass clazz, jlong handle,
                                             jshortArray audio, jint length, jfloatArray out) {
    (void)clazz;
    if (handle == 0 || audio == NULL || out == NULL || length <= 0) return -1;
    if ((*env)->GetArrayLength(env, audio) < length || (*env)->GetArrayLength(env, out) < 1) return -1;
    jshort *samples = (*env)->GetPrimitiveArrayCritical(env, audio, NULL);
    if (samples == NULL) return -1;
    float probability = 0.0f;
    int flag = 0;
    int rc = ten_vad_process((ten_vad_handle_t)(intptr_t)handle, (const int16_t *)samples,
                             (size_t)length, &probability, &flag);
    (*env)->ReleasePrimitiveArrayCritical(env, audio, samples, JNI_ABORT);
    if (rc != 0) return -1;
    (*env)->SetFloatArrayRegion(env, out, 0, 1, &probability);
    return flag ? 1 : 0;
}

JNIEXPORT void JNICALL JNI_FN(nativeDestroy)(JNIEnv *env, jclass clazz, jlong handle) {
    (void)env; (void)clazz;
    if (handle == 0) return;
    ten_vad_handle_t h = (ten_vad_handle_t)(intptr_t)handle;
    ten_vad_destroy(&h);
}

JNIEXPORT jstring JNICALL JNI_FN(nativeVersion)(JNIEnv *env, jclass clazz) {
    (void)clazz;
    const char *version = ten_vad_get_version();
    return (*env)->NewStringUTF(env, version ? version : "unknown");
}
