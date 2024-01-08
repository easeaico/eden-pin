const std = @import("std");

pub const GpioRegister: type = u32;
pub const GpioRegisterMemory: type = []align(1) volatile GpioRegister;

/// an interface that gives us a mapping of the physical memory of the
/// peripherals
pub const GpioMemMapper = struct {
    ptr: *anyopaque,

    /// pointer to the actual function that provides a mapping of the memory
    map_fn: *const fn (ptr: *anyopaque) anyerror!GpioRegisterMemory,

    /// the convenience function with which to use the interface
    /// provides access to a mapping of the GPIO registers
    pub fn memoryMap(self: GpioMemMapper) !GpioRegisterMemory {
        return self.map_fn(self.ptr);
    }
};

/// A structure containin info about the BCM2835 chip
/// see this website which does a brilliant job of explaining everything
/// https://www.pieter-jan.com/node/15
/// The most important thing is to look at the BCM2835 peripheral manual (pi1 / p2)
/// and then see in section 1.2.3 how the register addresses in the manual relate with
/// the physical memory. Then see the Gpio section for an explanation of how to
/// operate the Gpio pins using the registers.
/// The primary source for all of this is the Broadcom BCM2835 ARM Peripherals Manual
pub const BoardInfo = struct {
    /// the *physical* address space of all peripherals
    pub const peripheral_addresses: AddressRange = .{ .start = 0x20000000, .len = 0xFFFFFF };
    // address space of the GPIO registers
    pub const gpio_registers = .{ .start = peripheral_addresses.start + 0x200000, .len = 0xB4 };
    // /// physical address space of the gpio registers GPFSEL{n} (function select)
    pub const gpfsel_registers: AddressRange = .{ .start = peripheral_addresses.start + 0x200000, .len = 6 * 4 };
    /// physical address space of the gpio registers GPSET{n} (output setting)
    pub const gpset_registers: AddressRange = .{ .start = gpfsel_registers.start + 0x1C, .len = 2 * 4 };
    /// physical address space of the gpio registers GPCLR{n} (clearing pin output)
    pub const gpclr_registers: AddressRange = .{ .start = gpfsel_registers.start + 0x28, .len = 2 * 4 };
    /// physical address space of the gpio registers GPLEV{n} (reading pin levels)
    pub const gplev_registers: AddressRange = .{ .start = gpfsel_registers.start + 0x34, .len = 2 * 4 };
    /// phys address space of the gpio register GPPUD (pull up / pull down)
    pub const gppud_register: AddressRange = .{ .start = gpfsel_registers.start + 0x94, .len = 1 * 4 };
    /// phys address space of the gpio register GPPUDCLK{n} (pull up / down clocks)
    pub const gppudclk_registers: AddressRange = .{ .start = gpfsel_registers.start + 0x98, .len = 2 * 4 };
    /// the number of GPIO pins. Pin indices start at 0.
    pub const NUM_GPIO_PINS = 53;
};

pub const Bcm2385GpioMemoryMapper = struct {
    const Self: type = @This();

    /// the raw bytes representing the memory mapping
    devgpiomem: []align(std.mem.page_size) u8,

    pub fn init() !Self {
        var devgpiomem = try std.fs.openFileAbsolute("/dev/gpiomem", std.fs.File.OpenFlags{ .mode = .read_write });
        defer devgpiomem.close();

        return Self{ .devgpiomem = try std.os.mmap(null, BoardInfo.gpio_registers.len, std.os.PROT.READ | std.os.PROT.WRITE, std.os.MAP.SHARED, devgpiomem.handle, 0) };
    }

    pub fn mapper(self: *Self) GpioMemMapper {
        return .{
            .ptr = self,
            .map_fn = memoryMap,
        };
    }

    /// unmap the mapped memory
    pub fn deinit(self: Self) void {
        std.os.munmap(self.devgpiomem);
    }

    pub fn memoryMap(ptr: *anyopaque) !GpioRegisterMemory {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return std.mem.bytesAsSlice(u32, self.devgpiomem);
    }
};

/// A physical adress starting at `start` with a length of `len` bytes
pub const AddressRange = struct { start: usize, len: usize };

/// enumerates the GPio level (high/low)
pub const Level = enum(u1) { High = 0x1, Low = 0x0 };

