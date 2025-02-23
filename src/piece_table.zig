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

pub const PieceTable = struct {
    const EntryArray = ArrayList(PieceTableEntry);

    allocator: std.mem.Allocator,

    entries: EntryArray,
    original: []u8,
    changes: []u8,
    changes_len: usize = 0,

    const Self = @This();

    const Error = error{
        IndexOutOfRange,
    };

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

    pub fn insert(self: *Self, index: usize, data: []const u8) Error!void {
        if (index > self.length()) {
            return Error.IndexOutOfRange;
        }

        const change_start_index = self.changes_len;

        self.append_changes(data);

        if (index == self.length()) {
            self.entries.append(.{
                .source = .Changes,
                .start = change_start_index,
                .length = data.len,
            }) catch @panic("OOM");
        }

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

        self.entries.insert(split_entry_index + 2, self.entries.items[split_entry_index]) catch @panic("OOM");

        self.entries.items[split_entry_index + 2].length = split_entry_length - (index - entries_length);
        self.entries.items[split_entry_index + 2].start += index - entries_length;

        self.entries.items[split_entry_index].length = index - entries_length;
    }

    fn remove_one(self: *Self, index: usize) Error!void {
        if (index >= self.length()) {
            return Error.IndexOutOfRange;
        }

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

        if (entries_length + split_entry_length - 1 == index) {
            self.entries.items[split_entry_index].length -= 1;
        } else if (index - entries_length == 0) {
            self.entries.items[split_entry_index].start += 1;
            self.entries.items[split_entry_index].length -= 1;
        } else {
            self.entries.insert(split_entry_index + 1, self.entries.items[split_entry_index]) catch @panic("Out of bounds or OOM");

            self.entries.items[split_entry_index + 1].length -= (index - entries_length) + 1;
            self.entries.items[split_entry_index + 1].start += index - entries_length + 1;

            self.entries.items[split_entry_index].length = index - entries_length;
        }
    }

    pub fn remove(self: *Self, index: usize, count: usize) Error!void {
        for (0..count) |_| {
            self.remove_one(index) catch |err| return err;
        }
    }

    pub fn line_start(self: Self, line: usize) Error!usize {
        if (line == 0) {
            return 0;
        }

        var current_char: usize = 0;
        var current_line: usize = 0;

        for (0..self.entries.items.len) |i| {
            const entry_contents = self.entry_text(self.entries.items[i]);

            for (0..entry_contents.len) |j| {
                current_char += 1;

                if (entry_contents[j] == '\n') {
                    current_line += 1;

                    if (current_line == line) {
                        return current_char;
                    }
                }
            }
        }

        return Error.IndexOutOfRange;
    }

    pub fn line_length(self: Self, line: usize) Error!usize {
        var remaining_lines: usize = line;
        var current_char: usize = 0;

        const start = try self.line_start(line);

        for (0..self.entries.items.len) |i| {
            const entry_contents = self.entry_text(self.entries.items[i]);

            for (0..entry_contents.len) |j| {
                if (entry_contents[j] == '\n') {
                    if (remaining_lines == 0) {
                        return current_char - start;
                    }

                    remaining_lines -= 1;
                }

                current_char += 1;
            }
        }

        if (remaining_lines == 0) {
            return current_char - start;
        }

        return Error.IndexOutOfRange;
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

test "init piece table, add to it and check text" {
    const string = "This is some test data!\nThis is more data.";
    const expected_text = "Hello!\nThis certainly is some test data!\nThis is not more data.";

    var piece_table = PieceTable.init(std.testing.allocator, string);
    defer piece_table.deinit();

    try piece_table.insert(5, "certainly ");
    try piece_table.insert(42, "not ");
    try piece_table.insert(0, "Hello!\n");

    const actual_text = piece_table.text();
    defer piece_table.allocator.free(actual_text);

    try std.testing.expectEqualStrings(expected_text, actual_text);
}

test "init piece table, remove from it and check text" {
    const string = "This is some test data!\nThis is more data.";
    const expected_text = "This some test data\nThis more data";

    var piece_table = PieceTable.init(std.testing.allocator, string);
    defer piece_table.deinit();

    try piece_table.remove(5, 3);
    try piece_table.remove(26, 3);
    try piece_table.remove(19, 1);
    try piece_table.remove(34, 1);

    const actual_text = piece_table.text();
    defer piece_table.allocator.free(actual_text);

    try std.testing.expectEqualStrings(expected_text, actual_text);
}

test "init piece table, attempt to insert out of range" {
    const string = "This is some test data!\nThis is more data.";

    var piece_table = PieceTable.init(std.testing.allocator, string);
    defer piece_table.deinit();

    const ret = piece_table.insert(43, "Not allowed");
    try std.testing.expectError(PieceTable.Error.IndexOutOfRange, ret);
}

test "init piece table, attempt to remove out of range" {
    const string = "This is some test data!\nThis is more data.";

    var piece_table = PieceTable.init(std.testing.allocator, string);
    defer piece_table.deinit();

    const ret = piece_table.remove(42, 1);
    try std.testing.expectError(PieceTable.Error.IndexOutOfRange, ret);
}

test "init piece table, get start of various lines" {
    var piece_table = PieceTable.init(std.testing.allocator, "This is some test data!\nThis is more data.\nThis, yet again, is data\nYou're never going to believe it!\nI found some more data.");
    defer piece_table.deinit();

    try std.testing.expectEqual(0, piece_table.line_start(0));
    try std.testing.expectEqual(24, piece_table.line_start(1));
    try std.testing.expectEqual(43, piece_table.line_start(2));
    try std.testing.expectEqual(68, piece_table.line_start(3));
    try std.testing.expectEqual(102, piece_table.line_start(4));
}

test "init piece table, change data, get start of various lines" {
    var piece_table = PieceTable.init(std.testing.allocator, "This is some test data!\nThis is more data.\nThis, yet again, is data\nYou're never going to believe it!\nI found some more data.");
    defer piece_table.deinit();

    try piece_table.remove(0, 23);
    try piece_table.insert(0, "This is different test data.");

    try piece_table.insert(29, "More different data!\nWith a newline.\n");

    try std.testing.expectEqual(0, piece_table.line_start(0));
    try std.testing.expectEqual(29, piece_table.line_start(1));
    try std.testing.expectEqual(50, piece_table.line_start(2));
    try std.testing.expectEqual(66, piece_table.line_start(3));
    try std.testing.expectEqual(85, piece_table.line_start(4));
    try std.testing.expectEqual(110, piece_table.line_start(5));
    try std.testing.expectEqual(144, piece_table.line_start(6));
}

test "init piece table, get length of lines" {
    var piece_table = PieceTable.init(std.testing.allocator, "This is some test data!\nThis is more data.\nThis, yet again, is data\nYou're never going to believe it!\nI found some more data.");
    defer piece_table.deinit();

    try std.testing.expectEqual(23, piece_table.line_length(0));
    try std.testing.expectEqual(18, piece_table.line_length(1));
    try std.testing.expectEqual(24, piece_table.line_length(2));
    try std.testing.expectEqual(33, piece_table.line_length(3));
    try std.testing.expectEqual(23, piece_table.line_length(4));
}

test "init piece table, chance contents, get length of lines" {
    var piece_table = PieceTable.init(std.testing.allocator, "This is some test data!\nThis is more data.\nThis, yet again, is data\nYou're never going to believe it!\nI found some more data.");
    defer piece_table.deinit();

    try piece_table.remove(5, 3);
    try piece_table.remove(26, 3);
    try piece_table.remove(41, 12);
    try piece_table.remove(57, 45);
    try piece_table.insert(62, "\nWe're all data.");

    try std.testing.expectEqual(20, piece_table.line_length(0));
    try std.testing.expectEqual(15, piece_table.line_length(1));
    try std.testing.expectEqual(12, piece_table.line_length(2));
    try std.testing.expectEqual(12, piece_table.line_length(3));
    try std.testing.expectEqual(15, piece_table.line_length(4));
}
