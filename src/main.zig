const std = @import("std");
const wm = @import("window_manager.zig");
const l = @import("launcher.zig");

const usage =
    \\Usage: gwc <command> [options]
    \\
    \\Commands:
    \\  switch <id>                        Activate the window with the given ID
    \\  switch --last                      Activate the last focused window
    \\  switch --least-recent              Activate the least recently focused window
    \\  switch --index <n>                 Activate window by index (0 = current, 1 = previous, ...)
    \\  list   windows                     List open windows in reverse order (index 0 first). Format: `{wm_class} | {title}`
    \\  list   applications                List installed applications
    \\  list   applications --rofi         List installed applications in a formatted format for rofi
    \\
    \\Options for switch without a specific ID:
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
        runList(allocator, args[2..]);
    } else {
        fatal("{s}", .{usage});
    }
}

fn runSwitch(allocator: std.mem.Allocator, args: []const [:0]const u8) void {
    if (args.len == 0) fatal("{s}", .{usage});

    var exclude_pattern: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--exclude")) {
            if (i + 1 >= args.len) fatal("Missing value for --exclude.\n{s}", .{usage});
            exclude_pattern = args[i + 1];
            i += 1;
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
    } else if (std.mem.eql(u8, args[0], "--least-recent")) {
        const window_list = if (exclude_pattern) |pattern|
            (manager.list(allocator) catch fatal("Failed to list windows.\n", .{})).filtered(pattern) catch
                fatal("Failed to apply exclude filter.\n", .{})
        else
            manager.list(allocator) catch fatal("Failed to list windows.\n", .{});
        defer window_list.deinit();

        const win = window_list.firstFocused() orelse
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

fn runList(allocator: std.mem.Allocator, args: []const [:0]const u8) void {
    if (args.len == 0) fatal("{s}", .{usage});

    if (std.mem.eql(u8, args[0], "windows")) {
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

        var stdout_buf: [4096]u8 = undefined;
        var stdout_wrapper = std.fs.File.stdout().writer(&stdout_buf);
        const stdout = &stdout_wrapper.interface;

        var i: u32 = 0;
        while (i < ws.len) : (i += 1) {
            const w = ws[ws.len - 1 - i];

            var wm_class_buf: [256]u8 = undefined;
            const wm_class_lower = std.ascii.lowerString(&wm_class_buf, w.wm_class);
            const wm_class_str = if (std.mem.lastIndexOf(u8, wm_class_lower, ".")) |last_idx|
                wm_class_lower[last_idx + 1 ..]
            else
                wm_class_lower;
            stdout.print("{s} | {s}\n", .{ wm_class_str, w.title }) catch {};
        }
        stdout.flush() catch {};
    } else if (std.mem.eql(u8, args[0], "applications") or std.mem.eql(u8, args[0], "application")) {
        var rofi = false;
        if (args.len > 1 and std.mem.eql(u8, args[1], "--rofi")) {
            rofi = true;
        }

        var stdout_buf: [4096]u8 = undefined;
        var stdout_wrapper = std.fs.File.stdout().writer(&stdout_buf);
        const stdout = &stdout_wrapper.interface;

        const app_list = l.AppList.init(allocator) catch
            fatal("Failed to list applications.\n", .{});
        defer app_list.deinit();

        for (app_list.apps_buf) |app| {
            if (rofi) {
                stdout.print("{s}\x00display\x1f{s}\x1fmeta\x1f{s}\n", .{ app.id, app.name, app.name }) catch {};
            } else {
                stdout.print("{s} | {s}\n", .{ app.id, app.name }) catch {};
            }
        }
        stdout.flush() catch {};
    } else {
        fatal("{s}", .{usage});
    }
}
