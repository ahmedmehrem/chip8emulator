//! The struct file defines the chip-8 state. The emulator(It's more of an interpreter)
//! treats the chip as a finite state machine. Any instruction executed by the emulator
//! will alter the state memory, stack and registers

const std = @import("std");

pub const StackError = error{
    StackUnderflow,
    StackOverflow,
};

pub const memory_size = 4096;
pub const display_width = 64;
pub const display_height = 32;
pub const stack_size = 16;
pub const font_offset = 0x050;

/// the font bytes stored from font_offset to 0x9F
pub const font = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};
memory: [memory_size]u8,

display: [display_height][display_width]bool,
/// current instruction pointer
pc: u12,
/// index register
I: u12,
/// stack of addresses(I chose 16 arbitrarily)
stack: [16]u12,
/// stack index
si: u4,

delay_timer: u8,

sound_timer: u8,
/// the chip 16 registers
V: [16]u8,
/// the hexadecimal input keys
keys: [16]bool,

const Self = @This();

pub fn init() Self {
    var state: Self = .{
        .memory = [_]u8{0} ** 4096,
        .display = [_][display_width]bool{[_]bool{false} ** display_width} ** display_height,
        .pc = 0x200,
        .I = 0x0,
        .stack = [_]u12{0} ** 16,
        .si = 0,
        .delay_timer = 0,
        .sound_timer = 0,
        .V = [_]u8{0} ** 16,
        .keys = [_]bool{false} ** 16,
    };

    @memcpy(state.memory[font_offset .. font_offset + font.len], &font);

    return state;
}

pub fn popStack(self: *Self) StackError!u12 {
    if (self.si == 0) {
        return error.StackUnderflow;
    }

    const val = self.stack[self.si];
    self.si -= 1;

    return val;
}

pub fn pushToStack(self: *Self, addr: u12) StackError!void {
    if (self.si == 15) {
        return error.StackOverflow;
    }

    self.si += 1;
    self.stack[self.si] = addr;
}

test "chip-8 initial state" {
    const state = Self.init();

    try std.testing.expectEqualSlices(u8, &font, state.memory[font_offset .. font_offset + font.len]);
    try std.testing.expectEqual(0x200, state.pc);
}

test "push to and pop the chip stack" {
    var state = Self.init();

    const addrs = [_]u12{ 0xAAA, 0xBBB, 0xCCC };

    try state.pushToStack(addrs[0]);
    try state.pushToStack(addrs[1]);
    try state.pushToStack(addrs[2]);

    try std.testing.expectEqual(state.popStack(), addrs[2]);
    try std.testing.expectEqual(state.popStack(), addrs[1]);
    try std.testing.expectEqual(state.popStack(), addrs[0]);
}

test "stack overflow error" {
    var state = Self.init();

    const addrs = [_]u8{0xAA} ** (Self.stack_size + 1);

    for (0..Self.stack_size - 1) |i| {
        try state.pushToStack(addrs[i]);
    }

    try std.testing.expectError(error.StackOverflow, state.pushToStack(addrs[Self.stack_size]));
}

test "stack underflow error" {
    var state = Self.init();

    const addrs = [_]u12{ 0xAAA, 0xBBB, 0xCCC };

    try state.pushToStack(addrs[0]);
    try state.pushToStack(addrs[1]);
    try state.pushToStack(addrs[2]);

    for (0..3) |_| {
        _ = try state.popStack();
    }

    try std.testing.expectError(error.StackUnderflow, state.popStack());
}
