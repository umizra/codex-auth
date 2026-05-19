const std = @import("std");
const types = @import("../types.zig");
const common = @import("common.zig");

pub fn parse(allocator: std.mem.Allocator, args: []const [:0]const u8) !types.ParseResult {
    if (args.len == 1 and common.isHelpFlag(std.mem.sliceTo(args[0], 0))) {
        return .{ .command = .{ .help = .list } };
    }

    var opts: types.ListOptions = .{};
    var query_returned = false;
    defer if (!query_returned) {
        if (opts.query) |query| allocator.free(query);
    };

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = std.mem.sliceTo(args[i], 0);
        if (std.mem.eql(u8, arg, "--live")) {
            if (opts.live) return common.usageErrorResult(allocator, .list, "duplicate `--live` for `list`.", .{});
            opts.live = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--active")) {
            if (opts.active_only) return common.usageErrorResult(allocator, .list, "duplicate `--active` for `list`.", .{});
            opts.active_only = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--api")) {
            switch (opts.api_mode) {
                .default => opts.api_mode = .force_api,
                .force_api => return common.usageErrorResult(allocator, .list, "duplicate `--api` for `list`.", .{}),
                .skip_api => return common.usageErrorResult(allocator, .list, "`--api` cannot be combined with `--skip-api` for `list`.", .{}),
            }
            continue;
        }
        if (std.mem.eql(u8, arg, "--skip-api")) {
            switch (opts.api_mode) {
                .default => opts.api_mode = .skip_api,
                .skip_api => return common.usageErrorResult(allocator, .list, "duplicate `--skip-api` for `list`.", .{}),
                .force_api => return common.usageErrorResult(allocator, .list, "`--api` cannot be combined with `--skip-api` for `list`.", .{}),
            }
            continue;
        }
        if (std.mem.eql(u8, arg, "--nonzero")) {
            if (opts.nonzero) return common.usageErrorResult(allocator, .list, "duplicate `--nonzero` for `list`.", .{});
            opts.nonzero = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--available")) {
            if (opts.available) return common.usageErrorResult(allocator, .list, "duplicate `--available` for `list`.", .{});
            opts.available = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--errors")) {
            if (opts.errors) return common.usageErrorResult(allocator, .list, "duplicate `--errors` for `list`.", .{});
            opts.errors = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--min")) {
            if (opts.min_percent != null) return common.usageErrorResult(allocator, .list, "duplicate `--min` for `list`.", .{});
            i += 1;
            if (i >= args.len) return common.usageErrorResult(allocator, .list, "`--min` requires a percentage from 0 to 100.", .{});
            opts.min_percent = parseMinPercent(std.mem.sliceTo(args[i], 0)) catch
                return common.usageErrorResult(allocator, .list, "`--min` requires a percentage from 0 to 100.", .{});
            continue;
        }
        if (std.mem.eql(u8, arg, "--query")) {
            if (opts.query != null) return common.usageErrorResult(allocator, .list, "duplicate `--query` for `list`.", .{});
            i += 1;
            if (i >= args.len) return common.usageErrorResult(allocator, .list, "`--query` requires text.", .{});
            const value = std.mem.sliceTo(args[i], 0);
            if (value.len == 0) return common.usageErrorResult(allocator, .list, "`--query` requires text.", .{});
            opts.query = try allocator.dupe(u8, value);
            continue;
        }
        if (common.isHelpFlag(arg)) return common.usageErrorResult(allocator, .list, "`--help` must be used by itself for `list`.", .{});
        if (std.mem.startsWith(u8, arg, "-")) return common.usageErrorResult(allocator, .list, "unknown flag `{s}` for `list`.", .{arg});
        return common.usageErrorResult(allocator, .list, "unexpected argument `{s}` for `list`.", .{arg});
    }

    if (opts.available and opts.errors) {
        return common.usageErrorResult(allocator, .list, "`--available` cannot be combined with `--errors` for `list`.", .{});
    }
    query_returned = true;
    return .{ .command = .{ .list = opts } };
}

fn parseMinPercent(value: []const u8) !u8 {
    const parsed = std.fmt.parseUnsigned(u8, value, 10) catch return error.InvalidMinPercent;
    if (parsed > 100) return error.InvalidMinPercent;
    return parsed;
}
