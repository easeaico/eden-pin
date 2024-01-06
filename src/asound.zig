const std = @import("std");
const c = @cImport({
    @cInclude("alsa/asoundlib.h");
});
const wav = @import("wav.zig");

const log = std.log;
const io = std.io;
const mem = std.mem;
const atomic = std.atomic;
const Thread = std.Thread;

pub const ASoundError = error{
    PCMOpenFailed,
    PCMHWParamsError,
    PCMPrepareError,
    PCMRecoverError,
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
    handle: ?*c.snd_pcm_t,

    pub fn init(allocator: mem.Allocator) Self {
        const arena = std.heap.ArenaAllocator.init(allocator);
        return .{
            .capture_thread = undefined,
            .capturing = false,
            .captured = undefined,
            .arena = arena,
            .handle = undefined,
        };
    }

    pub fn deinit(self: Self) void {
        self.arena.deinit();
    }

    pub fn open(self: *Self) !void {
        var err = c.snd_pcm_open(&self.handle, DefaultDevice, c.SND_PCM_STREAM_CAPTURE, 0);
        if (err < 0) {
            log.err("Capture open error: {s}\n", .{c.snd_strerror(err)});
            return ASoundError.PCMOpenFailed;
        }

        err = self.setHWPramas(self.handle);
        if (err < 0) {
            log.err("cannot set parameters ({s})\n", .{c.snd_strerror(err)});
            return ASoundError.PCMHWParamsError;
        }
    }

    pub fn close(self: *Self) void {
        var err = c.snd_pcm_close(self.handle);
        if (err < 0) {
            log.err("snd pcm close failed ({s})\n", .{c.snd_strerror(err)});
        }
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

        var err = c.snd_pcm_prepare(self.handle);
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
            var frame_reads = c.snd_pcm_readi(self.handle, frame_buffer.ptr, buffer_frames);
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

    pub fn spawnCapture(self: *Self) !void {
        self.capture_thread = try Thread.spawn(.{}, Capturer.captureWave, .{self});
    }

    pub fn stopCapture(self: *Self) []u8 {
        @atomicStore(bool, &self.capturing, false, .SeqCst);
        self.capture_thread.join();
        return self.captured;
    }
};

pub const Player = struct {
    const Self = @This();

    handle: ?*c.snd_pcm_t,
    play_thread: Thread,

    pub fn init() Self {
        return .{
            .handle = undefined,
            .play_thread = undefined,
        };
    }

    pub fn deinit(_: Self) void {}

    pub fn open(self: *Self) !void {
        var err = c.snd_pcm_open(&self.handle, DefaultDevice, c.SND_PCM_STREAM_PLAYBACK, 0);
        if (err < 0) {
            log.err("Playback open error: {s}\n", .{c.snd_strerror(err)});
            return ASoundError.PCMOpenFailed;
        }
        err = c.snd_pcm_set_params(self.handle, c.SND_PCM_FORMAT_S16_LE, c.SND_PCM_ACCESS_RW_INTERLEAVED, 1, 44100, 1, 500000);
        if (err < 0) {
            log.err("Playback set params error: {s}\n", .{c.snd_strerror(err)});
            return ASoundError.PCMHWParamsError;
        }
    }

    pub fn spawnPlay(self: *Self, data: [][]const u8) !void {
        self.play_thread = try Thread.spawn(.{}, Player.playWave, .{ self, data });
    }

    pub fn playWave(self: *Self, data: [][]const u8) !void {
        try self.open();
        defer self.close();

        for (data) |d| {
            var fbs = io.fixedBufferStream(d);
            _ = try wav.Loader(@TypeOf(fbs).Reader, true).preload(fbs.reader());

            var fs: c.snd_pcm_uframes_t = (d.len - fbs.pos) / 2;
            var frames = c.snd_pcm_writei(self.handle, d.ptr + fbs.pos, fs);
            if (frames < 0) {
                var err = @as(c_int, @intCast(frames));
                err = c.snd_pcm_recover(self.handle, err, 0);
                if (err < 0) {
                    log.err("snd_pcm_writei failed: {s}\n", .{c.snd_strerror(err)});
                    return ASoundError.PCMRecoverError;
                }
            }

            if ((frames > 0) and (frames < fs)) {
                log.err("Short write (expected {d}, wrote {d})\n", .{ fs, frames });
                return ASoundError.PCMWriteError;
            }

            var ret = c.snd_pcm_drain(self.handle);
            if (ret < 0) {
                log.err("snd_pcm_drain failed: {s}\n", .{c.snd_strerror(ret)});
                return ASoundError.PCMCloseError;
            }
        }
    }

    pub fn join(self: Self) void {
        return self.play_thread.join();
    }

    pub fn close(self: Self) void {
        var ret = c.snd_pcm_close(self.handle);
        if (ret < 0) {
            log.err("snd_pcm_close failed: {s}\n", .{c.snd_strerror(ret)});
        }
    }
};

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

    var player = Player.init();

    try player.open();
    defer player.close();

    try player.play(data);
}
