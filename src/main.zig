const std = @import("std");
const capture = @import("capture.zig");

pub fn main() !void {
    const act = std.os.Sigaction{
        .handler = .{ .handler = capture.signalHandler },
        .mask = std.os.empty_sigset,
        .flags = 0,
    };
    try std.os.sigaction(std.os.SIG.INT, &act, null);
    try capture.capture();
}
