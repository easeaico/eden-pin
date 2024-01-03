const c = @cImport({
    @cInclude("zmq.h");
    @cInclude("stdio.h");
});
const std = @import("std");
const mpack = @import("mpack.zig");
const asound = @import("asound.zig");
const net = std.net;
const mem = std.mem;
const io = std.io;
const fmt = std.fmt;
const log = std.log;
const http = std.http;
const time = std.time;

pub const ArugulaError = error{
    UnpackError,
    PackError,
    ConnectError,
    SendFrameError,
    RecvFrameError,
};

pub const ChatCommand = struct {
    const Self = @This();

    buf: std.ArrayList(u8),
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, user_id: i64, character_id: i64, audio: []u8) !Self {
        var buf = std.ArrayList(u8).init(allocator);
        var w = mpack.msgPackWriter(buf.writer(), .{});

        try w.beginArray(2);
        try w.writeString("CHAT");
        try w.beginMap(4);
        try w.writeString("user_id");
        try w.writeInt(user_id);
        try w.writeString("character_id");
        try w.writeInt(character_id);
        try w.writeString("timestamp");
        try w.writeTimestamp(time.timestamp(), 0);
        try w.writeString("audio");
        try w.writeBytes(audio);

        return .{
            .buf = buf,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        self.buf.deinit();
    }
};

pub const ChatResponse = struct {
    const Self = @This();

    text: []const u8,
    audio: []const u8,

    allocator: mem.Allocator,
    arena: std.heap.ArenaAllocator,

    pub fn init(a: mem.Allocator, sbuf: []u8) !Self {
        log.info("buf size {d}", .{sbuf.len});

        var arena = std.heap.ArenaAllocator.init(a);
        var allocator = arena.allocator();

        var fbs = io.fixedBufferStream(sbuf);
        var r = mpack.msgPackReader(fbs.reader());
        var v = try r.readValue(allocator);
        var m = v.root.Map;
        var text: mpack.Value = m.get("text") orelse return ArugulaError.UnpackError;
        var audio: mpack.Value = m.get("audio") orelse return ArugulaError.UnpackError;

        return .{
            .text = text.String,
            .audio = audio.Binary,
            .arena = arena,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        self.arena.deinit();
    }
};

pub const Client = struct {
    const Self = @This();

    context: ?*anyopaque,
    requester: ?*anyopaque,

    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator, endpoint: [:0]const u8) !Self {
        const context = c.zmq_ctx_new();
        const requester = c.zmq_socket(context, c.ZMQ_REQ);
        const ret = c.zmq_connect(requester, endpoint.ptr);
        if (ret < 0) {
            log.err("zmq connect error", .{});
        }

        return .{
            .context = context,
            .requester = requester,
            .allocator = allocator,
        };
    }

    pub fn send(self: Self, command: *const ChatCommand) !void {
        var ret = c.zmq_send(self.requester, command.buf.items.ptr, command.buf.items.len, 0);
        if (ret < 0) {
            log.err("frame send error", .{});
            return ArugulaError.SendFrameError;
        }
    }

    pub fn recv(self: Self) !ChatResponse {
        var msg: c.zmq_msg_t = undefined;

        var rc: c_int = c.zmq_msg_init(&msg);
        if (rc != 0) {
            log.err("zmq msg init error", .{});
            return ArugulaError.RecvFrameError;
        }
        defer {
            _ = c.zmq_msg_close(&msg);
        }

        rc = c.zmq_msg_recv(&msg, self.requester, 0);
        if (rc < 0) {
            log.err("zmq msg recv error", .{});
            return ArugulaError.RecvFrameError;
        }
        log.info("data reads {}", .{rc});
        var ptr = c.zmq_msg_data(&msg);
        if (ptr) |p| {
            var data_ptr = @as([*]u8, @ptrCast(p));
            var size = c.zmq_msg_size(&msg);
            return try ChatResponse.init(self.allocator, data_ptr[0..size]);
        }

        return ArugulaError.UnpackError;
    }

    pub fn deinit(self: Self) void {
        var ret = c.zmq_close(self.requester);
        if (ret < 0) {
            log.err("close zmq sock error", .{});
        }

        ret = c.zmq_ctx_destroy(self.context);
        if (ret < 0) {
            log.err("destroy zmq context error", .{});
        }
    }
};

test "basic coverage (exec)" {
    const allocator = std.testing.allocator;

    const client = try Client.init(allocator, "tcp://127.0.0.1:8055");
    defer client.deinit();

    const data = try std.fs.cwd().readFileAlloc(allocator, "out.wav", 1024 * 1024);
    defer allocator.free(data);

    const cmd = try ChatCommand.init(allocator, 1, 1, data);
    defer cmd.deinit();

    try client.send(&cmd);

    var resp = try client.recv();
    defer resp.deinit();

    log.err("resp: {}", .{resp});
    var player: asound.Player = undefined;
    try player.playback(resp.audio);
    try std.testing.expect(resp.text.len > 0);
}
