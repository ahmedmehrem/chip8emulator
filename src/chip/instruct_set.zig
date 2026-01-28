const std = @import("std");

const InstructionFault = error{
    IllegalInstruction,
};

/// get the last 12 bits (NNN) operands from the instruction code
fn nnn(b1: u8, b2: u8) u12 {
    return (@as(u12, b1 & 0xF) << 8) | @as(u12, b2);
}

/// get the second 4 bits operand (X) and the last 8 bits (NN) from the instruction code
fn xnn(b1: u8, b2: u8) struct { u4, u8 } {
    return .{ @truncate(b1 & 0xF), b2 };
}

/// get the second 4 bits operand (X), the third 4 bits (Y)
/// and the fourth 4 bits (Z) from the instruction code
fn xyn(b1: u8, b2: u8) struct { u4, u4, u4 } {
    return .{
        @truncate(b1 & 0xF),
        @truncate(b2 >> 4),
        @truncate(b2 & 0xF),
    };
}

test "the operands decoding functions" {
    const code = [_]u8{ 0x1A, 0xBC };

    try std.testing.expectEqual(0xABC, nnn(code[0], code[1]));
    try std.testing.expectEqualDeep(struct { u4, u8 }{ 0xA, 0xBC }, xnn(code[0], code[1]));
    try std.testing.expectEqualDeep(struct { u4, u4, u4 }{ 0xA, 0xB, 0xC }, xyn(code[0], code[1]));
}

/// 0x00E0: clear the display
/// 0x00EE: return from a subroutine
const ClearOrReturn = struct {
    const Self = @This();

    fn execute(_: Self) InstructionFault!void {
        return undefined;
    }
};

const Instruction = union(enum) {
    clear_or_return: ClearOrReturn,

    const Self = @This();

    pub fn execute(self: Self) InstructionFault!void {
        switch (self) {
            else => |instruction| {
                instruction.execute();
            },
        }
    }
};
