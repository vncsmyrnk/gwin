const std = @import("std");
const dbus = @import("dbus.zig");

const dest = "org.gnome.Shell";
const path = "/org/gnome/Shell/Extensions/Windows";
const iface = "org.gnome.Shell.Extensions.Windows";

pub const Window = struct {
    in_current_workspace: bool,
    wm_class: []const u8,
    wm_class_instance: []const u8,
    title: []const u8,
    pid: i32,
    id: u32,
    frame_type: i32,
    window_type: i32,
    focus: bool,
};

pub const Error = error{
    ListFailed,
    ActivateFailed,
    NoWindows,
    WindowNotFound,
    JsonParseFailed,
};

pub const WindowList = struct {
    parsed: std.json.Parsed([]Window),

    pub fn windows(self: WindowList) []Window {
        return self.parsed.value;
    }

    pub fn lastFocused(self: WindowList) ?Window {
        const ws = self.windows();
        return if (ws.len > 1) ws[ws.len - 2] else null;
    }

    pub fn firstFocused(self: WindowList) ?Window {
        const ws = self.windows();
        return if (ws.len > 0) ws[0] else null;
    }

    pub fn findById(self: WindowList, id: u32) ?Window {
        for (self.windows()) |w| {
            if (w.id == id) return w;
        }
        return null;
    }

    pub fn deinit(self: WindowList) void {
        self.parsed.deinit();
    }
};

pub const WindowManager = struct {
    conn: dbus.Connection,

    pub fn init() !WindowManager {
        const conn = dbus.Connection.init() catch return error.ListFailed;
        return .{ .conn = conn };
    }

    pub fn deinit(self: WindowManager) void {
        self.conn.deinit();
    }

    /// Fetch all windows from the window-calls extension.
    pub fn list(self: WindowManager, allocator: std.mem.Allocator) Error!WindowList {
        const json_slice = self.conn.callNoArgsReturnString(allocator, dest, path, iface, "List") catch
            return Error.ListFailed;
        defer allocator.free(json_slice);

        const parsed = std.json.parseFromSlice(
            []Window,
            allocator,
            json_slice,
            .{ .ignore_unknown_fields = true },
        ) catch return Error.JsonParseFailed;

        return .{ .parsed = parsed };
    }

    /// Activate (focus) a window by its ID.
    pub fn activate(self: WindowManager, id: u32) Error!void {
        self.conn.callU32(dest, path, iface, "Activate", id) catch
            return Error.ActivateFailed;
    }
};
