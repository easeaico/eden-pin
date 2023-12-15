const std = @import("std");
const net = std.net;
const mem = std.mem;
const io = std.io;
const fmt = std.fmt;

pub const Command = struct {
    const Self = @This();

    var data: std.ArrayList(u8) = undefined;

    fn init(allocator: mem.Allocator, name: []const u8) !Self {
        data = std.ArrayList(u8).init(allocator);
        try data.appendSlice(name);

        return Self{};
    }

    fn addArg(_: Self, arg: []const u8) !void {
        try data.append(' ');
        try data.appendSlice(arg);
    }

    fn setBody(_: Self, body: []const u8) !void {
        try data.append(' ');
        try fmt.formatInt(body.len, 10, .lower, .{}, data.writer());
        try data.append('\n');
        try data.appendSlice(body);
    }

    fn packData(_: Self) []const u8 {
        return data.items;
    }

    fn deinit(_: Self) void {
        data.deinit();
    }
};

pub const Result = struct {
    const Self = @This();

    values: std.ArrayList([]const u8),
    body: []const u8,
    allocator: mem.Allocator,

    fn init(allocator: mem.Allocator, valueArray: std.ArrayList([]const u8), bodyData: []const u8) Self {
        return Self{
            .values = valueArray,
            .body = bodyData,
            .allocator = allocator,
        };
    }

    fn deinit(self: Self) void {
        self.values.deinit();
        self.allocator.free(self.body);
    }

    fn getValues(self: Self) [][]const u8 {
        return self.values.items;
    }

    fn getBody(self: Self) []const u8 {
        return self.body;
    }
};

pub const Errors = error{
    ConnectionErr,
    ExecutionErr,
};

pub const Client = struct {
    const Self = @This();

    allocator: mem.Allocator,
    address: net.Address,

    var stream: net.Stream = undefined;

    fn init(allocator: mem.Allocator, address: net.Address) Self {
        return Self{
            .allocator = allocator,
            .address = address,
        };
    }

    fn connect(self: Self) !void {
        stream = try net.tcpConnectToAddress(self.address);

        var list = std.ArrayList(u8).init(self.allocator);
        defer list.deinit();

        try stream.reader().streamUntilDelimiter(list.writer(), '\n', null);

        if (!mem.eql(u8, "OK ARUGULA 0.1.0", list.items)) {
            return Errors.ConnectionErr;
        }
    }

    fn exec(self: Self, command: Command) !Result {
        const data = command.packData();
        _ = try stream.write(data);

        var list = std.ArrayList(u8).init(self.allocator);
        defer list.deinit();

        try stream.reader().streamUntilDelimiter(list.writer(), '\n', null);

        var it = mem.split(u8, list.items, " ");
        if (it.next()) |v| {
            if (!mem.eql(u8, v, "RSP")) {
                return Errors.ExecutionErr;
            }
        }

        var values = std.ArrayList([]const u8).init(self.allocator);
        while (it.next()) |v| {
            try values.append(v);
        }

        const bsize = try fmt.parseUnsigned(usize, values.pop(), 10);
        const body = try self.allocator.alloc(u8, bsize);

        const s = try stream.reader().read(body);
        if (bsize != s) {
            return Errors.ExecutionErr;
        }

        return Result.init(self.allocator, values, body);
    }
};

const testing = std.testing;

test "basic coverage (exec)" {
    const allocator = std.testing.allocator;
    const client = Client.init(allocator, try net.Address.parseIp("127.0.0.1", 9999));
    try client.connect();

    const cmd = try Command.init(allocator, "CHAT");
    defer cmd.deinit();

    try cmd.addArg("1");
    try cmd.addArg("1");
    try cmd.addArg("1");
    try cmd.setBody("哈哈哈");

    const result = try client.exec(cmd);
    defer result.deinit();

    try testing.expect(mem.eql(u8, "呵呵呵", result.getBody()));
}
