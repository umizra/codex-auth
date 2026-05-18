const std = @import("std");
const app_runtime = @import("../core/runtime.zig");
const cli = @import("../cli/root.zig");
const registry = @import("../registry/root.zig");
const login_workflow = @import("login.zig");

const max_accounts_file_bytes = 10 * 1024 * 1024;

const BatchLoginAccount = struct {
    line_number: usize,
    primary_email: []u8,
};

fn freeAccounts(allocator: std.mem.Allocator, accounts: []BatchLoginAccount) void {
    for (accounts) |account| allocator.free(account.primary_email);
}

fn parseAccountLine(allocator: std.mem.Allocator, raw_line: []const u8, line_number: usize) !?BatchLoginAccount {
    const trimmed = std.mem.trim(u8, raw_line, &std.ascii.whitespace);
    if (trimmed.len == 0 or trimmed[0] == '#') return null;

    var parts = std.mem.splitScalar(u8, trimmed, ':');
    const primary_email = std.mem.trim(u8, parts.next() orelse return error.InvalidBatchLoginInput, &std.ascii.whitespace);
    const service_password = std.mem.trim(u8, parts.next() orelse return error.InvalidBatchLoginInput, &std.ascii.whitespace);
    const email_password = std.mem.trim(u8, parts.next() orelse return error.InvalidBatchLoginInput, &std.ascii.whitespace);
    const fallback_email = std.mem.trim(u8, parts.next() orelse return error.InvalidBatchLoginInput, &std.ascii.whitespace);
    const fallback_email_password = std.mem.trim(u8, parts.next() orelse return error.InvalidBatchLoginInput, &std.ascii.whitespace);
    if (parts.next() != null) return error.InvalidBatchLoginInput;
    if (primary_email.len == 0 or service_password.len == 0 or email_password.len == 0 or fallback_email.len == 0 or fallback_email_password.len == 0) {
        return error.InvalidBatchLoginInput;
    }

    return .{
        .line_number = line_number,
        .primary_email = try allocator.dupe(u8, primary_email),
    };
}

fn loadAccounts(allocator: std.mem.Allocator, accounts_path: []const u8) !std.ArrayList(BatchLoginAccount) {
    const file = try std.Io.Dir.cwd().openFile(app_runtime.io(), accounts_path, .{});
    defer file.close(app_runtime.io());

    const data = try registry.readFileAlloc(file, allocator, max_accounts_file_bytes);
    defer allocator.free(data);

    var accounts = std.ArrayList(BatchLoginAccount).empty;
    errdefer freeAccounts(allocator, accounts.items);

    var line_number: usize = 0;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw_line| : (line_number += 1) {
        if (try parseAccountLine(allocator, raw_line, line_number + 1)) |account| {
            try accounts.append(allocator, account);
        }
    }

    return accounts;
}

pub fn handleBatchLogin(allocator: std.mem.Allocator, codex_home: []const u8, opts: cli.types.BatchLoginOptions) !void {
    var accounts = try loadAccounts(allocator, opts.accounts_path);
    defer {
        freeAccounts(allocator, accounts.items);
        accounts.deinit(allocator);
    }

    if (accounts.items.len == 0) {
        std.log.err("batch-login: no usable account lines were found in {s}.", .{opts.accounts_path});
        return error.InvalidBatchLoginInput;
    }

    const selected_accounts = if (opts.line_number) |line_number| blk: {
        for (accounts.items, 0..) |account, idx| {
            if (account.line_number == line_number) break :blk accounts.items[idx .. idx + 1];
        }
        std.log.err("batch-login: line {d} was not found in {s}.", .{ line_number, opts.accounts_path });
        return error.AccountNotFound;
    } else if (opts.from_line_number) |from_line_number| blk: {
        for (accounts.items, 0..) |account, idx| {
            if (account.line_number >= from_line_number) break :blk accounts.items[idx..];
        }
        std.log.err("batch-login: no usable account lines were found at or after line {d} in {s}.", .{ from_line_number, opts.accounts_path });
        return error.AccountNotFound;
    } else accounts.items;

    var failure_count: usize = 0;
    for (selected_accounts) |account| {
        std.log.info("batch-login: starting fresh codex login session for {s} from line {d}.", .{ account.primary_email, account.line_number });
        if (cli.login.runCodexLogin(.{ .device_auth = opts.device_auth })) |_| {} else |err| {
            failure_count += 1;
            std.log.err("batch-login: codex login failed for {s} on line {d}: {s}.", .{ account.primary_email, account.line_number, @errorName(err) });
            continue;
        }
        if (login_workflow.syncLoggedInAccount(allocator, codex_home, account.primary_email)) |_| {
            std.log.info("batch-login: completed codex login for {s}.", .{account.primary_email});
        } else |err| {
            failure_count += 1;
            std.log.err("batch-login: sync failed for {s} on line {d}: {s}.", .{ account.primary_email, account.line_number, @errorName(err) });
        }
    }

    if (failure_count > 0) {
        std.log.err("batch-login: finished with {d} failure(s).", .{failure_count});
        return error.BatchLoginFailed;
    }
}
