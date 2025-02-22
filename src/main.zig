const std = @import("std");
const root = @import("root.zig");

pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}){};
    defer _ = da.deinit();

    const allocator = da.allocator();

    const arguments = try blk: {
        var args = try std.process.argsWithAllocator(allocator);
        _ = args.skip();
        defer args.deinit();
        var argv = std.ArrayList([:0]const u8).init(allocator);
        while (args.next()) |arg| {
            try argv.append(arg);
        }
        break :blk argv.toOwnedSlice();
    };
    defer allocator.free(arguments);

    if (arguments.len != 3) {
        std.log.err("Invalid arguments expect file path value.", .{});
        std.process.exit(1);
    }

    try root.writeYaml(allocator, arguments[0], arguments[1], arguments[2]);
}
