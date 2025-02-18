const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const PieceTableEntry = struct {
    source: PieceTableSource,
    start: usize,
    length: usize,
};

const PieceTableSource = enum {
    Original,
    Changes,
};

/// A piece table with two buffers
const PieceTable = struct {
    const EntryArray = ArrayList(PieceTableEntry);

    allocator: std.mem.Allocator,

    entries: EntryArray,
    original: []u8,
    changes: []u8,
    changes_len: usize = 0,

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

    fn source_pointer(self: Self, source: PieceTableSource) []u8 {
        if (source == .Original) {
            return self.original;
        } else {
            return self.changes;
        }
    }

    fn entry_text(self: Self, entry: PieceTableEntry) []const u8 {
        const source = self.source_pointer(entry.source);

        return source[entry.start .. entry.start + entry.length];
    }

    /// Calculates the length of the computed text of the piece table
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

    fn append_changes(self: *Self, data: []const u8) void {
        const new_len = self.changes_len + data.len;

        if (new_len > self.changes.len) {
            self.changes = self.allocator.realloc(self.changes, @max(new_len, 2 * self.changes.len)) catch @panic("OOM");
        }

        std.mem.copyForwards(u8, self.changes[self.changes_len..], data);

        self.changes_len += data.len;
    }

    pub fn insert(self: *Self, index: usize, data: []const u8) void {
        const change_start_index = self.changes_len;

        self.append_changes(data);

        var split_entry_index: usize = 0;
        var split_entry_length: usize = 0;
        var entries_length: usize = 0;

        for (0.., self.entries.items) |i, entry| {
            if (entries_length + entry.length > index) {
                split_entry_index = i;
                split_entry_length = entry.length;
                break;
            }

            entries_length += entry.length;
        }

        self.entries.insert(split_entry_index + 1, .{
            .source = .Changes,
            .start = change_start_index,
            .length = data.len,
        }) catch @panic("Out of bounds or OOM");

        self.entries.insert(split_entry_index + 2, self.entries.items[split_entry_index]) catch @panic("Out of bounds or OOM");

        self.entries.items[split_entry_index + 2].length = split_entry_length - (index - entries_length);
        self.entries.items[split_entry_index + 2].start += index - entries_length;

        self.entries.items[split_entry_index].length = index - entries_length;
    }
};

test "init and deinit empty piece table" {
    var piece_table = PieceTable.init(std.testing.allocator, "");
    defer piece_table.deinit();
}

test "init piece table with data" {
    var piece_table = PieceTable.init(std.testing.allocator, "This is some test data!\nThis is more data.");
    defer piece_table.deinit();
}

test "init piece table and check text" {
    const string = "This is some test data!\nThis is more data.";

    var piece_table = PieceTable.init(std.testing.allocator, string);
    defer piece_table.deinit();

    const actual_text = piece_table.text();
    defer piece_table.allocator.free(actual_text);

    try std.testing.expectEqualStrings(string, actual_text);
}

test "init piece table, modify it and check text" {
    const string = "This is some test data!\nThis is more data.";
    const expected_text = "Hello!\nThis certainly is some test data!\nThis is not more data.";

    var piece_table = PieceTable.init(std.testing.allocator, string);
    defer piece_table.deinit();

    piece_table.insert(5, "certainly ");
    piece_table.insert(42, "not ");
    piece_table.insert(0, "Hello!\n");

    const actual_text = piece_table.text();
    defer piece_table.allocator.free(actual_text);

    try std.testing.expectEqualStrings(expected_text, actual_text);
}
