const std = @import("std");
const State = @import("state.zig");

const InstructionFault = error{
    IllegalInstruction,
} || State.StackError;

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

fn skipInstruction(state: *State) void {
    state.pc += 2;
}

/// 0x00E0: clear the display
/// 0x00EE: return from a subroutine
const ClearOrReturn = struct {
    /// chip-8 state
    state: *State,
    /// instruction operand
    nnn: u12,

    const Self = @This();

    pub fn init(b1: u8, b2: u8, state: *State) Self {
        return .{ .state = state, .nnn = nnn(b1, b2) };
    }

    fn execute(self: Self) InstructionFault!void {
        switch (self.nnn) {
            0x0E0 => {
                @memset(&self.state.display, [_]bool{false} ** State.display_width);
            },
            0x0EE => {
                const addr = try self.state.popStack();
                self.state.pc = addr;
            },
            else => {
                return error.IllegalInstruction;
            },
        }
    }
};

/// 1NNN: jump to address
const Jump = struct {
    /// chip-8 state
    state: *State,
    /// instruction operand
    nnn: u12,

    const Self = @This();

    pub fn init(b1: u8, b2: u8, state: *State) Self {
        return .{
            .state = state,
            .nnn = nnn(b1, b2),
        };
    }

    pub fn execute(self: Self) InstructionFault!void {
        self.state.pc = self.nnn;
    }
};

/// 2NNN: call subroutine
const CallSubroutine = struct {
    /// chip-8 state
    state: *State,
    /// instruction operand
    nnn: u12,

    const Self = @This();

    pub fn init(b1: u8, b2: u8, state: *State) Self {
        return .{
            .state = state,
            .nnn = nnn(b1, b2),
        };
    }

    pub fn execute(self: Self) InstructionFault!void {
        try self.state.pushToStack(self.state.pc);
        self.state.pc = self.nnn;
    }
};

/// 0x3XNN: skip next instruction if a value equal to that of a register
const EqualValue = struct {
    state: *State,
    x: u4,
    nn: u8,

    const Self = @This();

    pub fn init(b1: u8, b2: u8, state: *State) Self {
        const x, const nn = xnn(b1, b2);
        return .{ .x = x, .nn = nn, .state = state };
    }

    pub fn execute(self: Self) InstructionFault!void {
        if (self.state.V[self.x] == self.nn) {
            skipInstruction(self.state);
        }
    }
};

/// 0x4XNN: skip next instruction if a value not equal to that of a register
const NotEqualValue = struct {
    state: *State,
    x: u4,
    nn: u8,

    const Self = @This();

    pub fn init(b1: u8, b2: u8, state: *State) Self {
        const x, const nn = xnn(b1, b2);
        return .{ .x = x, .nn = nn, .state = state };
    }

    pub fn execute(self: Self) InstructionFault!void {
        if (self.state.V[self.x] != self.nn) {
            skipInstruction(self.state);
        }
    }
};

/// 0x5XN0: skip next instruction if two registers have equal value
const EqualRegisters = struct {
    state: *State,
    x: u4,
    y: u4,
    n: u4,

    const Self = @This();

    pub fn init(b1: u8, b2: u8, state: *State) Self {
        const x, const y, const n = xyn(b1, b2);
        return .{
            .x = x,
            .y = y,
            .n = n,
            .state = state,
        };
    }

    pub fn execute(self: Self) InstructionFault!void {
        if (self.n != 0x0) {
            return error.IllegalInstruction;
        }
        if (self.state.V[self.x] == self.state.V[self.y]) {
            skipInstruction(self.state);
        }
    }
};

/// 0x9XN0: skip next instruction if two registers don't have equal value
const NotEqualRegisters = struct {
    state: *State,
    x: u4,
    y: u4,
    n: u4,

    const Self = @This();

    pub fn init(b1: u8, b2: u8, state: *State) Self {
        const x, const y, const n = xyn(b1, b2);
        return .{
            .x = x,
            .y = y,
            .n = n,
            .state = state,
        };
    }

    pub fn execute(self: Self) InstructionFault!void {
        if (self.n != 0x0) {
            return error.IllegalInstruction;
        }
        if (self.state.V[self.x] != self.state.V[self.y]) {
            skipInstruction(self.state);
        }
    }
};

