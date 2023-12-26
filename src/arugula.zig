const c = @cImport({
    @cInclude("czmq.h");
    @cInclude("msgpack.h");
});
const std = @import("std");
const net = std.net;
const mem = std.mem;
const io = std.io;
const fmt = std.fmt;
const log = std.log;
const http = std.http;

pub const ArugulaError = error{
    UnpackError,
    SendFrameError,
};

pub const ChatCommand = struct {
    const Self = @This();

    sbuf: c.msgpack_sbuffer,

    pub fn init(user_id: i64, character_id: i64, ts: i64, audio: []const u8) !Self {
        var self = Self{};
        c.msgpack_sbuffer_init(&self.sbuf);

        var pk: c.msgpack_packer = undefined;
        c.msgpack_packer_init(&pk, &self.sbuf, c.msgpack_sbuffer_write);
        c.msgpack_pack_int64(&pk, user_id);
        c.msgpack_pack_int64(&pk, character_id);
        c.msgpack_pack_int64(&pk, ts);
        c.msgpack_pack_bin_with_body(&pk, audio, audio.len);

        return self;
    }

    pub fn deinit(self: Self) void {
        c.msgpack_sbuffer_destroy(&self.sbuf);
    }
};

pub const ChatResponse = struct {
    const Self = @This();

    result: c.msgpack_unpacked,
    text: []const u8,
    audio: []const u8,

    pub fn init(sbuf: []const u8) !Self {
        var self = Self{};
        var off: usize = 0;

        c.msgpack_unpacked_init(&self.result);

        var ret = c.msgpack_unpack_next(&self.result, sbuf, sbuf.len, &off);
        if (ret != c.MSGPACK_UNPACK_SUCCESS) {
            log.err("unpack error {}", .{ret});
            return ArugulaError.UnpackError;
        }
        self.text = self.result.data.via.str;

        ret = c.msgpack_unpack_next(&self.result, sbuf, sbuf.len, &off);
        if (ret != c.MSGPACK_UNPACK_SUCCESS) {
            log.err("unpack error {}", .{ret});
            return ArugulaError.UnpackError;
        }
        self.audio = self.result.data.via.bin;
    }

    fn deinit(self: Self) void {
        c.msgpack_unpacked_destroy(&self.result);
    }
};

pub const Client = struct {
    const Self = @This();

    var zsock: c.zsock_t = undefined;

    var stream: net.Stream = undefined;

    pub fn init(endpoint: []const u8) Self {
        zsock = try c.zsock_new_dealer(endpoint);
        return .{};
    }

    pub fn send(_: Self, command: ChatCommand) !void {
        var data = command.sbuf.data;
        var size = command.sbuf.size;
        var frame: *c.zframe_t = try c.zframe_new(data, size);
        var rc: c_int = c.zframe_send(&frame, zsock, 0);
        if (rc < 0) {
            return ArugulaError.SendFrameError;
        }
    }

    pub fn recv(_: Self) ![]ChatResponse {
        var resps: std.ArrayList(ChatResponse) = undefined;

        var more = 0;
        while (more >= 0) {
            var frame = try c.zframe_recv(&zsock);
            var dataSize = c.zframe_size(frame);
            var dataPtr = c.zframe_data(frame);
            var sbuf: [dataSize]u8 = undefined;
            mem.copy(u8, sbuf, dataPtr);
            resps.append(ChatResponse.init(sbuf));

            more = c.zframe_more(frame);
            c.zframe_destroy(&frame);
        }
    }

    pub fn deinit(self: Self) void {
        c.zsock_destroy(self.zsock);
    }
};

test "basic coverage (exec)" {
    const allocator = std.testing.allocator;

    const client = Client.init("tcp://127.0.0.1:8055");
    defer client.deinit();

    var data = try std.fs.cwd().readFileAlloc(allocator, "out.wav", 4096);
    defer allocator.free(data);

    const cmd = try ChatCommand.init(1, 1, std.time.timestamp(), data);
    defer cmd.deinit();

    try client.send(cmd);
    for (try client.recv()) |r| {
        std.testing.expect(r.text != null);
    }
}
