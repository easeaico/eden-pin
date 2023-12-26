const std = @import("std");
const wav = @import("wav.zig");
const as = @import("asound.zig");
const asc = @cImport({
    @cInclude("alsa/asoundlib.h");
});
const log = std.log;
const io = std.io;

var keepRunning = true;

const bufferFrames: asc.snd_pcm_uframes_t = 128;

var sampleRate: c_uint = 16000;

pub fn capture(buf: []u8) !usize {
    var fbs = io.fixedBufferStream(buf);
    var err: c_int = undefined;

    var captureHandle: ?*asc.snd_pcm_t = undefined;
    err = asc.snd_pcm_open(&captureHandle, as.DefaultDevice, asc.SND_PCM_STREAM_CAPTURE, 0);
    if (err < 0) {
        log.err("Capture open error: {s}\n", .{asc.snd_strerror(err)});
        return as.ASoundError.PCMOpenFailed;
    }

    var hwParams: ?*asc.snd_pcm_hw_params_t = undefined;
    err = asc.snd_pcm_hw_params_malloc(&hwParams);
    if (err < 0) {
        log.err("cannot allocate hardware parameter structure ({s})\n", .{asc.snd_strerror(err)});
        return as.ASoundError.HWParamsError;
    }

    err = asc.snd_pcm_hw_params_any(captureHandle, hwParams);
    if (err < 0) {
        log.err("cannot init hardware parameter structure ({s})\n", .{asc.snd_strerror(err)});
        return as.ASoundError.HWParamsError;
    }

    err = asc.snd_pcm_hw_params_set_access(captureHandle, hwParams, asc.SND_PCM_ACCESS_RW_INTERLEAVED);
    if (err < 0) {
        log.err("cannot set access type ({s})\n", .{asc.snd_strerror(err)});
        return as.ASoundError.HWParamsError;
    }

    err = asc.snd_pcm_hw_params_set_format(captureHandle, hwParams, asc.SND_PCM_FORMAT_S16_LE);
    if (err < 0) {
        log.err("cannot set sample format ({s})\n", .{asc.snd_strerror(err)});
        return as.ASoundError.HWParamsError;
    }

    err = asc.snd_pcm_hw_params_set_rate_near(captureHandle, hwParams, &sampleRate, 0);
    if (err < 0) {
        log.err("cannot set sample rate ({s})\n", .{asc.snd_strerror(err)});
        return as.ASoundError.HWParamsError;
    }

    err = asc.snd_pcm_hw_params_set_channels(captureHandle, hwParams, 1);
    if (err < 0) {
        log.err("cannot set channel count ({s})\n", .{asc.snd_strerror(err)});
        return as.ASoundError.HWParamsError;
    }

    err = asc.snd_pcm_hw_params(captureHandle, hwParams);
    if (err < 0) {
        log.err("cannot set parameters ({s})\n", .{asc.snd_strerror(err)});
        return as.ASoundError.HWParamsError;
    }

    asc.snd_pcm_hw_params_free(hwParams);

    err = asc.snd_pcm_prepare(captureHandle);
    if (err < 0) {
        log.err("cannot prepare audio interface for use ({s})\n", .{asc.snd_strerror(err)});
        return as.ASoundError.PCMPrepareError;
    }

    const saver = wav.Saver(@TypeOf(fbs.writer()).Writer);
    try saver.writeHeader(fbs.writer(), .{
        .num_channels = 1,
        .sample_rate = 16000,
        .format = .signed16_lsb,
    });

    const fw = @as(usize, @intCast(asc.snd_pcm_format_width(asc.SND_PCM_FORMAT_S16_LE)));
    const allocator = std.heap.c_allocator;
    var buffer = try allocator.alloc(u8, 16 * fw);
    defer allocator.free(buffer);

    const bufferPtrOp: ?*anyopaque = @ptrCast(buffer);

    var dataLen: usize = 0;
    var dataWrited: usize = 0;

    while (keepRunning) {
        var frameReads = asc.snd_pcm_readi(captureHandle, bufferPtrOp, bufferFrames);
        if (frameReads != bufferFrames) {
            log.err("read from audio interface failed ({s})\n", .{asc.snd_strerror(err)});
            return as.ASoundError.PCMReadError;
        }
        dataWrited = try fbs.writer().write(buffer);
        dataLen += dataWrited;
        log.err("frame reads {d}, data reads {d}\n", .{ frameReads, dataWrited });
    }

    err = asc.snd_pcm_close(captureHandle);
    if (err < 0) {
        log.err("snd pcm close failed ({s})\n", .{asc.snd_strerror(err)});
        return as.ASoundError.PCMCloseError;
    }

    try saver.patchHeader(fbs.writer(), fbs.seekableStream(), dataLen);
    return fbs.getEndPos();
}

pub fn signalHandler(_: c_int) align(1) callconv(.C) void {
    keepRunning = false;
}
