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

const send_timeout: c_int = 10 * 1000; // 10秒
const recv_timeout: c_int = 60 * 1000; // 一分钟

pub const ArugulaError = error{
    UnpackError,
    PackError,
    ConnectError,
    SendFrameError,
    RecvFrameError,
    ResponseError,
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

    pub const InterResp = struct {
        text: []const u8,
        audio: []const u8,
    };

    data: std.ArrayList(InterResp),
    arena: std.heap.ArenaAllocator,

    pub fn init(alloc: mem.Allocator, sbuf: []u8) !Self {
        log.info("buf size {d}", .{sbuf.len});

        var arena = std.heap.ArenaAllocator.init(alloc);
        const allocator = arena.allocator();

        var fbs = io.fixedBufferStream(sbuf);
        var r = mpack.msgPackReader(fbs.reader());
        const v = try r.readValue(allocator);
        const a = v.root.Array;
        const t = a.items[0].String;
        if (mem.eql(u8, t, "ERR")) {
            log.err("response error: {s}", .{a.items[1].String});
            return ArugulaError.ResponseError;
        }

        var data = std.ArrayList(InterResp).init(allocator);
        if (a.items.len < 1) {
            log.err("response data is empty", .{});
            return ArugulaError.ResponseError;
        }

        for (a.items[1].Array.items) |i| {
            var m = i.Map;
            const text: mpack.Value = m.get("text") orelse return ArugulaError.UnpackError;
            const audio: mpack.Value = m.get("audio") orelse return ArugulaError.UnpackError;

            try data.append(.{
                .text = text.String,
                .audio = audio.Binary,
            });
        }

        return .{
            .arena = arena,
            .data = data,
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

    pub fn init(allocator: mem.Allocator) Self {
        const context = c.zmq_ctx_new();
        const requester = c.zmq_socket(context, c.ZMQ_REQ);
        return .{
            .context = context,
            .requester = requester,
            .allocator = allocator,
        };
    }

    pub fn connect(self: Self, endpoint: [:0]const u8) !void {
        var ret = c.zmq_connect(self.requester, endpoint.ptr);
        if (ret < 0) {
            log.err("zmq connect error: {s}", .{c.zmq_strerror(c.zmq_errno())});
        }

        ret = c.zmq_setsockopt(self.requester, c.ZMQ_SNDTIMEO, &send_timeout, @sizeOf(c_int));
        if (ret < 0) {
            log.err("set send time out error: {s}", .{c.zmq_strerror(c.zmq_errno())});
            return ArugulaError.ConnectError;
        }

        ret = c.zmq_setsockopt(self.requester, c.ZMQ_RCVTIMEO, &recv_timeout, @sizeOf(c_int));
        if (ret < 0) {
            log.err("set rev time out error: {s}", .{c.zmq_strerror(c.zmq_errno())});
            return ArugulaError.ConnectError;
        }
    }

    pub fn send(self: Self, command: *const ChatCommand) !void {
        const ret = c.zmq_send(self.requester, command.buf.items.ptr, command.buf.items.len, 0);
        if (ret < 0) {
            log.err("frame send error: {s}", .{c.zmq_strerror(c.zmq_errno())});
            return ArugulaError.SendFrameError;
        }
    }

    pub fn recv(self: Self) !ChatResponse {
        var msg: c.zmq_msg_t = undefined;

        var ret = c.zmq_msg_init(&msg);
        if (ret != 0) {
            log.err("zmq msg init error: {s}", .{c.zmq_strerror(c.zmq_errno())});
            return ArugulaError.RecvFrameError;
        }
        defer {
            _ = c.zmq_msg_close(&msg);
        }

        ret = c.zmq_msg_recv(&msg, self.requester, 0);
        if (ret < 0) {
            log.err("zmq msg recv error: {s}", .{c.zmq_strerror(c.zmq_errno())});
            return ArugulaError.RecvFrameError;
        }

        const ptr = c.zmq_msg_data(&msg);
        if (ptr) |p| {
            var data_ptr = @as([*]u8, @ptrCast(p));
            const size = c.zmq_msg_size(&msg);
            return try ChatResponse.init(self.allocator, data_ptr[0..size]);
        }

        return ArugulaError.UnpackError;
    }

    pub fn deinit(self: Self) void {
        var ret = c.zmq_close(self.requester);
        if (ret < 0) {
            log.err("close zmq sock error: {s}", .{c.zmq_strerror(c.zmq_errno())});
        }

        ret = c.zmq_ctx_destroy(self.context);
        if (ret < 0) {
            log.err("destroy zmq context error: {s}", .{c.zmq_strerror(c.zmq_errno())});
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
    for (resp.data.items) |i| {
        try asound.play(i.audio);
    }
    try std.testing.expect(resp.text.len > 0);
}