/// enumerates the gpio functionality
/// the enum values are the bits that need to be written into the
/// appropriate bits of the function select registers for a bin
/// see p 91,92 of http://www.raspberrypi.org/wp-content/uploads/2012/02/BCM2835-ARM-Peripherals.pdf
pub const Mode = enum(u3) {
    /// intput functionality
    Input = 0b000,
    /// output functionality
    Output = 0b001,
    /// not yet implemented
    Alternate0 = 0b100,
    /// not yet implemented
    Alternate1 = 0b101,
    /// not yet implemented
    Alternate2 = 0b110,
    /// not yet implemented
    Alternate3 = 0b111,
    /// not yet implemented
    Alternate4 = 0b011,
    /// not yet implemented
    Alternate5 = 0b010,
};

pub const PullMode = enum(u2) { Off = 0b00, PullDown = 0b01, PullUp = 0b10 };

pub const Error = error{
    /// not initialized
    Uninitialized,
    /// Pin number out of range (or not available for this functionality)
    IllegalPinNumber,
    /// a mode value that could not be recognized was read from the register
    IllegalMode,
};

pub const GpioRegisterOperation = struct {
    const Self = @This();

    /// if initialized points to the memory block that is provided by the gpio
    /// memory mapping interface
    gpio_registers: ?GpioRegisterMemory,
    is_init: bool = false,

    /// initialize the GPIO control with the given memory mapping
    pub fn init(memory_interface: *GpioMemMapper) !Self {
        return .{
            .gpio_registers = try memory_interface.memoryMap(),
        };
    }

    /// deinitialize
    /// This function will not release access of the GPIO memory, instead
    /// it will perform some cleanup for the internals of this implementation
    pub fn deinit(self: *Self) void {
        self.gpio_registers = null;
    }

    // write the given level to the pin
    pub fn setLevel(self: Self, pin_number: u8, level: Level) !void {
        try checkPinNumber(pin_number, BoardInfo);

        // register offset to find the correct set or clear register depending on the level:
        // setting works by writing a 1 to the bit that corresponds to the pin in the appropriate GPSET{n} register
        // and clearing works by writing a 1 to the bit that corresponds to the pin in the appropriate GPCLR{n} register
        // writing a 0 to those registers doesn't do anything
        const register_zero: u8 = switch (level) {
            .High => comptime gpioRegisterZeroIndex("gpset_registers", BoardInfo), // "set" GPSET{n} registers
            .Low => comptime gpioRegisterZeroIndex("gpclr_registers", BoardInfo), // "clear" GPCLR{n} registers
        };

        try setPinSingleBit(self.gpio_registers, .{ .pin_number = pin_number, .register_zero = register_zero }, 1);
    }

    pub fn getLevel(self: Self, pin_number: u8) !Level {
        const gplev_register_zero = comptime gpioRegisterZeroIndex("gplev_registers", BoardInfo);

        const bit: u1 = try getPinSingleBit(self.gpio_registers, .{ .register_zero = gplev_register_zero, .pin_number = pin_number });
        if (bit == 0) {
            return .Low;
        } else {
            return .High;
        }
    }
    // set the mode for the given pin.
    pub fn setMode(self: Self, pin_number: u8, mode: Mode) Error!void {
        var registers = self.gpio_registers orelse return Error.Uninitialized;
        try checkPinNumber(pin_number, BoardInfo);

        // a series of @bitSizeOf(Mode) is necessary to encapsulate the function of one pin
        // this is why we have to calculate the amount of pins that fit into a register by dividing
        // the number of bits in the register by the number of bits for the function
        // as of now 3 bits for the function and 32 bits for the register make 10 pins per register
        const pins_per_register = comptime @divTrunc(@bitSizeOf(GpioRegister), @bitSizeOf(Mode));

        const gpfsel_register_zero = comptime gpioRegisterZeroIndex("gpfsel_registers", BoardInfo);
        const n: @TypeOf(pin_number) = @divTrunc(pin_number, pins_per_register);

        // set the bits of the corresponding pins to zero so that we can bitwise or the correct mask to it below
        registers[gpfsel_register_zero + n] &= clearMask(pin_number); // use bitwise-& here
        registers[gpfsel_register_zero + n] |= modeMask(pin_number, mode); // use bitwise-| here TODO, this is dumb, rework the mode setting mask to not have the inverse!
    }

    // read the mode of the given pin number
    pub fn getMode(self: Self, pin_number: u8) !Mode {
        var registers = self.gpio_registers orelse return Error.Uninitialized;
        try checkPinNumber(pin_number, BoardInfo);

        const pins_per_register = comptime @divTrunc(@bitSizeOf(GpioRegister), @bitSizeOf(Mode));
        const gpfsel_register_zero = comptime gpioRegisterZeroIndex("gpfsel_registers", BoardInfo);
        const n: @TypeOf(pin_number) = @divTrunc(pin_number, pins_per_register);

        const ModeIntType = (@typeInfo(Mode).Enum.tag_type);

        const ones: GpioRegister = std.math.maxInt(ModeIntType);
        const shift_count = @bitSizeOf(Mode) * @as(u5, @intCast(pin_number % pins_per_register));
        const stencil_mask = ones << shift_count;
        const mode_value = @as(ModeIntType, @intCast((registers[gpfsel_register_zero + n] & stencil_mask) >> shift_count));

        inline for (std.meta.fields(Mode)) |mode| {
            if (mode.value == mode_value) {
                return @as(Mode, @enumFromInt(mode.value));
            }
        }

        return Error.IllegalMode;
    }

    pub fn setPull(self: Self, pin_number: u8, mode: PullMode) Error!void {
        var registers = self.gpio_registers orelse return Error.Uninitialized;

        // see the GPPUCLK register description for how to set the pull up or pull down on a per pin basis
        const gppud_register_zero = comptime gpioRegisterZeroIndex("gppud_register", BoardInfo);
        const gppudclk_register_zero = comptime gpioRegisterZeroIndex("gppudclk_registers", BoardInfo);
        const ten_us_in_ns = 10 * 1000;
        registers[gppud_register_zero] = @intFromEnum(mode);
        // TODO this may be janky, because no precision of timing is guaranteed
        // however, the manual only states that we have to wait 150 clock cycles
        // and we are being very generous here
        std.os.nanosleep(0, ten_us_in_ns);

        try setPinSingleBit(registers, .{ .pin_number = pin_number, .register_zero = gppudclk_register_zero }, 1);

        std.os.nanosleep(0, ten_us_in_ns);
        registers[gppud_register_zero] = @intFromEnum(PullMode.Off);
        try setPinSingleBit(registers, .{ .pin_number = pin_number, .register_zero = gppudclk_register_zero }, 0);
    }
};

