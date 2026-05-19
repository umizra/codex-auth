const std = @import("std");
const registry = @import("registry/root.zig");

pub const available_threshold_percent: i64 = 10;

pub const Options = struct {
    nonzero: bool = false,
    available: bool = false,
    min_percent: ?u8 = null,
    errors: bool = false,
    query: ?[]const u8 = null,

    pub fn isEmpty(self: Options) bool {
        return !self.nonzero and !self.available and self.min_percent == null and !self.errors and self.query == null;
    }
};

pub const AccountView = struct {
    account: *const registry.AccountRecord,
    usage_override: ?[]const u8 = null,
    now: i64,
};

pub fn matches(view: AccountView, opts: Options) bool {
    if (opts.query) |query| {
        if (!matchesQuery(view.account, query)) return false;
    }

    const error_like = isErrorLike(view);
    const score = registry.usageScoreAt(view.account.last_usage, view.now);

    if (opts.errors and !error_like) return false;
    if (opts.nonzero and (score == null or score.? <= 0)) return false;
    if (opts.available and (error_like or score == null or score.? <= available_threshold_percent)) return false;
    if (opts.min_percent) |min_percent| {
        if (score == null or score.? < @as(i64, min_percent)) return false;
    }

    return true;
}

pub fn filterAccountIndices(
    allocator: std.mem.Allocator,
    reg: *const registry.Registry,
    usage_overrides: ?[]const ?[]const u8,
    opts: Options,
    now: i64,
) ![]usize {
    var indices = std.ArrayList(usize).empty;
    errdefer indices.deinit(allocator);

    for (reg.accounts.items, 0..) |*account, idx| {
        if (matches(.{
            .account = account,
            .usage_override = usageOverrideForAccount(usage_overrides, idx),
            .now = now,
        }, opts)) {
            try indices.append(allocator, idx);
        }
    }

    return indices.toOwnedSlice(allocator);
}

pub fn summaryAlloc(allocator: std.mem.Allocator, opts: Options) ![]u8 {
    if (opts.isEmpty()) return allocator.dupe(u8, "");
    var parts = std.ArrayList([]const u8).empty;
    defer parts.deinit(allocator);

    if (opts.nonzero) try parts.append(allocator, "nonzero");
    if (opts.available) try parts.append(allocator, "available");
    if (opts.errors) try parts.append(allocator, "errors");
    var min_buf: [32]u8 = undefined;
    var min_text: []const u8 = "";
    if (opts.min_percent) |min_percent| {
        min_text = try std.fmt.bufPrint(&min_buf, "min >= {d}", .{min_percent});
        try parts.append(allocator, min_text);
    }
    var query_text: []const u8 = "";
    if (opts.query) |query| {
        query_text = try std.fmt.allocPrint(allocator, "query: {s}", .{query});
        try parts.append(allocator, query_text);
    }
    defer if (opts.query != null) allocator.free(query_text);

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "Filter: ");
    for (parts.items, 0..) |part, idx| {
        if (idx != 0) try out.appendSlice(allocator, " | ");
        try out.appendSlice(allocator, part);
    }
    return out.toOwnedSlice(allocator);
}

fn usageOverrideForAccount(usage_overrides: ?[]const ?[]const u8, account_idx: usize) ?[]const u8 {
    const overrides = usage_overrides orelse return null;
    if (account_idx >= overrides.len) return null;
    return overrides[account_idx];
}

fn isErrorLike(view: AccountView) bool {
    if (view.usage_override != null) return true;
    return view.account.last_usage == null;
}

fn matchesQuery(account: *const registry.AccountRecord, query: []const u8) bool {
    if (query.len == 0) return true;
    return containsIgnoreCase(account.email, query) or
        containsIgnoreCase(account.alias, query) or
        (account.account_name != null and containsIgnoreCase(account.account_name.?, query)) or
        containsIgnoreCase(account.account_key, query);
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;

    var start: usize = 0;
    while (start + needle.len <= haystack.len) : (start += 1) {
        var matched = true;
        for (needle, 0..) |needle_ch, offset| {
            if (std.ascii.toLower(haystack[start + offset]) != std.ascii.toLower(needle_ch)) {
                matched = false;
                break;
            }
        }
        if (matched) return true;
    }
    return false;
}
