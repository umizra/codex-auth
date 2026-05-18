const std = @import("std");
const types = @import("../types.zig");
const common = @import("common.zig");

pub fn parse(allocator: std.mem.Allocator, args: []const [:0]const u8) !types.ParseResult {
    if (args.len == 1 and common.isHelpFlag(std.mem.sliceTo(args[0], 0))) {
        return .{ .command = .{ .help = .batch_login } };
    }

    var accounts_path: ?[]u8 = null;
    var line_number: ?usize = null;
    var from_line_number: ?usize = null;
    var device_auth = false;
    var own_accounts_path = true;
    defer if (own_accounts_path) {
        if (accounts_path) |path| allocator.free(path);
    };

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = std.mem.sliceTo(args[i], 0);
        if (std.mem.eql(u8, arg, "--device-auth")) {
            if (device_auth) return common.usageErrorResult(allocator, .batch_login, "duplicate `--device-auth` for `batch-login`.", .{});
            device_auth = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--line")) {
            if (line_number != null) return common.usageErrorResult(allocator, .batch_login, "duplicate `--line` for `batch-login`.", .{});
            if (from_line_number != null) return common.usageErrorResult(allocator, .batch_login, "`--line` cannot be combined with `--from-line`.", .{});
            if (i + 1 >= args.len) return common.usageErrorResult(allocator, .batch_login, "missing value for `--line`.", .{});
            const line_value = std.mem.sliceTo(args[i + 1], 0);
            const parsed = std.fmt.parseUnsigned(usize, line_value, 10) catch
                return common.usageErrorResult(allocator, .batch_login, "invalid line number `{s}` for `batch-login`.", .{line_value});
            if (parsed == 0) return common.usageErrorResult(allocator, .batch_login, "`--line` must be 1 or greater.", .{});
            line_number = parsed;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--from-line")) {
            if (from_line_number != null) return common.usageErrorResult(allocator, .batch_login, "duplicate `--from-line` for `batch-login`.", .{});
            if (line_number != null) return common.usageErrorResult(allocator, .batch_login, "`--from-line` cannot be combined with `--line`.", .{});
            if (i + 1 >= args.len) return common.usageErrorResult(allocator, .batch_login, "missing value for `--from-line`.", .{});
            const line_value = std.mem.sliceTo(args[i + 1], 0);
            const parsed = std.fmt.parseUnsigned(usize, line_value, 10) catch
                return common.usageErrorResult(allocator, .batch_login, "invalid line number `{s}` for `batch-login`.", .{line_value});
            if (parsed == 0) return common.usageErrorResult(allocator, .batch_login, "`--from-line` must be 1 or greater.", .{});
            from_line_number = parsed;
            i += 1;
            continue;
        }
        if (common.isHelpFlag(arg)) {
            return common.usageErrorResult(allocator, .batch_login, "`--help` must be used by itself for `batch-login`.", .{});
        }
        if (std.mem.startsWith(u8, arg, "-")) return common.usageErrorResult(allocator, .batch_login, "unknown flag `{s}` for `batch-login`.", .{arg});
        if (accounts_path != null) return common.usageErrorResult(allocator, .batch_login, "unexpected extra path `{s}` for `batch-login`.", .{arg});
        accounts_path = try allocator.dupe(u8, arg);
    }

    if (accounts_path == null) {
        return common.usageErrorResult(allocator, .batch_login, "`batch-login` requires a path to an accounts file.", .{});
    }

    own_accounts_path = false;
    return .{ .command = .{ .batch_login = .{
        .accounts_path = accounts_path.?,
        .line_number = line_number,
        .from_line_number = from_line_number,
        .device_auth = device_auth,
    } } };
}
