const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const yaml = @import("yaml");

export fn cWriteYaml(location: [*:0]const c_char, path: [*:0]const c_char, value: [*:0]const c_char) i32 {
    var buffer: [100000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const file = std.fs.cwd().createFile("nsYaml.log", .{ .truncate = true, .read = true }) catch return -1;
    defer file.close();
    std.fmt.format(file.writer(), "nsYaml log file", .{}) catch return -1;

    if (writeYaml(allocator, std.mem.span(@as([*:0]const u8, @ptrCast(location))), std.mem.span(@as([*:0]const u8, @ptrCast(path))), std.mem.span(@as([*:0]const u8, @ptrCast(value))))) {
        return 0;
    } else |err| {
        std.fmt.format(file.writer(), "error in writeYaml: {}", .{err}) catch return -1;
        return -1;
    }
}

const Node = union(enum) {
    const Self = @This();
    const supportedTruthyBooleanValue: [4][]const u8 = .{ "y", "yes", "on", "true" };
    const supportedFalsyBooleanValue: [4][]const u8 = .{ "n", "no", "off", "false" };

    map: std.StringArrayHashMapUnmanaged(Self),
    list: std.ArrayListUnmanaged(Self),
    value: yaml.Value,

    fn fromText(allocator: std.mem.Allocator, raw: []const u8) !Self {
        try_int: {
            const int = std.fmt.parseInt(i64, raw, 0) catch break :try_int;
            return .{ .value = .{ .int = int } };
        }

        try_float: {
            const float = std.fmt.parseFloat(f64, raw) catch break :try_float;
            return .{ .value = .{ .float = float } };
        }

        if (raw.len <= 5 and raw.len > 0) {
            const lower_raw = try std.ascii.allocLowerString(allocator, raw);
            for (supportedTruthyBooleanValue) |v| {
                if (std.mem.eql(u8, v, lower_raw)) {
                    return .{ .value = .{ .boolean = true } };
                }
            }

            for (supportedFalsyBooleanValue) |v| {
                if (std.mem.eql(u8, v, lower_raw)) {
                    return .{ .value = .{ .boolean = false } };
                }
            }
        }

        return .{ .value = .{ .string = raw } };
    }

    fn fromYaml(allocator: std.mem.Allocator, input: yaml.Value) !Self {
        switch (input) {
            .map => |m| {
                var map = std.StringArrayHashMapUnmanaged(Self).empty;
                for (m.keys()) |key| {
                    try map.put(allocator, key, try fromYaml(allocator, m.get(key).?));
                }
                return .{ .map = map };
            },
            .list => |l| {
                var list = std.ArrayListUnmanaged(Self).empty;
                for (l) |entry| {
                    try list.append(allocator, try fromYaml(allocator, entry));
                }
                return .{ .list = list };
            },
            .empty => {
                const map = std.StringArrayHashMapUnmanaged(Self).empty;
                return .{ .map = map };
            },
            else => |s| {
                return .{ .value = s };
            },
        }
    }

    fn toYaml(self: *Self, allocator: std.mem.Allocator) !yaml.Value {
        switch (self.*) {
            .map => |m| {
                var map = std.StringArrayHashMap(yaml.Value).init(allocator);
                for (m.keys()) |key| {
                    try map.put(key, try m.getPtr(key).?.toYaml(allocator));
                }
                return .{ .map = map };
            },
            .list => |l| {
                var list = std.ArrayList(yaml.Value).init(allocator);
                for (l.items) |*item| {
                    try list.append(try item.toYaml(allocator));
                }
                return .{ .list = list.items };
            },
            .value => |v| {
                return v;
            },
        }
    }
};

pub fn writeYaml(allocator: std.mem.Allocator, location: []const u8, path: []const u8, value: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const file = try std.fs.cwd().createFile(location, .{ .truncate = false, .read = true });
    defer file.close();

    const buffer_size = 2000;
    const file_buffer = try file.readToEndAlloc(arena.allocator(), buffer_size);

    var untyped = try yaml.Yaml.load(arena.allocator(), file_buffer);
    defer untyped.deinit();

    var root = try Node.fromYaml(arena.allocator(), if (untyped.docs.items.len >= 1) untyped.docs.items[0] else yaml.Value.empty);

    var it = std.mem.splitScalar(u8, path, '.');
    var currentNode = &root;
    while (it.next()) |pathElement| {
        // on last element set value
        if (it.peek() == null) {
            if (std.fmt.parseInt(usize, pathElement, 10)) |index| {
                if (index < currentNode.list.items.len) {
                    currentNode.list.items[index].value = .{ .string = value };
                } else if (index == currentNode.list.items.len) {
                    try currentNode.list.insert(arena.allocator(), index, try Node.fromText(arena.allocator(), value));
                } else {
                    return error.InsertionNotAllowed;
                }
            } else |_| {
                const result = try currentNode.map.getOrPut(arena.allocator(), pathElement);
                result.value_ptr.* = try Node.fromText(arena.allocator(), value);
            }
            break;
        }

        currentNode = blk: switch (currentNode.*) {
            .map => {
                const result = try currentNode.map.getOrPut(arena.allocator(), pathElement);
                if (result.found_existing) {
                    break :blk result.value_ptr;
                } else {
                    if (std.fmt.parseInt(usize, it.peek().?, 10)) |_| {
                        const new = std.ArrayListUnmanaged(Node).empty;
                        result.value_ptr.* = .{ .list = new };
                        break :blk result.value_ptr;
                    } else |_| {
                        const new = std.StringArrayHashMapUnmanaged(Node).empty;
                        result.value_ptr.* = .{ .map = new };
                        break :blk result.value_ptr;
                    }
                }
            },
            .list => {
                if (std.fmt.parseInt(usize, pathElement, 10)) |index| {
                    if (index < currentNode.list.items.len) {
                        break :blk &currentNode.list.items[index];
                    } else if (index == currentNode.list.items.len) {
                        const new = std.StringArrayHashMapUnmanaged(Node).empty;
                        try currentNode.list.insert(arena.allocator(), index, .{ .map = new });
                        break :blk &currentNode.list.items[index];
                    } else {
                        return error.ArrayIndexOutOfBound;
                    }
                } else |_| {
                    return error.InvalidArrayIndex;
                }
            },
            else => return error.InvalidOperation,
        };
    }

    const doc = try root.toYaml(arena.allocator());
    try file.seekTo(0);
    try doc.stringify(file.writer(), .{});
    _ = try file.write("\n");
    const endPos = try file.getPos();
    try file.setEndPos(endPos);
}

test "write yaml" {
    const allocator = std.testing.allocator;
    try writeYaml(allocator, "test.yaml", "key.test.test3.0.key3", "value3");

    const file = try std.fs.cwd().createFile("test.yaml", .{ .truncate = false, .read = true });
    defer file.close();

    const buffer_size = 2000;
    const file_buffer = try file.readToEndAlloc(allocator, buffer_size);
    allocator.free(file_buffer);

    const path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(path);
}
