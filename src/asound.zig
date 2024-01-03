const std = @import("std");
const c = @cImport({
    @cInclude("alsa/asoundlib.h");
});
const wav = @import("wav.zig");

const log = std.log;
const io = std.io;
const fs = std.fs;
const mem = std.mem;
const atomic = std.atomic;
const Thread = std.Thread;

pub const ASoundError = error{
    PCMOpenFailed,
    PCMHWParamsError,
    PCMPrepareError,
    PCMReadError,
    PCMWriteError,
    PCMCloseError,
};

const DefaultDevice = "default";

var sample_rate: c_uint = 16000;
const frame_pre_read = 128;

pub const Capturer = struct {
    const Self = @This();

    capture_thread: Thread,
    capturing: bool,
    captured: []u8,
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: mem.Allocator) Self {
        const arena = std.heap.ArenaAllocator.init(allocator);
        return .{
            .capture_thread = undefined,
            .capturing = false,
            .captured = undefined,
            .arena = arena,
        };
    }

    pub fn deinit(self: Self) void {
        self.arena.deinit();
    }

    fn setHWPramas(_: Self, handle: ?*c.snd_pcm_t) c_int {
        var hwParams: ?*c.snd_pcm_hw_params_t = undefined;
        var err = c.snd_pcm_hw_params_malloc(&hwParams);
        if (err < 0) {
            return err;
        }

        err = c.snd_pcm_hw_params_any(handle, hwParams);
        if (err < 0) {
            return err;
        }

        err = c.snd_pcm_hw_params_set_access(handle, hwParams, c.SND_PCM_ACCESS_RW_INTERLEAVED);
        if (err < 0) {
            return err;
        }

        err = c.snd_pcm_hw_params_set_format(handle, hwParams, c.SND_PCM_FORMAT_S16_LE);
        if (err < 0) {
            return err;
        }

        err = c.snd_pcm_hw_params_set_rate_near(handle, hwParams, &sample_rate, 0);
        if (err < 0) {
            return err;
        }

        err = c.snd_pcm_hw_params_set_channels(handle, hwParams, 1);
        if (err < 0) {
            return err;
        }

        err = c.snd_pcm_hw_params(handle, hwParams);
        if (err < 0) {
            return err;
        }

        c.snd_pcm_hw_params_free(hwParams);
        return 0;
    }

    fn captureFrames(self: *Self) !std.ArrayList([]u8) {
        @atomicStore(bool, &self.capturing, true, .SeqCst);

        var handle: ?*c.snd_pcm_t = undefined;
        var err = c.snd_pcm_open(&handle, DefaultDevice, c.SND_PCM_STREAM_CAPTURE, 0);
        if (err < 0) {
            log.err("Capture open error: {s}\n", .{c.snd_strerror(err)});
            return ASoundError.PCMOpenFailed;
        }

        err = self.setHWPramas(handle);
        if (err < 0) {
            log.err("cannot set parameters ({s})\n", .{c.snd_strerror(err)});
            return ASoundError.PCMHWParamsError;
        }

        err = c.snd_pcm_prepare(handle);
        if (err < 0) {
            log.err("cannot prepare audio interface for use ({s})\n", .{c.snd_strerror(err)});
            return ASoundError.PCMPrepareError;
        }

        const frame_width = @as(usize, @intCast(c.snd_pcm_format_width(c.SND_PCM_FORMAT_S16_LE)));
        var frame_size = frame_pre_read * frame_width / 8;

        var frame_buffers = std.ArrayList([]u8).init(self.arena.allocator());
        while (@atomicLoad(bool, &self.capturing, .SeqCst)) {
            var frame_buffer = try self.arena.allocator().alloc(u8, frame_size);

            var buffer_frames: c.snd_pcm_uframes_t = frame_pre_read;
            var frame_reads = c.snd_pcm_readi(handle, frame_buffer.ptr, buffer_frames);
            if (frame_reads < 0) {
                log.err("read from audio interface failed ({s})\n", .{c.snd_strerror(@as(c_int, @intCast(frame_reads)))});
                return ASoundError.PCMReadError;
            }

            if (frame_reads != frame_pre_read) {
                log.err("read from audio interface failed (reads error)\n", .{});
                return ASoundError.PCMReadError;
            }

            try frame_buffers.append(frame_buffer);
            //log.err("data reads {d}\n", .{frame_buffer.len});
        }

        err = c.snd_pcm_close(handle);
        if (err < 0) {
            log.err("snd pcm close failed ({s})\n", .{c.snd_strerror(err)});
            return ASoundError.PCMCloseError;
        }

        return frame_buffers;
    }

    pub fn captureWave(self: *Self) !void {
        var frame_buffers = try self.captureFrames();

        var data = std.ArrayList(u8).init(self.arena.allocator());
        for (frame_buffers.items) |b| {
            try data.appendSlice(b);
        }

        var wave = std.ArrayList(u8).init(self.arena.allocator());
        const saver = wav.Saver(@TypeOf(wave).Writer);
        try saver.save(wave.writer(), data.items, .{
            .num_channels = 1,
            .sample_rate = 16000,
            .format = .signed16_lsb,
        });

        self.captured = wave.items;
    }

    pub fn spwanCapture(self: *Self) !void {
        self.capture_thread = try Thread.spawn(.{}, Capturer.captureWave, .{self});
    }

    pub fn stopCapture(self: *Self) []u8 {
        @atomicStore(bool, &self.capturing, false, .SeqCst);
        self.capture_thread.join();
        return self.captured;
    }
};

