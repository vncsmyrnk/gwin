const std = @import("std");
const window = @import("window.zig");
const app_info = @import("app_info.zig");
const format = @import("format.zig");

const mem = std.mem;
const fmt = std.fmt;
const heap = std.heap;
const meta = std.meta;
const ascii = std.ascii;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const File = std.Io.File;

const usage =
    \\Usage: gwin <command> [options]
    \\
    \\Commands:
    \\  switch --id <win_id>               Activate the window with the given window ID
    \\  switch --index <n>                 Activate window by index (0 = current, 1 = previous, ...)
    \\  switch --last-instance             Activate the last instance of the focused window
    \\  list   windows      [--rofi]       List open windows. Format: `{wm_class} | {title}`
    \\  list   applications [--rofi]       List installed applications
    \\  raise  <desktop_id>                Raise window for <desktop_id> or launch it if not open.
    \\                                     It also can resolve a substring for the actual desktop ID
    \\  close <win_id>                     Closes the window with the given window ID
    \\
    \\Options for switch without a specific ID:
    \\  --exclude <pattern>                Skip windows whose wm_class contains any
    \\                                     '|'-delimited token in <pattern>.
    \\                                     Example: --exclude 'ghostty|google-chrome'
    \\  --exclude-focused-application      Skip other instances from the current focused window,
    \\                                     supported on `--index` only
;

const Command = enum { switchCmd, listCmd, raiseCmd, closeCmd };

fn parseCommand(arg: []const u8) ?Command {
    if (mem.eql(u8, arg, "switch")) return .switchCmd;
    if (mem.eql(u8, arg, "list")) return .listCmd;
    if (mem.eql(u8, arg, "raise")) return .raiseCmd;
    if (mem.eql(u8, arg, "close")) return .closeCmd;

    return null;
}

fn fatal(comptime msg_fmt: []const u8, args: anytype) noreturn {
    std.debug.print(msg_fmt, args);
    std.process.exit(1);
}

pub fn main(init: std.process.Init) void {
    const allocator = init.gpa;

    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        fatal("Failed to read arguments.\n", .{});

    if (args.len < 2) fatal("{s}", .{usage});

    const manager = window.WindowManager.init() catch
        fatal("Failed to connect to D-Bus session bus.\n", .{});
    defer manager.deinit();

    const cmd = parseCommand(args[1]) orelse {
        fatal("{s}", .{usage});
    };

    switch (cmd) {
        .switchCmd => runSwitch(allocator, manager, args[2..]),
        .listCmd => runList(allocator, init.io, manager, args[2..]),
        .raiseCmd => runRaise(allocator, manager, args[2..]),
        .closeCmd => runClose(allocator, manager, args[2..]),
    }
}

fn runSwitch(allocator: Allocator, manager: window.WindowManager, args: []const [:0]const u8) void {
    if (args.len == 0) fatal("{s}", .{usage});

    var exclude_pattern: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (mem.eql(u8, args[i], "--exclude")) {
            if (i + 1 >= args.len) fatal("Missing value for --exclude.\n{s}", .{usage});
            exclude_pattern = mem.trim(u8, args[i + 1], "\"");
            i += 1;
        }
    }

    const Flag = enum {
        @"--last-instance",
        @"--id",
        @"--index",
    };

    const flag = meta.stringToEnum(Flag, args[0]) orelse fatal("{s}", .{usage});
    switch (flag) {
        .@"--last-instance" => runSwitchLastInstance(allocator, manager),
        .@"--id" => {
            if (args.len < 2) fatal("Missing value for --id.\n{s}", .{usage});

            const id = fmt.parseInt(u32, args[1], 10) catch
                fatal("Invalid window ID: {s}\n{s}", .{ args[0], usage });

            runSwitchByWindowID(manager, id);
        },
        .@"--index" => {
            if (args.len < 2) fatal("Missing value for --index.\n{s}", .{usage});

            const exclude_focused_application = if (args.len >= 3)
                mem.eql(u8, args[2], "--exclude-focused-application")
            else
                false;

            const index = fmt.parseInt(i8, args[1], 10) catch
                fatal("Invalid index: {s}\n{s}", .{ args[1], usage });

            runSwitchByIndex(allocator, manager, index, exclude_pattern, exclude_focused_application);
        },
    }
}

fn runList(allocator: Allocator, io: Io, manager: window.WindowManager, args: []const [:0]const u8) void {
    if (args.len == 0) fatal("{s}", .{usage});

    var rofi = false;
    if (args.len > 1 and mem.eql(u8, args[1], "--rofi")) {
        rofi = true;
    }

    const SubCommand = enum {
        windows,
        applications,
    };

    const subCmd = meta.stringToEnum(SubCommand, args[0]) orelse {
        fatal("{s}", .{usage});
    };

    switch (subCmd) {
        .windows => runListWindows(allocator, io, manager, rofi),
        .applications => runListApplications(allocator, io, rofi),
    }
}