/// 0x6XNN: move a value to register
const MoveValue = struct {
    x: u4,
    nn: u8,
    state: *State,

    const Self = @This();

    pub fn init(b1: u8, b2: u8, state: *State) Self {
        const x, const nn = xnn(b1, b2);
        return .{
            .x = x,
            .nn = nn,
            .state = state,
        };
    }

    pub fn execute(self: Self) InstructionFault!void {
        self.state.V[self.x] = self.nn;
    }
};

/// 0x7XNN: add a value to register
const AddValue = struct {
    x: u4,
    nn: u8,
    state: *State,

    const Self = @This();

    pub fn init(x: u4, nn: u8, state: *State) Self {
        // zig fmt: off
        return .{ 
            .x = x,
            .nn = nn,
            .state = state 
        };
        // zig fmt: on
    }

    pub fn execute(self: Self) InstructionFault!void {
        self.state.V[self.x] += self.nn;
    }
};

/// 0x8XYN: logical arthmetic operation
const ArithmeticLogic = struct {
    state: *State,
    x: u4,
    y: u4,
    n: u4,

    const Self = @This();

    pub fn init(b1: u8, b2: u8, state: *State) Self {
        const x, const y, const n = xyn(b1, b2);
        return .{
            .x = x,
            .y = y,
            .n = n,
            .state = state,
        };
    }

    pub fn execute(self: Self) InstructionFault!void {
        switch (self.n) {
            0x0 => {
                self.state.V[self.x] = self.state.V[self.y];
            },
            0x1 => {
                self.state.V[self.x] |= self.state.V[self.y];
            },
            0x2 => {
                self.state.V[self.x] &= self.state.V[self.y];
            },
            0x3 => {
                self.state.V[self.x] ^= self.state.V[self.y];
            },
            0x4 => {
                const res, const overflow = @addWithOverflow(self.state.V[self.x], self.state.V[self.y]);
                self.state.V[self.x] = res;
                self.state.V[0xF] = overflow;
            },
            0x5 => {
                const res, const overflow = @subWithOverflow(self.state.V[self.x], self.state.V[self.y]);
                self.state.V[self.x] = res;
                self.state.V[0xF] = overflow;
            },
            0x6 => {
                self.state.V[0xF] = self.state.V[self.y] & 1;
                self.state.V[self.x] = self.state.V[self.y] >> 1;
            },
            0x7 => {
                const res, const overflow = @subWithOverflow(self.state.V[self.y], self.state.V[self.x]);
                self.state.V[self.x] = res;
                self.state.V[0xF] = overflow;
            },
            0xE => {
                const res, const overflow = @shlWithOverflow(self.state.V[self.y], 1);
                self.state.V[self.x] = res;
                self.state.V[0xF] = overflow;
            },
            else => {
                return error.IllegalInstruction;
            },
        }
    }
};

/// 0xANNN: set the value of the I register
const SetI = struct {
    nnn: u12,
    state: *State,

    const Self = @This();

    pub fn init(b1: u8, b2: u8, state: *State) Self {
        return .{
            .nnn = nnn(b1, b2),
            .state = state,
        };
    }

    pub fn execute(self: Self) InstructionFault!void {
        self.state.I = self.nnn;
    }
};

/// 0xBNNN: jump to a certain address plus an offset
const JumpWithOffset = struct {
    nnn: u12,
    state: *State,

    const Self = @This();

    pub fn init(b1: u8, b2: u8, state: *State) Self {
        return .{
            .state = state,
            .nnn = nnn(b1, b2),
        };
    }

    pub fn execute(self: Self) InstructionFault!void {
        self.state.pc = self.nnn + self.state.V[0];
    }
};

