const std = @import("std");
const arugula = @import("arugula.zig");
const playback = @import("playback.zig");
const capture = @import("capture.zig");

const io = std.io;
const net = std.net;
const fmt = std.fmt;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    _ = allocator;
    const client = arugula.Client.init("127.0.0.1:8055");

    const act = std.os.Sigaction{
        .handler = .{ .handler = capture.signalHandler },
        .mask = std.os.empty_sigset,
        .flags = 0,
    };
    try std.os.sigaction(std.os.SIG.INT, &act, null);

    var buf: [4096]u8 = undefined;
    var len = try capture.capture(&buf);

    const cmd = try arugula.ChatCommand.init(1, 1, std.time.timestamp(), buf[0..len]);
    defer cmd.deinit();

    try client.send(cmd);
    for (try client.recv()) |r| {
        try playback.playback(r.audio);
    }
}