pub fn play(data: []const u8) !void {
    var handle: ?*c.snd_pcm_t = undefined;
    var err = c.snd_pcm_open(&handle, DefaultDevice, c.SND_PCM_STREAM_PLAYBACK, 0);
    if (err < 0) {
        log.err("Playback open error: {s}\n", .{c.snd_strerror(err)});
        return ASoundError.PCMOpenFailed;
    }
    err = c.snd_pcm_set_params(handle, c.SND_PCM_FORMAT_S16_LE, c.SND_PCM_ACCESS_RW_INTERLEAVED, 1, 44100, 1, 500000);
    if (err < 0) {
        log.err("Playback set params error: {s}\n", .{c.snd_strerror(err)});
        return ASoundError.PCMHWParamsError;
    }

    var frames = c.snd_pcm_writei(handle, data.ptr, data.len);
    if (frames < 0) {
        err = @as(c_int, @intCast(frames));
        err = c.snd_pcm_recover(handle, err, 0);
        if (err < 0) {
            log.err("snd_pcm_writei failed: {s}\n", .{c.snd_strerror(err)});
            return ASoundError.PCMPrepareError;
        }
    }

    if ((frames > 0) and (frames < data.len)) {
        log.err("Short write (expected {d}, wrote {d})\n", .{ data.len, frames });
        return ASoundError.PCMWriteError;
    }

    var ret = c.snd_pcm_drain(handle);
    if (ret < 0) {
        log.err("snd_pcm_drain failed: {s}\n", .{c.snd_strerror(ret)});
        return ASoundError.PCMCloseError;
    }

    ret = c.snd_pcm_close(handle);
    if (ret < 0) {
        log.err("snd_pcm_close failed: {s}\n", .{c.snd_strerror(ret)});
        return ASoundError.PCMCloseError;
    }
}

test "sound capture" {
    const allocator = std.testing.allocator;

    var capturer = try Capturer.init(allocator);
    defer capturer.deinit();

    var data = try capturer.captureWave();
    try std.testing.expect(data.len > 0);

    const file = try std.fs.cwd().createFile("out.wav", .{});
    defer file.close();

    try file.writeAll(data);
}

test "sound play" {
    const file = try std.fs.cwd().openFile("out.wav", .{});
    var data: []u8 = undefined;
    _ = try file.readAll(data);
    try play(data);
}