/// 0xCXNN: generate random bytes
const RandomByte = struct {
    x: u4,
    nn: u8,
    random: *const std.Random,
    state: *State,

    const Self = @This();

    pub fn init(b1: u8, b2: u8, random: *const std.Random, state: *State) Self {
        const x, const nn = xnn(b1, b2);
        // zig fmt: off
        return .{
            .x = x,
            .nn = nn,
            .random = random,
            .state = state,
        };
        // zig fmt: on
    }

    pub fn execute(self: Self) InstructionFault!void {
        self.state.V[self.x] = self.nn & self.random.int(u8);
    }
};

/// 0xDXYN: draw a sprite on the display
const DrawSprite = struct {
    state: *State,
    x: u4,
    y: u4,
    n: u4,

    const Self = @This();

    pub fn init(b1: u8, b2: u8, state: *State) Self {
        const x, const y, const n = xyn(b1, b2);
        // zig fmt: off
        return .{
            .state = state,
            .x = x,
            .y = y,
            .n = n
        };
        // zig fmt: on
    }

    pub fn execute(self: Self) InstructionFault!void {
        const x = self.state.V[self.x] & 63;
        const y = self.state.V[self.y] & 31;

        const num_rows = self.n;

        for (0..num_rows) |row| {
            if (row + y == State.display_height) {
                break;
            }
            var row_pixels = self.state.memory[self.state.I + row];

            for (0..8) |col| {
                if (col + x >= State.display_width) {
                    continue;
                }
                const display_pixel: *bool = &self.state.display[row + y][col + x];
                const new_pixel = (row_pixels & 0x80) != 0;
                row_pixels <<= 1;

                if (display_pixel.* and new_pixel) {
                    self.state.V[0xF] = 0x1;
                }

                display_pixel.* ^= new_pixel;
            }
        }
    }
};

/// 0xEX9E: skip instruction if key (x) is pressed
/// 0xEXA1: skip instruction if key (x) is not pressed
/// the instruction doesn't wait for the key state change
const CheckKey = struct {
    state: *State,
    x: u4,
    nn: u8,

    const Self = @This();

    pub fn init(b1: u8, b2: u8, state: *State) Self {
        const x, const nn = xnn(b1, b2);
        // zig fmt: off
        return .{
            .state = state,
            .x = x,
            .nn = nn
        };
        // zig fmt: on
    }

    pub fn execute(self: Self) InstructionFault!void {
        const key = self.state.V[self.x];
        switch (self.nn) {
            0x9E => {
                if (self.state.keys[key]) {
                    skipInstruction(self.state);
                }
            },
            0xA1 => {
                if (!self.state.keys[key]) {
                    skipInstruction(self.state);
                }
            },
            else => {
                return error.IllegalInstruction;
            },
        }
    }
};

const Instruction = union(enum) {
    clear_or_return: ClearOrReturn,
    jump: Jump,
    call_subroutine: CallSubroutine,
    equal_value: EqualValue,
    not_equal_value: NotEqualValue,
    equal_registers: EqualRegisters,
    not_equal_registers: NotEqualRegisters,
    move_value: MoveValue,
    add_value: AddValue,
    arthmetic_logic: ArithmeticLogic,
    set_i: SetI,
    jump_with_offset: JumpWithOffset,
    random_byte: RandomByte,
    draw_sprite: DrawSprite,
    check_key: CheckKey,

    const Self = @This();

    pub fn execute(self: Self) InstructionFault!void {
        switch (self) {
            inline else => |instruction| {
                try instruction.execute();
            },
        }
    }
};

test "the operands decoding functions" {
    const code = [_]u8{ 0x1A, 0xBC };

    try std.testing.expectEqual(0xABC, nnn(code[0], code[1]));
    try std.testing.expectEqualDeep(struct { u4, u8 }{ 0xA, 0xBC }, xnn(code[0], code[1]));
    try std.testing.expectEqualDeep(struct { u4, u4, u4 }{ 0xA, 0xB, 0xC }, xyn(code[0], code[1]));
}

test "instruction 0x00E0" {
    var state = State.init();
    const code = [2]u8{ 0x00, 0xE0 };

    const instruction = Instruction{ .clear_or_return = ClearOrReturn.init(code[0], code[1], &state) };
    try instruction.execute();

    for (0..State.display_height) |i| {
        try std.testing.expectEqualSlices(bool, &[_]bool{false} ** State.display_width, &state.display[i]);
    }
}

