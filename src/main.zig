const std = @import("std");
const arugula = @import("arugula.zig");
const asound = @import("asound.zig");
const gpio = @import("gpio.zig");

const io = std.io;
const net = std.net;
const fmt = std.fmt;
const log = std.log;
const mem = std.mem;
const Thread = std.Thread;

const led_pin = 16;
const btn_pin = 17;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const client = arugula.Client.init(allocator);
    defer client.deinit();

    try client.connect("tcp://192.168.88.13:8055"); //"tcp://ec2-34-239-163-102.compute-1.amazonaws.com:8055");

    //gpio.setMode(btn_pin, gpio.Mode.Input);
    //gpio.setPull(btn_pin, gpio.PullMode.PullUp);

    var player = asound.Player.init();
    defer player.deinit();

    var capturer = asound.Capturer.init(allocator);
    defer capturer.deinit();

    try capturer.open();
    defer capturer.close();

    while (true) {
        captureToPlay(allocator, client, &capturer, &player) catch |err| {
            log.err("capture to play error: {any}", .{err});
        };
    }
}

fn captureToPlay(allocator: mem.Allocator, client: arugula.Client, capturer: *asound.Capturer, player: *asound.Player) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    try stdout.print("enter to start recording", .{});
    var c = try stdin.readByte();
    if (c != '\n') {
        return;
    }

    try capturer.spawnCapture();

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
        defer resp.deinit();

        var results = resp.data.items;
        var datas = try allocator.alloc([]const u8, results.len);
        for (results, 0..) |r, i| {
            datas[i] = r.audio;
        }
        try player.spawnPlay(datas);
        player.join();

        log.info("data played", .{});
        return;
    }
}
