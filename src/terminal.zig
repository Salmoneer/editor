const std = @import("std");
const os = std.os.linux;

pub const RawModeError = error{
    GetTermios,
    SetTermios,
};

var reset_termios: os.termios = undefined;

pub fn enable_rawmode() RawModeError!void {
    const get_ret = os.tcgetattr(os.STDIN_FILENO, &reset_termios);

    if (get_ret != 0) {
        return RawModeError.GetTermios;
    }

    var raw_termios = reset_termios;

    raw_termios.iflag.IGNBRK = false;
    raw_termios.iflag.BRKINT = false;
    raw_termios.iflag.IGNPAR = false;
    raw_termios.iflag.PARMRK = false;
    raw_termios.iflag.INPCK = false;
    raw_termios.iflag.ISTRIP = false;
    raw_termios.iflag.INLCR = false;
    raw_termios.iflag.IGNCR = false;
    raw_termios.iflag.ICRNL = false;
    raw_termios.iflag.IXON = false;
    raw_termios.iflag.IXOFF = false;
    raw_termios.iflag.IXANY = false;
    raw_termios.iflag.IMAXBEL = false;

    raw_termios.oflag.OPOST = false;

    raw_termios.lflag.ECHO = false;
    raw_termios.lflag.ECHOE = false;
    raw_termios.lflag.ECHOK = false;
    raw_termios.lflag.ECHONL = false;
    raw_termios.lflag.ICANON = false;
    raw_termios.lflag.ISIG = false;
    raw_termios.lflag.IEXTEN = false;

    raw_termios.cflag.CSIZE = .CS8;
    raw_termios.cflag.PARENB = false;

    raw_termios.cc[@as(usize, @intFromEnum(os.V.MIN))] = 1;
    raw_termios.cc[@as(usize, @intFromEnum(os.V.TIME))] = 0;

    const set_ret = os.tcsetattr(os.STDIN_FILENO, os.TCSA.FLUSH, &raw_termios);

    if (set_ret != 0) {
        return RawModeError.SetTermios;
    }
}

pub fn disable_rawmode() RawModeError!void {
    const set_ret = os.tcsetattr(os.STDIN_FILENO, os.TCSA.FLUSH, &reset_termios);

    if (set_ret != 0) {
        return RawModeError.SetTermios;
    }
}

pub const KeyStroke = union(enum) {
    invalid,
    printable: [4]u8,
    escaped: SpecialKey,
};

pub const SpecialKey = enum(u8) {
    Ctrl_A = 1,
    Ctrl_B = 2,
    Ctrl_C = 3,
    Ctrl_D = 4,
    Ctrl_E = 5,
    Ctrl_F = 6,
    Ctrl_G = 7,
    Ctrl_H = 8,
    Tab = 9, // Ctrl_I
    Ctrl_J = 10,
    Ctrl_K = 11,
    Ctrl_L = 12,
    Enter = 13, // Ctrl_M
    Ctrl_N = 14,
    Ctrl_O = 15,
    Ctrl_P = 16,
    Ctrl_Q = 17,
    Ctrl_R = 18,
    Ctrl_S = 19,
    Ctrl_T = 20,
    Ctrl_U = 21,
    Ctrl_V = 22,
    Ctrl_W = 23,
    Ctrl_X = 24,
    Ctrl_Y = 25,
    Ctrl_Z = 26,

    Escape = 27,

    Backspace = 127,

    Delete,
};

var input: [64]u8 = .{undefined} ** 64;
var input_size: usize = 0;

fn trunc_inputs(n: usize) void {
    std.mem.copyBackwards(u8, &input, input[n..input_size]);
    input_size -= n;
}

fn identify_key() KeyStroke {
    var key: KeyStroke = undefined;

    const c = input[0];

    if (c != 27) {
        if (c >= 1 and c <= 26) {
            key = .{ .escaped = @enumFromInt(c) };
        } else if (c == 127) {
            key = .{ .escaped = .Backspace };
        } else {
            var data: [4]u8 = .{undefined} ** 4;
            data[0] = c;

            key = .{ .printable = data };
        }

        trunc_inputs(1);
    } else {
        if (input_size == 1) {
            key = .{ .escaped = .Escape };
            trunc_inputs(1);
        } else if (input_size >= 4 and std.mem.eql(u8, input[1..4], "[3~")) {
            key = .{ .escaped = .Delete };
            trunc_inputs(4);
        } else {
            trunc_inputs(1);
            return .invalid;
        }
    }

    return key;
}

pub fn get_key() KeyStroke {
    if (input_size == 0) {
        input_size = std.io.getStdIn().read(&input) catch @panic("Failed to read from stdin");
    }

    return identify_key();
}
