const std = @import("std");
const wm = @import("window_manager.zig");
const l = @import("launcher.zig");

const usage =
    \\Usage: gwin <command> [options]
    \\
    \\Commands:
    \\  switch <win_id>                    Activate the window with the given window ID
    \\  switch --last                      Activate the last application focused window
    \\  switch --last-instance             Activate the last instance of the focused window
    \\  switch --least-recent              Activate the least recently focused window
    \\  switch --index <n>                 Activate window by index (0 = current, 1 = previous, ...)
    \\  list   windows                     List open windows in reverse order (index 0 being the current focused window). Format: `{wm_class} | {title}`
    \\  list   applications [--rofi]       List installed applications
    \\  raise  <desktop_id>                Raise window for <desktop_id> or launch it if not open (Example: `raise org.gnome.Calculator.desktop`)
    \\
    \\Options for switch without a specific ID:
    \\  --exclude <pattern>                Skip windows whose wm_class contains any
    \\                                     '|'-delimited token in <pattern>.
    \\                                     Example: --exclude 'ghostty|google-chrome'
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
    } else if (std.mem.eql(u8, args[1], "raise")) {
        runRaise(allocator, args[2..]);
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
            exclude_pattern = std.mem.trim(u8, args[i + 1], "\"");
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

        const win = window_list.lastApplicationFocused() orelse
            fatal("There are no open windows to switch to.\n", .{});
        manager.activate(win.id) catch
            fatal("Failed to activate window {d}.\n", .{win.id});
    } else if (std.mem.eql(u8, args[0], "--last-instance")) {
        const window_list = manager.list(allocator) catch fatal("Failed to list windows.\n", .{});
        defer window_list.deinit();

        const ws = window_list.windows();
        if (ws.len < 2) {
            fatal("There are no other windows to switch to.\n", .{});
        }
        const current_window = ws[ws.len - 1];

        var target_window: ?wm.Window = null;
        var j: usize = ws.len - 1;
        while (j > 0) {
            j -= 1;
            const w = ws[j];
            if (std.mem.eql(u8, w.wm_class, current_window.wm_class)) {
                target_window = w;
                break;
            }
        }

        if (target_window) |win| {
            manager.activate(win.id) catch
                fatal("Failed to activate window {d}.\n", .{win.id});
        } else {
            fatal("No other instance of the current application was found.\n", .{});
        }
    } else if (std.mem.eql(u8, args[0], "--least-recent")) {
        const window_list = if (exclude_pattern) |pattern|
            (manager.list(allocator) catch fatal("Failed to list windows.\n", .{})).filtered(pattern) catch
                fatal("Failed to apply exclude filter.\n", .{})
        else
            manager.list(allocator) catch fatal("Failed to list windows.\n", .{});
        defer window_list.deinit();

        const win = window_list.firstWindowFocused() orelse
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

    var rofi = false;
    if (args.len > 1 and std.mem.eql(u8, args[1], "--rofi")) {
        rofi = true;
    }

    if (std.mem.eql(u8, args[0], "windows")) {
        const manager = wm.WindowManager.init() catch
            fatal("Failed to connect to D-Bus session bus.\n", .{});
        defer manager.deinit();

        const window_list = manager.list(allocator) catch
            fatal("Failed to list windows.\n", .{});
        defer window_list.deinit();

        const ws = window_list.windows();
        if (ws.len == 0) {
            fatal("There are no other windows opened.\n", .{});
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

            if (rofi) {
                stdout.print("{d}\x00display\x1f{s} | {s}\x1fmeta\x1f{s}\n", .{ w.id, wm_class_str, w.title, w.title }) catch {};
            } else {
                stdout.print("{s} | {s}\n", .{ wm_class_str, w.title }) catch {};
            }
        }
        stdout.flush() catch {};
    } else if (std.mem.eql(u8, args[0], "applications") or std.mem.eql(u8, args[0], "application")) {
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

fn runRaise(allocator: std.mem.Allocator, args: []const [:0]const u8) void {
    if (args.len == 0) fatal("{s}", .{usage});

    const app_id = args[0];

    var base_name: []const u8 = app_id;
    if (std.mem.endsWith(u8, base_name, ".desktop")) {
        base_name = base_name[0 .. base_name.len - ".desktop".len];
    }

    var base_name_buf: [256]u8 = undefined;
    const base_name_lower = std.ascii.lowerString(&base_name_buf, base_name);

    const manager = wm.WindowManager.init() catch
        fatal("Failed to connect to D-Bus session bus.\n", .{});
    defer manager.deinit();

    const window_list = manager.list(allocator) catch
        fatal("Failed to list windows.\n", .{});
    defer window_list.deinit();

    const ws = window_list.windows();
    var found_window: ?wm.Window = null;

    for (ws) |w| {
        var wm_class_buf: [256]u8 = undefined;
        const wm_class_lower = std.ascii.lowerString(&wm_class_buf, w.wm_class);

        if (std.mem.indexOf(u8, wm_class_lower, base_name_lower) != null) {
            found_window = w;
            break;
        }
    }

    if (found_window) |w| {
        manager.activate(w.id) catch
            fatal("Failed to activate window {d}.\n", .{w.id});
    } else {
        l.launch(app_id) catch |err| {
            fatal("Failed to launch application '{s}': {any}\n", .{ app_id, err });
        };
    }
}
