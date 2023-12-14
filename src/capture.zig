const std = @import("std");
const as = @cImport({
    @cInclude("alsa/asoundlib.h");
});
const wav = @import("wav.zig");

var keepRunning = true;

const bufferFrames: as.snd_pcm_uframes_t = 128;

const CaptureError = error{
    PCMOpenFailed,
    HWParamsError,
    PCMPrepareError,
    PCMReadError,
    PCMCloseError,
};

var sampleRate: c_uint = 16000;

pub fn capture() !void {
    var err: c_int = undefined;

    var captureHandle: ?*as.snd_pcm_t = undefined;
    err = as.snd_pcm_open(&captureHandle, "default", as.SND_PCM_STREAM_CAPTURE, 0);
    if (err < 0) {
        std.debug.print("Capture open error: {s}\n", .{as.snd_strerror(err)});
        return CaptureError.PCMOpenFailed;
    }

    var hwParams: ?*as.snd_pcm_hw_params_t = undefined;
    err = as.snd_pcm_hw_params_malloc(&hwParams);
    if (err < 0) {
        std.debug.print("cannot allocate hardware parameter structure ({s})\n", .{as.snd_strerror(err)});
        return CaptureError.HWParamsError;
    }

    err = as.snd_pcm_hw_params_any(captureHandle, hwParams);
    if (err < 0) {
        std.debug.print("cannot init hardware parameter structure ({s})\n", .{as.snd_strerror(err)});
        return CaptureError.HWParamsError;
    }

    err = as.snd_pcm_hw_params_set_access(captureHandle, hwParams, as.SND_PCM_ACCESS_RW_INTERLEAVED);
    if (err < 0) {
        std.debug.print("cannot set access type ({s})\n", .{as.snd_strerror(err)});
        return CaptureError.HWParamsError;
    }

    err = as.snd_pcm_hw_params_set_format(captureHandle, hwParams, as.SND_PCM_FORMAT_S16_LE);
    if (err < 0) {
        std.debug.print("cannot set sample format ({s})\n", .{as.snd_strerror(err)});
        return CaptureError.HWParamsError;
    }

    err = as.snd_pcm_hw_params_set_rate_near(captureHandle, hwParams, &sampleRate, 0);
    if (err < 0) {
        std.debug.print("cannot set sample rate ({s})\n", .{as.snd_strerror(err)});
        return CaptureError.HWParamsError;
    }

    err = as.snd_pcm_hw_params_set_channels(captureHandle, hwParams, 1);
    if (err < 0) {
        std.debug.print("cannot set channel count ({s})\n", .{as.snd_strerror(err)});
        return CaptureError.HWParamsError;
    }

    err = as.snd_pcm_hw_params(captureHandle, hwParams);
    if (err < 0) {
        std.debug.print("cannot set parameters ({s})\n", .{as.snd_strerror(err)});
        return CaptureError.HWParamsError;
    }

    as.snd_pcm_hw_params_free(hwParams);

    err = as.snd_pcm_prepare(captureHandle);
    if (err < 0) {
        std.debug.print("cannot prepare audio interface for use ({s})\n", .{as.snd_strerror(err)});
        return CaptureError.PCMPrepareError;
    }

    const file = try std.fs.cwd().createFile(
        "out.wav",
        .{},
    );
    defer file.close();

    const saver = wav.Saver(@TypeOf(file).Writer);
    const writer = file.writer();
    try saver.writeHeader(writer, .{
        .num_channels = 1,
        .sample_rate = 16000,
        .format = .signed16_lsb,
    });

    const fw = @as(usize, @intCast(as.snd_pcm_format_width(as.SND_PCM_FORMAT_S16_LE)));
    const allocator = std.heap.c_allocator;
    var buffer = try allocator.alloc(u8, 16 * fw);
    defer allocator.free(buffer);

    const bufferPtrOp: ?*anyopaque = @ptrCast(buffer);

    var dataLen: usize = 0;
    var dataWrited: usize = 0;

    while (keepRunning) {
        var frameReads = as.snd_pcm_readi(captureHandle, bufferPtrOp, bufferFrames);
        if (frameReads != bufferFrames) {
            std.debug.print("read from audio interface failed ({s})\n", .{as.snd_strerror(err)});
            return CaptureError.PCMReadError;
        }
        dataWrited = try writer.write(buffer);
        dataLen += dataWrited;
        std.debug.print("frame reads {d}, data reads {d}\n", .{ frameReads, dataWrited });
    }

    err = as.snd_pcm_close(captureHandle);
    if (err < 0) {
        std.debug.print("snd pcm close failed ({s})\n", .{as.snd_strerror(err)});
        return CaptureError.PCMCloseError;
    }

    try saver.patchHeader(writer, file.seekableStream(), dataLen);
}

pub fn signalHandler(_: c_int) align(1) callconv(.C) void {
    keepRunning = false;
}
