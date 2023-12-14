const std = @import("std");
const as = @cImport({
    @cInclude("alsa/asoundlib.h");
});

const deviceName = "default";
var buffer: [16 * 1024]u8 = undefined;

pub fn playback() void {
    var err: c_int = undefined;
    var rnd = std.rand.DefaultPrng.init(0);

    for (&buffer) |*item| {
        item.* = rnd.random().int(u8) & 0xff;
    }

    var playbackHandle: ?*as.snd_pcm_t = undefined;
    err = as.snd_pcm_open(&playbackHandle, deviceName, as.SND_PCM_STREAM_PLAYBACK, 0);
    if (err < 0) {
        std.debug.print("Playback open error: {s}\n", .{as.snd_strerror(err)});
        std.os.exit(as.EXIT_FAILURE);
    }
    std.debug.print("Playback open success\n", .{});

    err = as.snd_pcm_set_params(playbackHandle, as.SND_PCM_FORMAT_U8, as.SND_PCM_ACCESS_RW_INTERLEAVED, 1, 48000, 1, 500000);
    if (err < 0) {
        std.debug.print("Playback set params error: {s}\n", .{as.snd_strerror(err)});
        std.os.exit(as.EXIT_FAILURE);
    }

    var frames: as.snd_pcm_sframes_t = undefined;
    for (0..16) |_| {
        frames = as.snd_pcm_writei(playbackHandle, &buffer, buffer.len);
        if (frames < 0) {
            err = @intCast(frames);
            err = as.snd_pcm_recover(playbackHandle, err, 0);
            if (err < 0) {
                std.debug.print("snd_pcm_writei failed: {s}\n", .{as.snd_strerror(err)});
                break;
            }
        }

        if ((frames > 0) and (frames < buffer.len)) {
            std.debug.print("Short write (expected {}, wrote {})\n", .{ buffer.len, frames });
        }
    }

    err = as.snd_pcm_drain(playbackHandle);
    if (err < 0) {
        std.debug.print("snd_pcm_drain failed: {s}\n", .{as.snd_strerror(err)});
    }

    err = as.snd_pcm_close(playbackHandle);
    if (err < 0) {
        std.debug.print("snd_pcm_close failed: {s}\n", .{as.snd_strerror(err)});
    }
}
