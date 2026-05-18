const std = @import("std");
const cli = @import("../cli/root.zig");
const registry = @import("../registry/root.zig");
const auth = @import("../auth/auth.zig");
const account_names = @import("account_names.zig");

const defaultAccountFetcher = account_names.defaultAccountFetcher;
const refreshAccountNamesAfterLogin = account_names.refreshAccountNamesAfterLogin;

pub fn syncLoggedInAccount(
    allocator: std.mem.Allocator,
    codex_home: []const u8,
    expected_email: ?[]const u8,
) !bool {
    const auth_path = try registry.activeAuthPath(allocator, codex_home);
    defer allocator.free(auth_path);

    const info = try auth.parseAuthInfo(allocator, auth_path);
    defer info.deinit(allocator);

    if (expected_email) |expected| {
        const actual_email = info.email orelse {
            std.log.err("codex login completed, but the current auth file does not contain an email.", .{});
            return error.MissingEmail;
        };
        const normalized_expected = try registry.normalizeEmailAlloc(allocator, expected);
        defer allocator.free(normalized_expected);
        if (!std.mem.eql(u8, actual_email, normalized_expected)) {
            std.log.err(
                "codex login completed for {s}, but this command was prepared for {s}.",
                .{ actual_email, normalized_expected },
            );
            return error.EmailMismatch;
        }
    }

    var reg = try registry.loadRegistry(allocator, codex_home);
    defer reg.deinit(allocator);

    var changed = try registry.syncActiveAccountFromAuth(allocator, codex_home, &reg);
    if (info.auth_mode == .chatgpt) {
        if (try refreshAccountNamesAfterLogin(allocator, &reg, &info, defaultAccountFetcher)) {
            changed = true;
        }
    }
    if (changed) try registry.saveRegistry(allocator, codex_home, &reg);
    return changed;
}

pub fn handleLogin(allocator: std.mem.Allocator, codex_home: []const u8, opts: cli.types.LoginOptions) !void {
    try cli.login.runCodexLogin(opts);
    _ = try syncLoggedInAccount(allocator, codex_home, null);
}