const PinAndRegister = struct {
    pin_number: u8,
    register_zero: u8,
};

/// helper function for simplifying working with those contiguous registers where one GPIO bin is represented by one bit
/// needs the zero register for the set and the pin number and returns the bit (or an error)
inline fn getPinSingleBit(gpio_registers: ?GpioRegisterMemory, pin_and_register: PinAndRegister) !u1 {
    var registers = gpio_registers orelse return Error.Uninitialized;
    const pin_number = pin_and_register.pin_number;
    const register_zero = pin_and_register.register_zero;
    try checkPinNumber(pin_number, BoardInfo);

    const pins_per_register = comptime @bitSizeOf(GpioRegister);
    const n = @divTrunc(pin_number, pins_per_register);
    const pin_shift = @as(u5, @intCast(pin_number % pins_per_register));

    const pin_value = registers[register_zero + n] & (@as(GpioRegister, @intCast(1)) << pin_shift);
    if (pin_value == 0) {
        return 0;
    } else {
        return 1;
    }
}

/// helper function for simplifying the work with those contiguous registers where one GPIO pin is represented by one bit
/// this function sets the respective bit to the given value
inline fn setPinSingleBit(gpio_registers: ?GpioRegisterMemory, pin_and_register: PinAndRegister, comptime value_to_set: u1) !void {
    var registers = gpio_registers orelse return Error.Uninitialized;
    const pin_number = pin_and_register.pin_number;
    const register_zero = pin_and_register.register_zero;
    try checkPinNumber(pin_number, BoardInfo);

    const pins_per_register = comptime @bitSizeOf(GpioRegister);
    const n = @divTrunc(pin_number, pins_per_register);
    const pin_shift = @as(u5, @intCast(pin_number % pins_per_register));
    if (value_to_set == 1) {
        registers[register_zero + n] |= (@as(GpioRegister, @intCast(1)) << pin_shift);
    } else {
        registers[register_zero + n] &= ~(@as(GpioRegister, @intCast(1)) << pin_shift);
    }
}

