const terminal = @import("terminal.zig");

pub fn main() !void {
    try terminal.enable_rawmode();
    defer terminal.disable_rawmode() catch @panic("Failed to reset terminal to default state");

    // Text editing
}
