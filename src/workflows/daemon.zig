const std = @import("std");
const app_runtime = @import("../core/runtime.zig");
const registry = @import("../registry/root.zig");
const usage_refresh = @import("usage.zig");

const auto_switch_threshold_percent: i64 = 10;
const max_candidate_usage_age_seconds: i64 = 30 * 60;

fn usageScoreForAccount(rec: *const registry.AccountRecord, now: i64) i64 {
    return registry.usageScoreAt(rec.last_usage, now) orelse -1;
}

fn shouldSwitchActive(reg: *registry.Registry, now: i64) bool {
    const active_key = reg.active_account_key orelse return reg.accounts.items.len > 0;
    const active_idx = registry.findAccountIndexByAccountKey(reg, active_key) orelse return reg.accounts.items.len > 0;
    const score = registry.usageScoreAt(reg.accounts.items[active_idx].last_usage, now) orelse return false;
    return score <= auto_switch_threshold_percent;
}

fn bestSwitchTargetIndex(reg: *registry.Registry, now: i64) ?usize {
    const active_key = reg.active_account_key;
    var best_idx: ?usize = null;
    var best_score: i64 = 0;
    var best_seen: i64 = -1;

    for (reg.accounts.items, 0..) |rec, idx| {
        if (active_key) |key| {
            if (std.mem.eql(u8, rec.account_key, key)) continue;
        }
        const seen = rec.last_usage_at orelse continue;
        if (now - seen > max_candidate_usage_age_seconds) continue;
        const score = usageScoreForAccount(&rec, now);
        if (score <= auto_switch_threshold_percent) continue;
        if (best_idx == null or score > best_score or (score == best_score and seen > best_seen)) {
            best_idx = idx;
            best_score = score;
            best_seen = seen;
        }
    }

    return best_idx;
}

fn runOnce(allocator: std.mem.Allocator, codex_home: []const u8) !void {
    var reg = try registry.loadRegistry(allocator, codex_home);
    defer reg.deinit(allocator);

    var active_usage_state = try usage_refresh.refreshForegroundUsageForDisplayWithBatchFetcherUsingApiEnabledAndActiveOnly(
        allocator,
        codex_home,
        &reg,
        reg.api.usage,
        true,
    );
    defer active_usage_state.deinit(allocator);

    const now = std.Io.Timestamp.now(app_runtime.io(), .real).toSeconds();
    if (!shouldSwitchActive(&reg, now)) return;

    var candidate_usage_state = try usage_refresh.refreshForegroundUsageForDisplayWithBatchFetcherUsingApiEnabledAndActiveOnly(
        allocator,
        codex_home,
        &reg,
        reg.api.usage,
        false,
    );
    defer candidate_usage_state.deinit(allocator);

    const target_idx = bestSwitchTargetIndex(&reg, now) orelse return;
    const target_key = try allocator.dupe(u8, reg.accounts.items[target_idx].account_key);
    defer allocator.free(target_key);
    const target_email = try allocator.dupe(u8, reg.accounts.items[target_idx].email);
    defer allocator.free(target_email);

    try registry.activateAccountByKey(allocator, codex_home, &reg, target_key);
    try registry.saveRegistry(allocator, codex_home, &reg);
    std.log.info("daemon: switched active account to {s}.", .{target_email});
}

pub fn handleDaemon(allocator: std.mem.Allocator, codex_home: []const u8, opts: anytype) !void {
    while (true) {
        runOnce(allocator, codex_home) catch |err| {
            std.log.err("daemon: auto-switch check failed: {s}.", .{@errorName(err)});
        };
        if (!opts.watch) return;

        var reg = registry.loadRegistry(allocator, codex_home) catch {
            std.Io.sleep(app_runtime.io(), .fromSeconds(60), .awake) catch {};
            continue;
        };
        const interval = reg.live.interval_seconds;
        reg.deinit(allocator);
        std.Io.sleep(app_runtime.io(), .fromSeconds(interval), .awake) catch {};
    }
}
