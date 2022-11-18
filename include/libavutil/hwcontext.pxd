
cdef extern from "libavutil/hwcontext.h" nogil:

    cdef enum AVHWDeviceType:
        AV_HWDEVICE_TYPE_NONE
        AV_HWDEVICE_TYPE_VDPAU
        AV_HWDEVICE_TYPE_CUDA
        AV_HWDEVICE_TYPE_VAAPI
        AV_HWDEVICE_TYPE_DXVA2
        AV_HWDEVICE_TYPE_QSV
        AV_HWDEVICE_TYPE_VIDEOTOOLBOX
        AV_HWDEVICE_TYPE_D3D11VA
        AV_HWDEVICE_TYPE_DRM
        AV_HWDEVICE_TYPE_OPENCL
        AV_HWDEVICE_TYPE_MEDIACODEC

    cdef struct AVHWDeviceContext:
        AVClass * av_class
        AVHWDeviceType type

    cdef struct AVHWFramesContext:
        AVClass * av_class

        AVBufferRef * 	device_ref
        AVHWDeviceContext * device_ctx
        int initial_pool_size
        AVPixelFormat 	format
        AVPixelFormat 	sw_format
        int width
        int height

    cdef AVHWDeviceType av_hwdevice_iterate_types(AVHWDeviceType prev)

    cdef int av_hwdevice_ctx_create(AVBufferRef **device_ctx, AVHWDeviceType type, const char *device, AVDictionary *opts, int flags)

    cdef AVHWDeviceType av_hwdevice_find_type_by_name(const char *name)
    cdef const char *av_hwdevice_get_type_name(AVHWDeviceType type)

    cdef int av_hwframe_transfer_data(AVFrame *dst, const AVFrame *src, int flags)
    cdef AVBufferRef * 	av_hwframe_ctx_alloc (AVBufferRef *device_ref_in)
    int av_hwframe_ctx_init	(AVBufferRef * 	ref	)
    int av_hwframe_get_buffer (AVBufferRef *hwframe_ref, AVFrame *frame, int flags)