/// calculates that mask that sets the mode for a given pin in a GPFSEL register.
/// ATTENTION: before this function is called, the clearMask must be applied to this register
inline fn modeMask(pin_number: u8, mode: Mode) GpioRegister {
    // a 32 bit register can only hold 10 pins, because a pin function is set by an u3 value.
    const pins_per_register = comptime @divTrunc(@bitSizeOf(GpioRegister), @bitSizeOf(Mode));
    const pin_bit_idx = pin_number % pins_per_register;
    // shift the mode to the correct bits for the pin. Mode mask 0...xxx...0
    return @as(GpioRegister, @intCast(@intFromEnum(mode))) << @as(u5, @intCast((pin_bit_idx * @bitSizeOf(Mode))));
}

fn gpioRegisterZeroIndex(comptime register_name: []const u8, comptime board_info: anytype) comptime_int {
    return comptime std.math.divExact(comptime_int, @field(board_info, register_name).start - board_info.gpio_registers.start, @sizeOf(GpioRegister)) catch @compileError("Offset not evenly divisible by register width");
}

/// just a helper function that returns an error iff the given pin number is illegal
/// the board info type must carry a NUM_GPIO_PINS member field indicating the number of gpio pins
inline fn checkPinNumber(pin_number: u8, comptime board_info: type) !void {
    if (@hasDecl(BoardInfo, "NUM_GPIO_PINS")) {
        if (pin_number < board_info.NUM_GPIO_PINS) {
            return;
        } else {
            return Error.IllegalPinNumber;
        }
    } else {
        @compileError("BoardInfo type must have a constant field NUM_GPIO_PINS indicating the number of gpio pins");
    }
}

/// make a binary mask for clearing the associated region of th GPFSET register
/// this mask can be binary-ANDed to the GPFSEL register to set the bits of the given pin to 0
inline fn clearMask(pin_number: u8) GpioRegister {
    const pins_per_register = comptime @divTrunc(@bitSizeOf(GpioRegister), @bitSizeOf(Mode));
    const pin_bit_idx = pin_number % pins_per_register;
    // the input config should be zero
    // if it is, then the following logic will work
    comptime std.debug.assert(@intFromEnum(Mode.Input) == 0);
    // convert the mode to a 3 bit integer: 0b000 (binary)
    // then invert the mode 111 (binary)
    // then convert this to an integer 000...000111 (binary) of register width
    // shift this by the appropriate amount (right now 3 bits per pin in a register)
    // 000...111...000
    // invert the whole thing and we end up with 111...000...111
    // we can bitwise and this to the register to clear the mode of the given pin
    // and prepare it for the set mode mask (which is bitwise or'd);
    return (~(@as(GpioRegister, @intCast(~@intFromEnum(Mode.Input))) << @as(u5, @intCast((pin_bit_idx * @bitSizeOf(Mode))))));
}

const testing = std.testing;

test "clearMask" {
    comptime std.debug.assert(@bitSizeOf(GpioRegister) == 32);
    comptime std.debug.assert(@bitSizeOf(Mode) == 3);

    try testing.expect(clearMask(0) == 0b11111111111111111111111111111000);
    std.log.info("mode mask = {b}", .{modeMask(3, Mode.Input)});
    try testing.expect(clearMask(3) == 0b11111111111111111111000111111111);
    try testing.expect(clearMask(13) == 0b11111111111111111111000111111111);
}

test "modeMask" {
    // since the code below is manually verified for 32bit registers and 3bit function info
    // we have to make sure this still holds at compile time.
    comptime std.debug.assert(@bitSizeOf(GpioRegister) == 32);
    comptime std.debug.assert(@bitSizeOf(Mode) == 3);

    // see online hex editor, e.g. https://hexed.it/
    try testing.expect(modeMask(0, Mode.Input) == 0);
    std.log.info("mode mask = {b}", .{modeMask(3, Mode.Input)});

    try testing.expect(modeMask(0, Mode.Output) == 0b00000000000000000000000000000001);
    try testing.expect(modeMask(3, Mode.Output) == 0b00000000000000000000001000000000);
    try testing.expect(modeMask(13, Mode.Alternate3) == 0b00000000000000000000111000000000);
}

