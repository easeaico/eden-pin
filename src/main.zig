const std = @import("std");
const arugula = @import("arugula.zig");
const asound = @import("asound.zig");

const io = std.io;
const net = std.net;
const fmt = std.fmt;
const log = std.log;
const mem = std.mem;
const Thread = std.Thread;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const client = try arugula.Client.init(allocator, "tcp://192.168.88.13:8055");
    defer client.deinit();

    while (true) {
        try captureAndPlay(allocator, client);
    }
}

fn captureAndPlay(allocator: mem.Allocator, client: arugula.Client) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    try stdout.print("enter to start recording", .{});
    var c = try stdin.readByte();
    if (c != '\n') {
        return;
    }

    var capturer = asound.Capturer.init(allocator);
    defer capturer.deinit();

    try capturer.spwanCapture();

    try stdout.print("enter to stop recording", .{});
    while (true) {
        c = try stdin.readByte();
        if (c != '\n') {
            continue;
        }

        var captured = capturer.stopCapture();
        log.info("data captured: {d}", .{captured.len});
        const cmd = try arugula.ChatCommand.init(allocator, 1, 1, captured);
        defer cmd.deinit();

        try client.send(&cmd);
        log.info("data sent!", .{});

        var resp = try client.recv();
        log.info("data recv: {s}", .{resp.text});
        try asound.play(resp.audio);
        log.info("data played", .{});
        return;
    }
}
