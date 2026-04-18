const std = @import("std");
const wm = @import("window.zig");
const a = @import("app_info.zig");

const usage =
    \\Usage: gwin <command> [options]
    \\
    \\Commands:
    \\  switch <win_id>                    Activate the window with the given window ID
    \\  switch --last                      Activate the last application focused window
    \\  switch --last-instance             Activate the last instance of the focused window
    \\  switch --least-recent              Activate the least recently focused window
    \\  switch --index <n>                 Activate window by index (0 = current, 1 = previous, ...)
    \\  list   windows      [--rofi]       List open windows. Format: `{wm_class} | {title}`
    \\  list   applications [--rofi]       List installed applications
    \\  raise  <desktop_id>                Raise window for <desktop_id> or launch it if not open (Example: `raise org.gnome.Calculator.desktop`)
    \\                                     It also can resolve a substring for the actual desktop ID (Example: `raise calculator`)
    \\  close <win_id>                     Closes the window with the given window ID
    \\
    \\Options for switch without a specific ID:
    \\  --exclude <pattern>                Skip windows whose wm_class contains any
    \\                                     '|'-delimited token in <pattern>.
    \\                                     Example: --exclude 'ghostty|google-chrome'
;

const Command = enum { switchCmd, listCmd, raiseCmd, closeCmd };

fn parseCommand(arg: []const u8) ?Command {
    if (std.mem.eql(u8, arg, "switch")) return .switchCmd;
    if (std.mem.eql(u8, arg, "list")) return .listCmd;
    if (std.mem.eql(u8, arg, "raise")) return .raiseCmd;
    if (std.mem.eql(u8, arg, "close")) return .closeCmd;

    return null;
}

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

    const manager = wm.WindowManager.init() catch
        fatal("Failed to connect to D-Bus session bus.\n", .{});
    defer manager.deinit();

    const cmd = parseCommand(args[1]) orelse {
        fatal("{s}", .{usage});
    };

    switch (cmd) {
        .switchCmd => runSwitch(allocator, manager, args[2..]),
        .listCmd => runList(allocator, manager, args[2..]),
        .raiseCmd => runRaise(allocator, manager, args[2..]),
        .closeCmd => runClose(allocator, manager, args[2..]),
    }
}

fn runSwitch(allocator: std.mem.Allocator, manager: wm.WindowManager, args: []const [:0]const u8) void {
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

    const Flag = enum {
        @"--last",
        @"--last-instance",
        @"--least-recent",
        @"--index",
    };

    const flag = std.meta.stringToEnum(Flag, args[0]) orelse {
        const id = std.fmt.parseInt(u32, args[0], 10) catch
            fatal("Invalid window ID: {s}\n{s}", .{ args[0], usage });

        return runSwitchByWindowID(manager, id);
    };

    switch (flag) {
        .@"--last" => runSwitchLast(allocator, manager, exclude_pattern),
        .@"--last-instance" => runSwitchLastInstance(allocator, manager),
        .@"--least-recent" => runSwitchLeastRecent(allocator, manager, exclude_pattern),
        .@"--index" => {
            if (args.len < 2) fatal("Missing value for --index.\n{s}", .{usage});

            const index = std.fmt.parseInt(u32, args[1], 10) catch
                fatal("Invalid index: {s}\n{s}", .{ args[1], usage });

            runSwitchByIndex(allocator, manager, index, exclude_pattern);
        },
    }
}

fn runList(allocator: std.mem.Allocator, manager: wm.WindowManager, args: []const [:0]const u8) void {
    if (args.len == 0) fatal("{s}", .{usage});

    var rofi = false;
    if (args.len > 1 and std.mem.eql(u8, args[1], "--rofi")) {
        rofi = true;
    }

    const SubCommand = enum {
        windows,
        applications,
    };

    const subCmd = std.meta.stringToEnum(SubCommand, args[0]) orelse {
        fatal("{s}", .{usage});
    };

    switch (subCmd) {
        .windows => runListWindows(allocator, manager, rofi),
        .applications => runListApplications(allocator, rofi),
    }
}

