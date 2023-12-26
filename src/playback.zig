const std = @import("std");
const as = @import("asound.zig");
const asc = @cImport({
    @cInclude("alsa/asoundlib.h");
});
const print = std.debug.print;

pub fn playback(data: []const u8) !void {
    var playbackHandle: ?*asc.snd_pcm_t = undefined;
    var err = asc.snd_pcm_open(&playbackHandle, as.DefaultDevice, asc.SND_PCM_STREAM_PLAYBACK, 0);
    if (err < 0) {
        print("Playback open error: {s}\n", .{asc.snd_strerror(err)});
        return as.ASoundError.PCMOpenFailed;
    }

    err = asc.snd_pcm_set_params(playbackHandle, asc.SND_PCM_FORMAT_U8, asc.SND_PCM_ACCESS_RW_INTERLEAVED, 1, 48000, 1, 500000);
    if (err < 0) {
        print("Playback set params error: {s}\n", .{asc.snd_strerror(err)});
        return as.ASoundError.PCMHWParamsError;
    }

    var frames: asc.snd_pcm_sframes_t = undefined;
    frames = asc.snd_pcm_writei(playbackHandle, @ptrCast(&data), data.len);
    if (frames < 0) {
        err = @intCast(frames);
        err = asc.snd_pcm_recover(playbackHandle, err, 0);
        if (err < 0) {
            print("snd_pcm_writei failed: {s}\n", .{asc.snd_strerror(err)});
            return as.ASoundError.PCMPrepareError;
        }
    }

    if ((frames > 0) and (frames < data.len)) {
        print("Short write (expected {}, wrote {})\n", .{ data.len, frames });
        return as.ASoundError.PCMWriteError;
    }

    err = asc.snd_pcm_drain(playbackHandle);
    if (err < 0) {
        print("snd_pcm_drain failed: {s}\n", .{asc.snd_strerror(err)});
        return as.ASoundError.PCMCloseError;
    }

    err = asc.snd_pcm_close(playbackHandle);
    if (err < 0) {
        print("snd_pcm_close failed: {s}\n", .{asc.snd_strerror(err)});
        return as.ASoundError.PCMCloseError;
    }
}
