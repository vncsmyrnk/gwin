const std = @import("std");
const c = @cImport({
    @cInclude("gio/gio.h");
});

pub const Error = error{
    ConnectionFailed,
    CallFailed,
};

/// Opaque handle to a DBus session bus connection.
pub const Connection = struct {
    handle: *c.GDBusConnection,

    /// Connect to the session bus. Caller must call `deinit` when done.
    pub fn init() Error!Connection {
        var err: ?*c.GError = null;
        const conn = c.g_bus_get_sync(c.G_BUS_TYPE_SESSION, null, &err);
        if (conn) |handle| {
            return .{ .handle = handle };
        }
        defer c.g_error_free(err);
        return Error.ConnectionFailed;
    }

    pub fn deinit(self: Connection) void {
        c.g_object_unref(self.handle);
    }

    /// Call a DBus method that takes no parameters and returns a string.
    /// Caller owns the returned slice and must free it with `allocator.free()`.
    pub fn callNoArgsReturnString(self: Connection, allocator: std.mem.Allocator, comptime dest: [:0]const u8, comptime path: [:0]const u8, comptime iface: [:0]const u8, comptime method: [:0]const u8) (std.mem.Allocator.Error || Error)![]const u8 {
        var err: ?*c.GError = null;
        const result = c.g_dbus_connection_call_sync(
            self.handle,
            dest,
            path,
            iface,
            method,
            null,
            null,
            c.G_DBUS_CALL_FLAGS_NONE,
            -1,
            null,
            &err,
        );
        if (result == null) {
            defer c.g_error_free(err);
            return Error.CallFailed;
        }
        defer c.g_variant_unref(result);

        var json_output: [*c]const u8 = undefined;
        c.g_variant_get(result, "(&s)", &json_output);
        const span = std.mem.span(json_output);
        return allocator.dupe(u8, span);
    }

    /// Call a DBus method that takes a single `u32` parameter and returns nothing meaningful.
    pub fn callU32(self: Connection, comptime dest: [:0]const u8, comptime path: [:0]const u8, comptime iface: [:0]const u8, comptime method: [:0]const u8, arg: u32) Error!void {
        var err: ?*c.GError = null;
        const params = c.g_variant_new("(u)", arg);
        const result = c.g_dbus_connection_call_sync(
            self.handle,
            dest,
            path,
            iface,
            method,
            params,
            null,
            c.G_DBUS_CALL_FLAGS_NONE,
            -1,
            null,
            &err,
        );
        if (result == null) {
            defer c.g_error_free(err);
            return Error.CallFailed;
        }
        c.g_variant_unref(result);
    }
};