fn runRaise(allocator: Allocator, manager: window.WindowManager, args: []const [:0]const u8) void {
    if (args.len == 0) fatal("{s}", .{usage});

    const app_id = args[0];

    var base_name: []const u8 = app_id;
    if (mem.endsWith(u8, base_name, ".desktop")) {
        base_name = base_name[0 .. base_name.len - ".desktop".len];
    }

    const window_list = manager.list(allocator) catch
        fatal("Failed to list windows.\n", .{});
    defer window_list.deinit();

    const ws = window_list.windows();
    var found_window: ?window.Window = null;

    var j: usize = ws.len;
    while (j > 0) {
        j -= 1;

        const w = ws[j];

        if (ascii.indexOfIgnoreCase(w.wm_class, base_name) != null) {
            found_window = w;
            break;
        }
    }

    if (found_window) |w| {
        manager.activate(w.id) catch
            fatal("Failed to activate window {d}.\n", .{w.id});
        return;
    }

    app_info.launch(app_id) catch |err| {
        if (err != error.AppNotFound) {
            fatal("Failed to launch application '{s}': {any}\n", .{ app_id, err });
        }

        const app_list = app_info.AppList.init(allocator) catch fatal("Failed to list applications.\n", .{});
        defer app_list.deinit();

        for (app_list.apps_buf) |app| {
            if (ascii.indexOfIgnoreCase(app.id, app_id) == null) continue;

            app_info.launch(app.id) catch |substringMatchLauchErr| {
                fatal("Failed to launch application '{s}': {any}\n", .{ app_id, substringMatchLauchErr });
            };
            return;
        }

        fatal("Failed to launch application '{s}': {any}\n", .{ app_id, err });
    };
}

fn runClose(_: Allocator, manager: window.WindowManager, args: []const [:0]const u8) void {
    if (args.len == 0) fatal("{s}", .{usage});

    const id = fmt.parseInt(u32, args[0], 10) catch
        fatal("Invalid window ID: {s}\n{s}", .{ args[0], usage });

    manager.close(id) catch
        fatal("Failed to activate window {d}.\n", .{id});
}

fn runSwitchByWindowID(manager: window.WindowManager, id: u32) void {
    manager.activate(id) catch
        fatal("Failed to activate window {d}.\n", .{id});
}

fn runSwitchLastInstance(allocator: Allocator, manager: window.WindowManager) void {
    const window_list = manager.list(allocator) catch fatal("Failed to list windows.\n", .{});
    defer window_list.deinit();

    const ws = window_list.windows();
    if (ws.len < 2) {
        fatal("There are no other windows to switch to.\n", .{});
    }
    const current_window = ws[ws.len - 1];

    var target_window: ?window.Window = null;
    var j: usize = ws.len - 1;
    while (j > 0) {
        j -= 1;
        const w = ws[j];
        if (mem.eql(u8, w.wm_class, current_window.wm_class)) {
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

fn runSwitchByIndex(allocator: Allocator, manager: window.WindowManager, index: i8, exclude_pattern: ?[]const u8, exclude_focused_application: bool) void {
    var window_list = manager.list(allocator) catch fatal("Failed to list windows.\n", .{});
    defer window_list.deinit();

    const pattern: []const u8 = exclude_pattern orelse "";
    window_list = (if (exclude_focused_application)
        window_list.filteredIgnoringFocusedApplication(pattern)
    else
        window_list.filtered(pattern)) catch fatal("Failed to filter windows.\n", .{});

    const win = window_list.getByIndex(index) orelse fatal("No window at index {d}.\n", .{index});
    manager.activate(win.id) catch
        fatal("Failed to activate window {d}.\n", .{win.id});
}

fn runListWindows(allocator: Allocator, io: Io, manager: window.WindowManager, rofi: bool) void {
    const window_list = manager.list(allocator) catch
        fatal("Failed to list windows.\n", .{});
    defer window_list.deinit();

    const ws = window_list.switchableWindows();
    if (ws.len == 0) {
        fatal("There are no other windows opened.\n", .{});
    }

    var stdout_buf: [4096]u8 = undefined;
    var stdout_wrapper = File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_wrapper.interface;

    var arena = heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temp_alloc = arena.allocator();

    var metadata_cache = std.StringHashMap(app_info.AppMetadata).init(temp_alloc);

    const out_format: format.Format = if (rofi) .rofi else .default;

    var i: u32 = 0;
    while (i < ws.len) : (i += 1) {
        const w = ws[ws.len - 1 - i];

        var metadata: ?app_info.AppMetadata = null;
        if (rofi) {
            metadata = metadata_cache.get(w.wm_class) orelse blk: {
                const fetched = app_info.getMetadataByWmClass(temp_alloc, w.wm_class) catch app_info.AppMetadata{ .name = "", .icon = "" };
                metadata_cache.put(w.wm_class, fetched) catch {};
                break :blk fetched;
            };
        }

        format.printWindow(stdout, out_format, w, metadata) catch {};
    }
    stdout.flush() catch fatal("failed to flush output\n", .{});
}

fn runListApplications(allocator: Allocator, io: Io, rofi: bool) void {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_wrapper = File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_wrapper.interface;

    const app_list = if (rofi)
        app_info.AppList.initWithIcons(allocator) catch fatal("Failed to list applications.\n", .{})
    else
        app_info.AppList.init(allocator) catch fatal("Failed to list applications.\n", .{});
    defer app_list.deinit();

    const out_format: format.Format = if (rofi) .rofi else .default;

    for (app_list.apps_buf) |app| {
        format.printApplication(stdout, out_format, app) catch {};
    }
    stdout.flush() catch {};
}