test "instruction 0x00EE" {
    var state = State.init();
    const code = [2]u8{ 0x00, 0xEE };

    const pc = 0xAAA;
    try state.pushToStack(pc);
    state.pc = 0xBBB;

    const instruction = Instruction{ .clear_or_return = ClearOrReturn.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(pc, state.pc);
}

test "instruction 0x1NNN" {
    var state = State.init();
    const code = [2]u8{ 0x1A, 0x33 };

    const addr = 0xA33;
    try state.pushToStack(addr);

    const instruction = Instruction{ .jump = Jump.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(addr, state.pc);
}

test "instruction 2NNN" {
    var state = State.init();

    const subroutine_addr: u12 = 0xAAA;
    // zig fmt: off
    const code = [2]u8{ 
        0x20 | @as(u8, @truncate(subroutine_addr >> 8)),
        @truncate(subroutine_addr & 0xFF) 
    };
    // zig fmt: on

    const pc = 0xBBB;
    state.pc = pc;

    try CallSubroutine.init(code[0], code[1], &state).execute();

    skipInstruction(&state);
    skipInstruction(&state);
    skipInstruction(&state);

    try std.testing.expectEqual(subroutine_addr + 3 * 2, state.pc);

    const instruction = Instruction{ .clear_or_return = ClearOrReturn.init(0x00, 0xEE, &state) };
    try instruction.execute();
    try std.testing.expectEqual(pc, state.pc);
}

test "instruction 0x3NNN" {
    var state = State.init();

    const register: u4 = 0x6;
    const val: u8 = 0xDD;
    state.V[register] = val;
    // zig fmt: off
    const code = [2]u8{
       0x30 | @as(u8, register),
       val 
    };
    // zig fmt: on
    const pc = 0xAAA;
    state.pc = pc;

    try EqualValue.init(code[0], code[1], &state).execute();
    try std.testing.expectEqual(pc + 2, state.pc);

    state.pc = pc;
    state.V[register] = val - 1;

    const instruction = Instruction{ .equal_value = EqualValue.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(pc, state.pc);
}

test "instruction 0x4XNN" {
    var state = State.init();

    const register: u4 = 0x6;
    const val: u8 = 0xDD;
    state.V[register] = val - 1;

    // zig fmt: off
    const code = [2]u8{
        0x40 | @as(u8, register),
        val 
    };
    // zig fmt: on

    const pc = 0xAAA;
    state.pc = pc;

    try NotEqualValue.init(code[0], code[1], &state).execute();
    try std.testing.expectEqual(pc + 2, state.pc);

    state.pc = pc;
    state.V[register] = val;

    const instruction = Instruction{ .not_equal_value = NotEqualValue.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(pc, state.pc);
}

test "instruction 0x5XY0" {
    var state = State.init();

    const register1: u4 = 0x6;
    const register2: u4 = 0xB;

    const val: u8 = 0xDD;

    state.V[register1] = val;
    state.V[register2] = val;

    // zig fmt: off
    const code = [2]u8{
        0x50 | @as(u8, register1), 
        @as(u8, register2) << 4 
    };
    // zig fmt: on
    const pc = 0xAAA;
    state.pc = pc;

    try EqualRegisters.init(code[0], code[1], &state).execute();
    try std.testing.expectEqual(pc + 2, state.pc);

    state.pc = pc;
    state.V[register2] = val - 1;

    const instruction = Instruction{ .equal_registers = EqualRegisters.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(pc, state.pc);
}

test "instruction 0x9XY0" {
    var state = State.init();

    const register1: u4 = 0x6;
    const register2: u4 = 0xB;

    const val: u8 = 0xDD;

    state.V[register1] = val;
    state.V[register2] = val - 1;

    // zig fmt: off
    const code = [2]u8{
        0x90 | @as(u8, register1), 
        @as(u8, register2) << 4 
    };
    // zig fmt: on
    const pc = 0xAAA;
    state.pc = pc;

    try NotEqualRegisters.init(code[0], code[1], &state).execute();
    try std.testing.expectEqual(pc + 2, state.pc);

    state.pc = pc;
    state.V[register2] = val;

    const instruction = Instruction{ .not_equal_registers = NotEqualRegisters.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(pc, state.pc);
}

test "instruction 0x8XYN: move value between registers 0x8XY0" {
    var state = State.init();

    const register1: u4 = 0x4;
    const register2: u4 = 0xC;

    const val1: u8 = 0x56;

    state.V[register2] = val1;

    // zig fmt: off
    const code = [2]u8{
        0x80 | @as(u8, register1),
        @as(u8, register2) << 4
    };
    // zig fmt: on
    const instruction = Instruction{ .arthmetic_logic = ArithmeticLogic.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(val1, state.V[register2]);
}

test "instruction 0x8XYN: binary OR operation 0x8XY1" {
    var state = State.init();

    const register1: u4 = 0x9;
    const register2: u4 = 0x2;

    const val1: u8 = 0x6A;
    const val2: u8 = 0x8C;
    const res: u8 = val1 | val2;

    state.V[register1] = val1;
    state.V[register2] = val2;

    // zig fmt: off
    const code = [2]u8{
        0x80 | @as(u8, register1),
        @as(u8, register2) << 4 | 0x1
    };
    // zig fmt: on
    const instruction = Instruction{ .arthmetic_logic = ArithmeticLogic.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(res, state.V[register1]);
}

test "instruction 0x8XYN: binary AND operation 0x8XY2" {
    var state = State.init();

    const register1: u4 = 0x6;
    const register2: u4 = 0xD;

    const val1 = 0x45;
    const val2 = 0x91;
    const res = val1 & val2;

    state.V[register1] = val1;
    state.V[register2] = val2;

    // zig fmt: off
    const code = [2]u8{
        0x80 | @as(u8, register1),
        @as(u8, register2) << 4 | 0x2
    };
    // zig fmt: on
    const instruction = Instruction{ .arthmetic_logic = ArithmeticLogic.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(res, state.V[register1]);
}

test "instruction 0x8XYN: binary XOR operation 0x8XY3" {
    var state = State.init();

    const register1 = 0x1;
    const register2 = 0xE;

    const val1 = 0xB8;
    const val2 = 0x91;
    const res = val1 ^ val2;

    state.V[register1] = val1;
    state.V[register2] = val2;

    // zig fmt: off
    const code = [2]u8{
        0x80 | @as(u8, register1),
        @as(u8, register2) << 4 | 0x3
    };
    // zig fmt: on
    const instruction = Instruction{ .arthmetic_logic = ArithmeticLogic.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(res, state.V[register1]);
}

test "instruction 0x8XYN: byte addition operation 0x8XY4 without overflow" {
    var state = State.init();

    const register1: u4 = 0x4;
    const register2: u4 = 0xC;

    const val1: u8 = 0x16;
    const val2: u8 = 0x23;
    const res: u8 = val1 + val2;

    state.V[register1] = val1;
    state.V[register2] = val2;

    // zig fmt: off
    const code = [2]u8{
        0x80 | @as(u8, register1),
        @as(u8, register2) << 4 | 0x4
    };
    // zig fmt: on
    const instruction = Instruction{ .arthmetic_logic = ArithmeticLogic.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(res, state.V[register1]);
    try std.testing.expectEqual(0x0, state.V[0xF]);
}

test "instruction 0x8XYN: byte addition operation 0x8XY4 with overflow" {
    var state = State.init();

    const register1: u4 = 0x4;
    const register2: u4 = 0xC;

    const val1: u8 = 0xFB;
    const val2: u8 = 0xBB;
    const res: u8 = val1 +% val2;

    state.V[register1] = val1;
    state.V[register2] = val2;
    // zig fmt: off
    const code = [2]u8{
        0x80 | @as(u8, register1),
        @as(u8, register2) << 4 | 0x4
    };
    // zig fmt: on
    const instruction = Instruction{ .arthmetic_logic = ArithmeticLogic.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(res, state.V[register1]);
    try std.testing.expectEqual(0x1, state.V[0xF]);
}

test "instruction 0x8XYN: byte subtraction operation 0x8XY5 without overflow" {
    var state = State.init();

    const register1: u4 = 0x6;
    const register2: u4 = 0x7;

    const val1: u8 = 0xC1;
    const val2: u8 = 0x14;

    const res: u8 = val1 - val2;

    state.V[register1] = val1;
    state.V[register2] = val2;
    // zig fmt: off
    const code = [2]u8{
        0x80 | @as(u8, register1),
        @as(u8, register2) << 4 | 0x5
    };
    // zig fmt: on
    const instruction = Instruction{ .arthmetic_logic = ArithmeticLogic.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(res, state.V[register1]);
    try std.testing.expectEqual(0x0, state.V[0xF]);
}

test "instruction 0x8XYN: byte subtraction operation 0x8XY5 with overflow" {
    var state = State.init();

    const register1: u4 = 0x6;
    const register2: u4 = 0x7;

    const val1: u8 = 0x14;
    const val2: u8 = 0xC4;

    const res: u8 = val1 -% val2;

    state.V[register1] = val1;
    state.V[register2] = val2;
    // zig fmt: off
    const code = [2]u8{
        0x80 | @as(u8, register1),
        @as(u8, register2) << 4 | 0x5
    };
    // zig fmt: on
    const instruction = Instruction{ .arthmetic_logic = ArithmeticLogic.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(res, state.V[register1]);
    try std.testing.expectEqual(0x1, state.V[0xF]);
}

test "instruction 0x8XYN: byte subtraction operation 0x8XY7 without overflow" {
    var state = State.init();

    const register1: u4 = 0x6;
    const register2: u4 = 0x7;

    const val1: u8 = 0x14;
    const val2: u8 = 0xC1;

    const res: u8 = val2 - val1;

    state.V[register1] = val1;
    state.V[register2] = val2;
    // zig fmt: off
    const code = [2]u8{
        0x80 | @as(u8, register1),
        @as(u8, register2) << 4 | 0x7
    };
    // zig fmt: on
    const instruction = Instruction{ .arthmetic_logic = ArithmeticLogic.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(res, state.V[register1]);
    try std.testing.expectEqual(0x0, state.V[0xF]);
}

test "instruction 0x8XYN: byte subtraction operation 0x8XY7 with overflow" {
    var state = State.init();

    const register1: u4 = 0x6;
    const register2: u4 = 0x7;

    const val1: u8 = 0xC1;
    const val2: u8 = 0x14;

    const res: u8 = val2 -% val1;

    state.V[register1] = val1;
    state.V[register2] = val2;
    // zig fmt: off
    const code = [2]u8{
        0x80 | @as(u8, register1),
        @as(u8, register2) << 4 | 0x7
    };
    // zig fmt: on
    const instruction = Instruction{ .arthmetic_logic = ArithmeticLogic.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(res, state.V[register1]);
    try std.testing.expectEqual(0x1, state.V[0xF]);
}

test "instruction 0x8XYN: bit shift with operation 0x8XY6 without overflow" {
    var state = State.init();

    const register1: u4 = 0xA;
    const register2: u4 = 0x5;

    const val: u8 = 0b0111_0110;

    const res: u8 = val >> 1;

    state.V[register2] = val;
    // zig fmt: off
    const code = [2]u8{
        0x80 | @as(u8, register1),
        @as(u8, register2) << 4 | 0x6
    };
    // zig fmt: on
    const instruction = Instruction{ .arthmetic_logic = ArithmeticLogic.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(res, state.V[register1]);
    try std.testing.expectEqual(0x0, state.V[0xF]);
}

test "instruction 0x8XYN: bit shift with operation 0x8XY6 with overflow" {
    var state = State.init();

    const register1: u4 = 0xA;
    const register2: u4 = 0x5;

    const val: u8 = 0b0111_0111;

    const res: u8 = val >> 1;

    state.V[register2] = val;
    // zig fmt: off
    const code = [2]u8{
        0x80 | @as(u8, register1),
        @as(u8, register2) << 4 | 0x6
    };
    // zig fmt: on
    const instruction = Instruction{ .arthmetic_logic = ArithmeticLogic.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(res, state.V[register1]);
    try std.testing.expectEqual(0x1, state.V[0xF]);
}

test "instruction 0x8XYN: bit shift with operation 0x8XYE without overflow" {
    var state = State.init();

    const register1: u4 = 0xA;
    const register2: u4 = 0x5;

    const val: u8 = 0b0111_0110;

    const res: u8 = val << 1;

    state.V[register2] = val;
    // zig fmt: off
    const code = [2]u8{
        0x80 | @as(u8, register1),
        @as(u8, register2) << 4 | 0xE
    };
    // zig fmt: on
    const instruction = Instruction{ .arthmetic_logic = ArithmeticLogic.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(res, state.V[register1]);
    try std.testing.expectEqual(0x0, state.V[0xF]);
}

test "instruction 0x8XYN: bit shift with operation 0x8XYE with overflow" {
    var state = State.init();

    const register1: u4 = 0xA;
    const register2: u4 = 0x5;

    const val: u8 = 0b1111_0110;

    const res: u8 = val << 1;

    state.V[register2] = val;
    // zig fmt: off
    const code = [2]u8{
        0x80 | @as(u8, register1),
        @as(u8, register2) << 4 | 0xE
    };
    // zig fmt: on
    const instruction = Instruction{ .arthmetic_logic = ArithmeticLogic.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(res, state.V[register1]);
    try std.testing.expectEqual(0x1, state.V[0xF]);
}

test "instruction 0xANNN: set the address value of the I register" {
    var state = State.init();

    const address: u12 = 0xAAA;
    // zig fmt: off
    const code = [2]u8{
        0xA0 | @as(u8, @truncate(address >> 8)),
        @truncate(address & 0xFF)
    };
    // zig fmt: on
    const instruction = Instruction{ .set_i = SetI.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(address, state.I);
}

test "instruction 0xBNNN" {
    var state = State.init();

    const address: u12 = 0x315;
    const offset: u8 = 0x66;

    state.V[0] = offset;

    // zig fmt: off
    const code = [2]u8{
        0xB0 | @as(u8, @truncate(address >> 8)),
        @truncate(address & 0xFF)
    };
    // zig fmt: on
    const instruction = Instruction{ .jump_with_offset = JumpWithOffset.init(code[0], code[1], &state) };
    try instruction.execute();
    try std.testing.expectEqual(address + offset, state.pc);
}

test "instruction 0xCXNN" {
    var state = State.init();

    const register: u4 = 0x5;
    const mask: u8 = 0xFF;

    state.V[register] = mask;

    // zig fmt: off
    const code = [2]u8{
        0xB0 | @as(u8, register),
        mask
    };
    // zig fmt: on

    var engine: std.Random.DefaultPrng = .init(blk: {
        var buffer: [8]u8 = undefined;
        try std.posix.getrandom(&buffer);
        break :blk @as(u64, @bitCast(buffer));
    });

    const instruction = Instruction{ .random_byte = RandomByte.init(code[0], code[1], &engine.random(), &state) };

    const num_samples = 100_000;

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var frequencies: std.AutoHashMap(u8, u32) = .init(allocator);
    defer frequencies.deinit();

    for (0..num_samples) |_| {
        try instruction.execute();
        const res = try frequencies.getOrPut(state.V[register]);
        if (res.found_existing) res.value_ptr.* += 1 else res.value_ptr.* = 0;
    }

    const average_freq: f64 = num_samples / std.math.maxInt(u8);
    const top_threshold: u64 = @intFromFloat(1.2 * average_freq);
    const lower_threshold: u64 = @intFromFloat(0.8 * average_freq);

    var it = frequencies.iterator();

    while (it.next()) |elem| {
        const x = elem.value_ptr.*;
        try std.testing.expect(x > lower_threshold and x < top_threshold);
    }
}

fn spirte_to_bytes(comptime height: u4, comptime sprite: [height][8]bool) [height]u8 {
    var bytes: [height]u8 = undefined;

    inline for (0..height) |i| {
        var byte: u8 = 0;
        inline for (0..8) |j| {
            byte |= @as(u8, @intFromBool(sprite[i][j])) << j;
        }
        bytes[i] = byte;
    }

    return bytes;
}

test "instruction 0xDXYN" {
    var state = State.init();

    const sprite = [_][8]bool{
        .{ true, true, true, true, true, true, true, true }, // ..XXXX..
        .{ true, false, false, false, false, false, false, true }, // .X....X.
        .{ true, false, true, true, true, true, false, true }, // X.XXXX.X
        .{ true, false, true, false, false, true, false, true }, // X.X..X.X
        .{ true, false, true, false, false, true, false, true }, // X.X..X.X
        .{ true, false, true, true, true, true, false, true }, // X.XXXX.X
        .{ true, false, false, false, false, false, false, true }, // .X....X.
        .{ true, true, true, true, true, true, true, true }, // ..XXXX..
    };

    const sprite_addr = 0x100;
    const sprite_bytes = comptime spirte_to_bytes(sprite.len, sprite);
    @memcpy(state.memory[sprite_addr .. sprite_addr + sprite.len], &sprite_bytes);

    // draw the sprite
    const x1: u8 = 32;
    const y1: u8 = 14;

    const register1: u4 = 0x3;
    const register2: u4 = 0x7;

    state.V[register1] = x1;
    state.V[register2] = y1;
    state.I = sprite_addr;

    const num_rows: u4 = sprite.len;

    // zig fmt: off
    const code = [2]u8{
        0xB0 | @as(u8, register1),
        @as(u8, register2) << 4 | @as(u8, num_rows)
    };
    // zig fmt: on
    const instruction = Instruction{ .draw_sprite = DrawSprite.init(code[0], code[1], &state) };
    try instruction.execute();

    // check for the display pixels are rendered correctly
    for (0..sprite.len) |i| {
        try std.testing.expectEqualSlices(bool, &sprite[i], state.display[y1 + i][x1 .. x1 + 8]);
    }

    // render the same sprite again but clipped by the right edge of the display
    const x2: u8 = 59;
    const y2: u8 = 9;

    state.V[register1] = x2;
    state.V[register2] = y2;

    try instruction.execute();

    for (0..sprite.len) |i| {
        if (y2 + i > State.display_height) {
            break;
        }
        try std.testing.expectEqualSlices(bool, sprite[i][0..@min(State.display_width - x2, 8)], state.display[y2 + i][x2..@min(x2 + 8, State.display_width)]);
    }

    // render the sprite a third time but intersecting with the first rendered sprite pixels
    const x3: u8 = 36;
    const y3: u8 = 18;

    state.V[register1] = x3;
    state.V[register2] = y3;

    try instruction.execute();

    // zig fmt: off
    const overlap_pixels = [_][4]bool{
        .{ true, false, true, false },
        .{ false, true, false, true },
        .{ true, false, true, false },
        .{ false, true, false, true } 
    };
    // zig fmt: on
    for (0..overlap_pixels.len) |i| {
        try std.testing.expectEqualSlices(bool, &overlap_pixels[i], state.display[y3 + i][x3 .. x3 + overlap_pixels[0].len]);
    }
}

test "0xEX9E - 0xEXA1: check for key state(no waiting)" {
    var state = State.init();

    const key: u4 = 0xA;
    const register: u4 = 0x6;
    const pc = 0x100;

    state.keys[key] = true;
    state.V[register] = key;
    state.pc = pc;

    // zig fmt: off
    const code = [2]u8{
        0xE0 | @as(u8, register),
        0x9E
    };
    // zig fmt: on
    const instruction = Instruction{ .check_key = CheckKey.init(code[0], code[1], &state) };
    try instruction.execute();

    try std.testing.expectEqual(pc + 2, state.pc);

    state.keys[key] = false;
    state.pc = pc;

    // zig fmt: off
    const code2 = [2]u8{
        0xE0 | @as(u8, register),
        0xA1
    };
    // zig fmt: on

    const instruction2 = Instruction{ .check_key = CheckKey.init(code2[0], code2[1], &state) };
    try instruction2.execute();

    try std.testing.expectEqual(pc + 2, state.pc);
}
