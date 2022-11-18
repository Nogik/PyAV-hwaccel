cdef extern from "libavcodec/avcodec.h" nogil:

    cdef struct AVCodecHWConfig:
        AVPixelFormat pix_fmt
        int methods
        AVHWDeviceType device_type

    cdef const AVCodecHWConfig* avcodec_get_hw_config(const AVCodec *codec, int index)

    cdef enum:
        AV_HWACCEL_CODEC_CAP_EXPERIMENTAL

    cdef struct AVHWAccel:
        char *name
        AVMediaType type
        AVCodecID id
        AVPixelFormat pix_fmt
        int capabilities