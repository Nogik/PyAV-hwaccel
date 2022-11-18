from libc.stdint cimport int64_t
cimport libav as lib

from av.codec.context cimport CodecContext
from av.codec.hwaccel cimport HWAccel, HWConfig
from av.error cimport err_check
from av.frame cimport Frame
from av.packet cimport Packet
from av.utils cimport avrational_to_fraction, to_avrational
from av.video.format cimport VideoFormat, get_pix_fmt, get_video_format
from av.video.frame cimport VideoFrame, alloc_video_frame
from av.video.reformatter cimport VideoReformatter


cdef lib.AVPixelFormat _get_hw_format(lib.AVCodecContext *ctx, lib.AVPixelFormat *pix_fmts):
    i = 0
    while pix_fmts[i] != -1:
        if pix_fmts[i] == ctx.pix_fmt:
            return pix_fmts[i]
        i += 1
    
    return lib.AV_PIX_FMT_NONE

cdef class VideoCodecContext(CodecContext):

    def __cinit__(self, *args, **kwargs):
        self.last_w = 0
        self.last_h = 0


    cdef _init(self, lib.AVCodecContext *ptr, const lib.AVCodec *codec, HWAccel hwaccel):
        CodecContext._init(self, ptr, codec,hwaccel)  # TODO: Can this be `super`?
        if hwaccel is not None:
            self.hwaccel = hwaccel.create(self.codec)

        self._build_format()
        self.encoded_frame_count = 0

    cdef set_hw(self):
        if self.hwaccel is not None:
            if self.hwaccel.config.methods == lib.AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX:
                self.ptr.hw_device_ctx = lib.av_buffer_ref(self.hwaccel.ptr)
                self.ptr.pix_fmt = self.hwaccel.config.ptr.pix_fmt
            if self.hwaccel.config.methods == lib.AV_CODEC_HW_CONFIG_METHOD_HW_FRAMES_CTX:
                self.hw_frames_ref = lib.av_hwframe_ctx_alloc(self.hwaccel.ptr)
                self.frames_ctx_ptr = <lib.AVHWFramesContext *> self.hw_frames_ref.data
                self.frames_ctx_ptr.format = lib.AVPixelFormat.AV_PIX_FMT_VAAPI
                self.frames_ctx_ptr.sw_format = lib.AVPixelFormat.AV_PIX_FMT_NV12
                self.frames_ctx_ptr.width = self.ptr.width
                self.frames_ctx_ptr.height = self.ptr.height
                self.frames_ctx_ptr.initial_pool_size  = 20
                err_check(lib.av_hwframe_ctx_init(self.hw_frames_ref))
                self.ptr.hw_frames_ctx = lib.av_buffer_ref(self.hw_frames_ref)
                lib.av_buffer_unref(&self.hw_frames_ref)

                self.ptr.pix_fmt = lib.av_get_pix_fmt(self.hwaccel.codec_pix_fmt)
                self.hw_frame = lib.av_frame_alloc() #moved to HW init
                err_check(lib.av_hwframe_get_buffer(self.ptr.hw_frames_ctx,self.hw_frame,0))
            self.ptr.get_format = _get_hw_format





    cdef _set_default_time_base(self):
        self.ptr.time_base.num = self.ptr.framerate.den or 1
        self.ptr.time_base.den = self.ptr.framerate.num or lib.AV_TIME_BASE

    cdef _prepare_frames_for_encode(self, Frame input):

        if not input:
            return [None]

        cdef VideoFrame vframe = input
        # Reformat if it doesn't match.
        if (
            vframe.format.pix_fmt != self._format.pix_fmt or
            vframe.width != self.ptr.width or
            vframe.height != self.ptr.height
        ):
            if not self.reformatter:
                self.reformatter = VideoReformatter()
            vframe = self.reformatter.reformat(
                vframe,
                self.ptr.width,
                self.ptr.height,
                self._format,
            )

        # There is no pts, so create one.
        if vframe.ptr.pts == lib.AV_NOPTS_VALUE:
            vframe.ptr.pts = <int64_t>self.encoded_frame_count

        self.encoded_frame_count += 1
        return [vframe]

    cdef Frame _alloc_next_frame(self):
        return alloc_video_frame()

    cdef _setup_decoded_frame(self, Frame frame, Packet packet):
        CodecContext._setup_decoded_frame(self, frame, packet)
        cdef VideoFrame vframe = frame
        vframe._init_user_attributes()

    cdef _transfer_hwframe(self, Frame frame):
        cdef Frame frame_sw

        #print("Format", frame.ptr.format)

        if self.hwaccel is not None and frame.ptr.format == self.hwaccel.config.ptr.pix_fmt:
            # retrieve data from GPU to CPU
            frame_sw = self._alloc_next_frame()

            ret = lib.av_hwframe_transfer_data(frame_sw.ptr, frame.ptr, 0)
            if (ret < 0):
                raise RuntimeError("Error transferring the data to system memory")

            frame_sw.pts = frame.pts
            return frame_sw

        else:
            return frame

    cdef _send_frame_and_recv(self, Frame frame):

        cdef Packet packet
        cdef int res

        if self.hwaccel is not None:
            #hw_frame = lib.av_frame_alloc() #moved to HW init
            #err_check(lib.av_hwframe_get_buffer(self.ptr.hw_frames_ctx,self.hw_frame,0))
            err_check(lib.av_hwframe_transfer_data(self.hw_frame, frame.ptr,0))
            self.hw_frame.pts = frame.ptr.pts

            with nogil:
                res = lib.avcodec_send_frame(self.ptr, self.hw_frame)
        else:
            with nogil:
                res = lib.avcodec_send_frame(self.ptr, frame.ptr if frame is not None else NULL)

        err_check(res)

        out = []
        while True:
            packet = self._recv_packet(frame.ptr.pts)
            if packet:
                out.append(packet)
            else:
                break
        #if self.hwaccel is not None:
        #    lib.av_frame_free(&hw_frame)
        return out

    cdef _build_format(self):
        self._format = get_video_format(<lib.AVPixelFormat>self.ptr.pix_fmt, self.ptr.width, self.ptr.height)

    property format:
        def __get__(self):
            return self._format

        def __set__(self, VideoFormat format):
            self.ptr.pix_fmt = format.pix_fmt
            self.ptr.width = format.width
            self.ptr.height = format.height
            self._build_format()  # Kinda wasteful.

    property width:
        def __get__(self):
            return self.ptr.width

        def __set__(self, unsigned int value):
            self.ptr.width = value
            self._build_format()

    property height:
        def __get__(self):
            return self.ptr.height

        def __set__(self, unsigned int value):
            self.ptr.height = value
            self._build_format()

    property pix_fmt:
        """
        The pixel format's name.

        :type: str
        """
        def __get__(self):
            return self._format.name

        def __set__(self, value):
            self.ptr.pix_fmt = get_pix_fmt(value)
            self._build_format()

    property framerate:
        """
        The frame rate, in frames per second.

        :type: fractions.Fraction
        """
        def __get__(self):
            return avrational_to_fraction(&self.ptr.framerate)

        def __set__(self, value):
            to_avrational(value, &self.ptr.framerate)

    property rate:
        """Another name for :attr:`framerate`."""
        def __get__(self):
            return self.framerate

        def __set__(self, value):
            self.framerate = value

    property gop_size:
        def __get__(self):
            return self.ptr.gop_size

        def __set__(self, int value):
            self.ptr.gop_size = value

    property sample_aspect_ratio:
        def __get__(self):
            return avrational_to_fraction(&self.ptr.sample_aspect_ratio)

        def __set__(self, value):
            to_avrational(value, &self.ptr.sample_aspect_ratio)

    property display_aspect_ratio:
        def __get__(self):
            cdef lib.AVRational dar

            lib.av_reduce(
                &dar.num, &dar.den,
                self.ptr.width * self.ptr.sample_aspect_ratio.num,
                self.ptr.height * self.ptr.sample_aspect_ratio.den, 1024*1024)

            return avrational_to_fraction(&dar)

    property has_b_frames:
        def __get__(self):
            return bool(self.ptr.has_b_frames)

    property coded_width:
        def __get__(self):
            return self.ptr.coded_width

    property coded_height:
        def __get__(self):
            return self.ptr.coded_height

    property using_hwaccel:
        def __get__(self):
            return self.ptr.hw_device_ctx != NULL
