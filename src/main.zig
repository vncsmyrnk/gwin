const std = @import("std");
const wm = @import("window_manager.zig");

const usage =
    \\Usage: gwc <command> [options]
    \\
    \\Commands:
    \\  switch <id>                        Activate the window with the given ID
    \\  switch --last                      Activate the last focused window
    \\  switch --index <n>                 Activate window by index (0 = current, 1 = previous, ...)
    \\  list                               List open windows in reverse order (index 0 first)
    \\
    \\Options for switch --last / --index:
    \\  --exclude <pattern>                Skip windows whose wm_class contains any
    \\                                     '|'-delimited token in <pattern>.
    \\                                     Example: --exclude 'ghostty|google-chrome'
    \\
;

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch "fatal error\n";
    _ = std.fs.File.stderr().write(msg) catch {};
    std.process.exit(1);
}

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = std.process.argsAlloc(allocator) catch
        fatal("Failed to read arguments.\n", .{});
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) fatal("{s}", .{usage});

    if (std.mem.eql(u8, args[1], "switch")) {
        runSwitch(allocator, args[2..]);
    } else if (std.mem.eql(u8, args[1], "list")) {
        runList(allocator);
    } else {
        fatal("{s}", .{usage});
    }
}

fn runSwitch(allocator: std.mem.Allocator, args: []const [:0]const u8) void {
    if (args.len == 0) fatal("{s}", .{usage});

    // Pre-scan args for --exclude so it can appear in any position relative
    // to --last / --index.
    var exclude_pattern: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--exclude")) {
            if (i + 1 >= args.len) fatal("Missing value for --exclude.\n{s}", .{usage});
            exclude_pattern = args[i + 1];
            i += 1; // skip the value on the next iteration
        }
    }

    const manager = wm.WindowManager.init() catch
        fatal("Failed to connect to D-Bus session bus.\n", .{});
    defer manager.deinit();

    if (std.mem.eql(u8, args[0], "--last")) {
        const window_list = if (exclude_pattern) |pattern|
            (manager.list(allocator) catch fatal("Failed to list windows.\n", .{})).filtered(pattern) catch
                fatal("Failed to apply exclude filter.\n", .{})
        else
            manager.list(allocator) catch fatal("Failed to list windows.\n", .{});
        defer window_list.deinit();

        const win = window_list.lastFocused() orelse
            fatal("There are no open windows to switch to.\n", .{});
        manager.activate(win.id) catch
            fatal("Failed to activate window {d}.\n", .{win.id});
    } else if (std.mem.eql(u8, args[0], "--index")) {
        if (args.len < 2) fatal("Missing value for --index.\n{s}", .{usage});

        const index = std.fmt.parseInt(u32, args[1], 10) catch
            fatal("Invalid index: {s}\n{s}", .{ args[1], usage });

        const window_list = if (exclude_pattern) |pattern|
            (manager.list(allocator) catch fatal("Failed to list windows.\n", .{})).filtered(pattern) catch
                fatal("Failed to apply exclude filter.\n", .{})
        else
            manager.list(allocator) catch fatal("Failed to list windows.\n", .{});
        defer window_list.deinit();

        const win = window_list.getByIndex(index) orelse
            fatal("No window at index {d}.\n", .{index});
        manager.activate(win.id) catch
            fatal("Failed to activate window {d}.\n", .{win.id});
    } else if (!std.mem.eql(u8, args[0], "--exclude")) {
        // Plain numeric ID — --exclude is silently ignored (no list involved).
        const id = std.fmt.parseInt(u32, args[0], 10) catch
            fatal("Invalid window ID: {s}\n{s}", .{ args[0], usage });

        manager.activate(id) catch
            fatal("Failed to activate window {d}.\n", .{id});
    } else {
        fatal("{s}", .{usage});
    }
}

fn runList(allocator: std.mem.Allocator) void {
    const manager = wm.WindowManager.init() catch
        fatal("Failed to connect to D-Bus session bus.\n", .{});
    defer manager.deinit();

    const window_list = manager.list(allocator) catch
        fatal("Failed to list windows.\n", .{});
    defer window_list.deinit();

    const ws = window_list.windows();
    if (ws.len == 0) {
        fatal("There are no open windows.\n", .{});
    }

    const stdout = std.fs.File.stdout();
    var i: u32 = 0;
    while (i < ws.len) : (i += 1) {
        const w = ws[ws.len - 1 - i];
        var buf: [4096]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "{s}\n", .{w.title}) catch continue;
        _ = stdout.write(line) catch {};
    }
}
