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

const eden_sever = "tcp://ec2-34-239-163-102.compute-1.amazonaws.com:8055";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const client = arugula.Client.init(allocator);
    defer client.deinit();

    try client.connect(eden_sever);
    log.info("eden server connected {s}", .{eden_sever});

    var gpio_mem = try gpio.Bcm2385GpioMemoryMapper.init();
    defer gpio_mem.deinit();

    var mapper = gpio_mem.mapper();
    var op = try gpio.GpioRegisterOperation.init(&mapper);
    defer op.deinit();

    // setup botton pin
    try op.setMode(btn_pin, gpio.Mode.Input);
    try op.setPull(btn_pin, gpio.PullMode.PullUp);
    // setup led pin
    try op.setMode(led_pin, gpio.Mode.Output);

    var player = asound.Player.init();
    defer player.deinit();

    try player.open();
    defer player.close();

    var capturer = asound.Capturer.init(allocator);
    defer capturer.deinit();

    try capturer.open();
    defer capturer.close();

    log.info("press button to speaking", .{});
    while (true) {
        captureToPlay(allocator, client, &capturer, &player, &op) catch |err| {
            log.err("capture to play error: {any}", .{err});
        };
    }
}

fn captureToPlay(allocator: mem.Allocator, client: arugula.Client, capturer: *asound.Capturer, player: *asound.Player, op: *gpio.GpioRegisterOperation) !void {
    var current_level = try op.getLevel(btn_pin);
    if (current_level == gpio.Level.High) { // not pressing
        return;
    }

    try capturer.spawnCapture();
    try op.setLevel(led_pin, gpio.Level.High);
    log.info("voice capturing", .{});

    while (true) {
        current_level = try op.getLevel(btn_pin);
        if (current_level == gpio.Level.Low) { // is pressing, continue to recording
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

        try op.setLevel(led_pin, gpio.Level.Low);
        log.info("data played", .{});
        return;
    }
}
