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
    CloseFailed,
    NoWindows,
    WindowNotFound,
    JsonParseFailed,
    FilterFailed,
};

/// Returns true if `wm_class` contains at least one of the `|`-delimited
/// tokens in `pattern`. Matching is case-sensitive substring search.
fn matchesExcludePattern(wm_class: []const u8, pattern: []const u8) bool {
    var it = std.mem.splitScalar(u8, pattern, '|');
    while (it.next()) |token| {
        if (token.len == 0) continue;
        if (std.mem.indexOf(u8, wm_class, token) != null) return true;
    }
    return false;
}

pub const WindowList = struct {
    parsed: std.json.Parsed([]Window),
    json_buf: []const u8,
    allocator: std.mem.Allocator,
    filtered_buf: ?[]const Window = null,

    pub fn windows(self: WindowList) []const Window {
        return if (self.filtered_buf) |buf| buf else self.parsed.value;
    }

    /// Get all the windows opened except for the current one
    pub fn switchableWindows(self: WindowList) []const Window {
        return self.parsed.value[0 .. self.parsed.value.len - 1];
    }

    pub fn lastApplicationFocused(self: WindowList) ?Window {
        const ws = self.windows();
        var i = ws.len - 1; // Ignores the current window
        while (i > 0) { // Excludes windows from the same application
            i -= 1;
            if (!std.mem.eql(u8, ws[i].wm_class, ws[ws.len - 1].wm_class)) {
                return ws[i]; // Excludes windows from the same application
            }
        }
        return null;
    }

    pub fn firstWindowFocused(self: WindowList) ?Window {
        const ws = self.windows();
        return if (ws.len > 0) ws[0] else null;
    }

    pub fn findById(self: WindowList, id: u32) ?Window {
        for (self.windows()) |w| {
            if (w.id == id) return w;
        }
        return null;
    }

    /// Get a window by reverse index (0 = current, 1 = previous, etc.).
    pub fn getByIndex(self: WindowList, index: u32) ?Window {
        const ws = self.windows();
        if (ws.len == 0) return null;
        const ri = ws.len - 1 - @min(index, ws.len - 1);
        if (index >= ws.len) return null;
        return ws[ri];
    }

    /// Return a new `WindowList` that excludes any window whose `wm_class`
    /// contains at least one of the `|`-delimited tokens in `exclude_pattern`.
    /// Ownership is transferred from `self` into the returned list; the caller
    /// must NOT call `deinit` on `self` afterwards — only on the returned value.
    pub fn filtered(self: WindowList, exclude_pattern: []const u8) Error!WindowList {
        const ws = self.parsed.value;
        var buf = std.ArrayList(Window).initCapacity(self.allocator, ws.len) catch return Error.FilterFailed;
        errdefer buf.deinit(self.allocator);

        for (ws, 0..) |w, i| {
            // The current window should never be excluded
            // as the last window fetch consider it is always present
            if (i == ws.len - 1 or !matchesExcludePattern(w.wm_class, exclude_pattern)) {
                buf.appendBounded(w) catch return Error.FilterFailed;
            }
        }

        return .{
            .parsed = self.parsed,
            .json_buf = self.json_buf,
            .allocator = self.allocator,
            .filtered_buf = buf.toOwnedSlice(self.allocator) catch return Error.FilterFailed,
        };
    }

    pub fn deinit(self: WindowList) void {
        if (self.filtered_buf) |buf| self.allocator.free(buf);
        self.parsed.deinit();
        self.allocator.free(self.json_buf);
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

        const parsed = std.json.parseFromSlice(
            []Window,
            allocator,
            json_slice,
            .{ .ignore_unknown_fields = true },
        ) catch return Error.JsonParseFailed;

        return .{ .parsed = parsed, .json_buf = json_slice, .allocator = allocator };
    }

    /// Activate (focus) a window by its ID.
    pub fn activate(self: WindowManager, id: u32) Error!void {
        self.conn.callU32(dest, path, iface, "Activate", id) catch
            return Error.ActivateFailed;
    }

    /// Closes a window by its ID.
    pub fn close(self: WindowManager, id: u32) Error!void {
        self.conn.callU32(dest, path, iface, "Close", id) catch
            return Error.CloseFailed;
    }
};