fn runRaise(allocator: std.mem.Allocator, manager: wm.WindowManager, args: []const [:0]const u8) void {
    if (args.len == 0) fatal("{s}", .{usage});

    const app_id = args[0];

    var base_name: []const u8 = app_id;
    if (std.mem.endsWith(u8, base_name, ".desktop")) {
        base_name = base_name[0 .. base_name.len - ".desktop".len];
    }

    const window_list = manager.list(allocator) catch
        fatal("Failed to list windows.\n", .{});
    defer window_list.deinit();

    const ws = window_list.windows();
    var found_window: ?wm.Window = null;

    var j: usize = ws.len;
    while (j > 0) {
        j -= 1;

        const w = ws[j];

        if (std.ascii.indexOfIgnoreCase(w.wm_class, base_name) != null) {
            found_window = w;
            if (w.focus) {
                continue;
            }
            break;
        }
    }

    if (found_window) |w| {
        manager.activate(w.id) catch
            fatal("Failed to activate window {d}.\n", .{w.id});
        return;
    }

    a.launch(app_id) catch |err| {
        if (err != error.AppNotFound) {
            fatal("Failed to launch application '{s}': {any}\n", .{ app_id, err });
        }

        const app_list = a.AppList.init(allocator) catch fatal("Failed to list applications.\n", .{});
        defer app_list.deinit();

        for (app_list.apps_buf) |app| {
            if (std.ascii.indexOfIgnoreCase(app.id, app_id) == null) continue;

            a.launch(app.id) catch |substringMatchLauchErr| {
                fatal("Failed to launch application '{s}': {any}\n", .{ app_id, substringMatchLauchErr });
            };
            return;
        }

        fatal("Failed to launch application '{s}': {any}\n", .{ app_id, err });
    };
}

fn runClose(_: std.mem.Allocator, manager: wm.WindowManager, args: []const [:0]const u8) void {
    if (args.len == 0) fatal("{s}", .{usage});

    const id = std.fmt.parseInt(u32, args[0], 10) catch
        fatal("Invalid window ID: {s}\n{s}", .{ args[0], usage });

    manager.close(id) catch
        fatal("Failed to activate window {d}.\n", .{id});
}

fn runSwitchByWindowID(manager: wm.WindowManager, id: u32) void {
    manager.activate(id) catch
        fatal("Failed to activate window {d}.\n", .{id});
}

fn runSwitchLast(allocator: std.mem.Allocator, manager: wm.WindowManager, exclude_pattern: ?[]const u8) void {
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
}

fn runSwitchLastInstance(allocator: std.mem.Allocator, manager: wm.WindowManager) void {
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
}

fn runSwitchLeastRecent(allocator: std.mem.Allocator, manager: wm.WindowManager, exclude_pattern: ?[]const u8) void {
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
}

fn runSwitchByIndex(allocator: std.mem.Allocator, manager: wm.WindowManager, index: u32, exclude_pattern: ?[]const u8) void {
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
}

fn runListWindows(allocator: std.mem.Allocator, manager: wm.WindowManager, rofi: bool) void {
    const window_list = manager.list(allocator) catch
        fatal("Failed to list windows.\n", .{});
    defer window_list.deinit();

    const ws = window_list.switchableWindows();
    if (ws.len == 0) {
        fatal("There are no other windows opened.\n", .{});
    }

    var stdout_buf: [4096]u8 = undefined;
    var stdout_wrapper = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_wrapper.interface;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp_alloc = arena.allocator();

    var metadata_cache = std.StringHashMap(a.AppMetadata).init(temp_alloc);

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
            const meta = metadata_cache.get(w.wm_class) orelse blk: {
                const fetched = a.getMetadataByWmClass(temp_alloc, w.wm_class) catch a.AppMetadata{ .name = "", .icon = "" };
                metadata_cache.put(w.wm_class, fetched) catch {};
                break :blk fetched;
            };

            const display_name = if (meta.name.len > 0) meta.name else wm_class_str;

            if (meta.icon.len > 0) {
                stdout.print("{d}\x00display\x1f{s} > {s}\x1ficon\x1f{s}\x1fmeta\x1f{s}\n", .{ w.id, display_name, w.title, meta.icon, w.title }) catch {};
            } else {
                stdout.print("{d}\x00display\x1f{s} > {s}\x1fmeta\x1f{s}\n", .{ w.id, display_name, w.title, w.title }) catch {};
            }
        } else {
            stdout.print("{s} | {s}\n", .{ wm_class_str, w.title }) catch {};
        }
    }
    stdout.flush() catch fatal("failed to flush output\n", .{});
}

fn runListApplications(allocator: std.mem.Allocator, rofi: bool) void {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_wrapper = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_wrapper.interface;

    const app_list = if (rofi)
        a.AppList.initWithIcons(allocator) catch fatal("Failed to list applications.\n", .{})
    else
        a.AppList.init(allocator) catch fatal("Failed to list applications.\n", .{});
    defer app_list.deinit();

    for (app_list.apps_buf) |app| {
        if (rofi) {
            if (app.icon.len > 0) {
                stdout.print("{s}\x00display\x1f{s}\x1ficon\x1f{s}\x1fmeta\x1f{s}\n", .{ app.id, app.name, app.icon, app.name }) catch {};
            } else {
                stdout.print("{s}\x00display\x1f{s}\x1fmeta\x1f{s}\n", .{ app.id, app.name, app.name }) catch {};
            }
        } else {
            stdout.print("{s} | {s}\n", .{ app.id, app.name }) catch {};
        }
    }
    stdout.flush() catch {};
}
