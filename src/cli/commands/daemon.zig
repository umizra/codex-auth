const std = @import("std");
const types = @import("../types.zig");
const common = @import("common.zig");

pub fn parse(allocator: std.mem.Allocator, args: []const [:0]const u8) !types.ParseResult {
    if (args.len == 1 and common.isHelpFlag(std.mem.sliceTo(args[0], 0))) {
        return .{ .command = .{ .help = .daemon } };
    }

    var watch = false;
    for (args) |raw_arg| {
        const arg = std.mem.sliceTo(raw_arg, 0);
        if (std.mem.eql(u8, arg, "--watch")) {
            if (watch) return common.usageErrorResult(allocator, .daemon, "duplicate `--watch` for `daemon`.", .{});
            watch = true;
            continue;
        }
        if (common.isHelpFlag(arg)) {
            return common.usageErrorResult(allocator, .daemon, "`--help` must be used by itself for `daemon`.", .{});
        }
        if (std.mem.startsWith(u8, arg, "-")) {
            return common.usageErrorResult(allocator, .daemon, "unknown flag `{s}` for `daemon`.", .{arg});
        }
        return common.usageErrorResult(allocator, .daemon, "unexpected argument `{s}` for `daemon`.", .{arg});
    }

    return .{ .command = .{ .daemon = .{ .watch = watch } } };
}
