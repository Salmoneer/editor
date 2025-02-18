const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// A piece table with two buffers
const PieceTable = struct {
    const EntryArray = ArrayList(PieceTableEntry);

    allocator: std.mem.Allocator,

    entries: EntryArray,
    original: []u8,
    changes: []u8,

    const Self = @This();

    pub fn init(allocator: Allocator, original_data: []const u8) Self {
        const original = allocator.alloc(u8, original_data.len) catch @panic("OOM");
        std.mem.copyForwards(u8, original, original_data);

        const changes = allocator.alloc(u8, 1024) catch @panic("OOM");

        var entries = EntryArray.init(allocator);
        entries.append(.{
            .source = .Original,
            .start = 0,
            .length = original_data.len,
        }) catch @panic("OOM");

        return Self{
            .allocator = allocator,
            .original = original,
            .changes = changes,
            .entries = entries,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.original);
        self.allocator.free(self.changes);
        self.entries.deinit();
    }

    pub fn source_pointer(self: Self, source: PieceTableSource) []u8 {
        if (source == .Original) {
            return self.original;
        } else {
            return self.changes;
        }
    }

    pub fn entry_text(self: Self, entry: PieceTableEntry) []const u8 {
        const source = self.source_pointer(entry.source);

        return source[entry.start .. entry.start + entry.length];
    }

    pub fn length(self: Self) usize {
        var total: usize = 0;

        for (self.entries.items) |entry| {
            total += entry.length;
        }

        return total;
    }

    /// Allocates and returns the computed text of the piece table
    pub fn text(self: Self) []u8 {
        const string = self.allocator.alloc(u8, self.length()) catch @panic("OOM");
        var string_index: usize = 0;

        for (self.entries.items) |entry| {
            std.mem.copyForwards(u8, string[string_index..], self.entry_text(entry));
            string_index += entry.length;
        }

        return string;
    }
};

const PieceTableEntry = struct {
    source: PieceTableSource,
    start: usize,
    length: usize,
};

const PieceTableSource = enum {
    Original,
    Changes,
};

test "init and deinit empty piece table" {
    var piece_table = PieceTable.init(std.testing.allocator, "");
    defer piece_table.deinit();
}

test "init piece table with data" {
    var piece_table = PieceTable.init(std.testing.allocator, "This is some test data!\nThis is more data.");
    defer piece_table.deinit();
}