test "gpioRegisterZeroIndex" {
    // the test is hand verified for 4 byte registers as is the case in the bcm2835
    // so we need to make sure this prerequisite is fulfilled
    comptime std.debug.assert(@sizeOf(GpioRegister) == 4);
    // manually verified using the BCM2835 ARM Peripherals Manual
    const board_info = BoardInfo;
    try testing.expectEqual(0, gpioRegisterZeroIndex("gpfsel_registers", board_info));
    try testing.expectEqual(7, gpioRegisterZeroIndex("gpset_registers", board_info));
    try testing.expectEqual(10, gpioRegisterZeroIndex("gpclr_registers", board_info));
    try testing.expectEqual(13, gpioRegisterZeroIndex("gplev_registers", board_info));
}

test "checkPinNumber" {
    const MyBoardInfo = struct {
        pub const NUM_GPIO_PINS: u8 = 20;
    };

    var pin: u8 = 0;
    while (pin < MyBoardInfo.NUM_GPIO_PINS) : (pin += 1) {
        try checkPinNumber(pin, MyBoardInfo);
    }

    while (pin < 2 * MyBoardInfo.NUM_GPIO_PINS) : (pin += 1) {
        try testing.expectError(Error.IllegalPinNumber, checkPinNumber(pin, MyBoardInfo));
    }
}

test "getPinSingleBit" {
    try std.testing.expectError(Error.Uninitialized, getPinSingleBit(null, .{ .pin_number = 1, .register_zero = 0 }));

    var three_registers = [3]GpioRegister{ std.math.maxInt(GpioRegister), 3, 5 };
    try std.testing.expectEqual(@as(u1, @intCast(1)), try getPinSingleBit(&three_registers, .{ .pin_number = 0, .register_zero = 1 }));
    try std.testing.expectEqual(@as(u1, @intCast(1)), try getPinSingleBit(&three_registers, .{ .pin_number = 1, .register_zero = 1 }));
    try std.testing.expectEqual(@as(u1, @intCast(0)), try getPinSingleBit(&three_registers, .{ .pin_number = 2, .register_zero = 1 }));
    try std.testing.expectEqual(@as(u1, @intCast(1)), try getPinSingleBit(&three_registers, .{ .pin_number = 32 + 0, .register_zero = 1 }));
    try std.testing.expectEqual(@as(u1, @intCast(0)), try getPinSingleBit(&three_registers, .{ .pin_number = 32 + 1, .register_zero = 1 }));
    try std.testing.expectEqual(@as(u1, @intCast(1)), try getPinSingleBit(&three_registers, .{ .pin_number = 32 + 2, .register_zero = 1 }));
}

test "setPinSingleBit" {
    var three_registers = [3]GpioRegister{ 0, 0, 0 };
    // try setting bits
    try setPinSingleBit(&three_registers, .{ .pin_number = 0, .register_zero = 1 }, 1);
    try setPinSingleBit(&three_registers, .{ .pin_number = 1, .register_zero = 1 }, 1);
    try setPinSingleBit(&three_registers, .{ .pin_number = 3, .register_zero = 1 }, 1);
    try setPinSingleBit(&three_registers, .{ .pin_number = 32 + 2, .register_zero = 1 }, 1);
    // and then also unset bits that are zero anyways (these should have no influence on the values)
    try setPinSingleBit(&three_registers, .{ .pin_number = 32 + 3, .register_zero = 1 }, 0);
    try setPinSingleBit(&three_registers, .{ .pin_number = 2, .register_zero = 1 }, 0);
    try std.testing.expectEqual(@as(GpioRegister, @intCast(0)), three_registers[0]);
    try std.testing.expectEqual(@as(GpioRegister, @intCast(1 + 2 + 8)), three_registers[1]);
    try std.testing.expectEqual(@as(GpioRegister, @intCast(4)), three_registers[2]);
    // now unset a bit
    try setPinSingleBit(&three_registers, .{ .pin_number = 1, .register_zero = 1 }, 0);
    try std.testing.expectEqual(@as(GpioRegister, @intCast(0)), three_registers[0]);
    try std.testing.expectEqual(@as(GpioRegister, @intCast(1 + 0 + 8)), three_registers[1]);
    try std.testing.expectEqual(@as(GpioRegister, @intCast(4)), three_registers[2]);
}
