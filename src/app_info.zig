const std = @import("std");
const c = @import("c");

pub const App = struct {
    id: []const u8,
    name: []const u8,
    icon: []const u8,
};

pub const AppList = struct {
    apps_buf: []App,
    arena: std.heap.ArenaAllocator,

    inline fn initInternal(base_allocator: std.mem.Allocator, comptime fetch_icons: bool) !AppList {
        var arena = std.heap.ArenaAllocator.init(base_allocator);
        errdefer arena.deinit();

        const alloc = arena.allocator();

        const gio_list = c.g_app_info_get_all() orelse return error.NoAppsFound;
        defer {
            var it: ?*c.GList = @ptrCast(gio_list);
            while (it) |node| : (it = @ptrCast(node.next)) {
                c.g_object_unref(node.data);
            }
            c.g_list_free(gio_list);
        }

        var buf = try std.ArrayList(App).initCapacity(alloc, c.g_list_length(gio_list));

        var current: ?*c.GList = @ptrCast(gio_list);
        while (current) |node| : (current = @ptrCast(node.next)) {
            const app_info: *c.GAppInfo = @ptrCast(node.data);

            const c_name = c.g_app_info_get_name(app_info);
            const c_id = c.g_app_info_get_id(app_info);

            if (c_name == null or c_id == null) continue;

            const name_str = try alloc.dupe(u8, std.mem.span(c_name));
            const id_str = try alloc.dupe(u8, std.mem.span(c_id));

            var icon_str: []const u8 = "";
            if (comptime fetch_icons) {
                if (c.g_app_info_get_icon(app_info)) |c_icon| {
                    if (c.g_icon_to_string(c_icon)) |c_icon_str| {
                        defer c.g_free(c_icon_str);
                        icon_str = try alloc.dupe(u8, std.mem.span(c_icon_str));
                    }
                }
            }

            try buf.appendBounded(.{ .name = name_str, .id = id_str, .icon = icon_str });
        }

        return .{
            .apps_buf = try buf.toOwnedSlice(alloc),
            .arena = arena,
        };
    }

    pub fn init(base_allocator: std.mem.Allocator) !AppList {
        return initInternal(base_allocator, false);
    }

    pub fn initWithIcons(base_allocator: std.mem.Allocator) !AppList {
        return initInternal(base_allocator, true);
    }

    pub fn deinit(self: AppList) void {
        self.arena.deinit();
    }
};

pub fn launch(app_id: []const u8) !void {
    const app_info = c.g_desktop_app_info_new(app_id.ptr);
    if (app_info == null) return error.AppNotFound;
    defer c.g_object_unref(app_info);

    var err: ?*c.GError = null;
    const success = c.g_app_info_launch(@ptrCast(app_info), null, null, &err);
    if (success == 0) {
        if (err) |e| c.g_error_free(e);
        return error.LaunchFailed;
    }
}

pub const AppMetadata = struct {
    name: []const u8,
    icon: []const u8,
};

pub fn getMetadataByWmClass(allocator: std.mem.Allocator, wm_class: []const u8) !AppMetadata {
    var buf: [256]u8 = undefined;

    const desktop_id = std.fmt.bufPrintZ(&buf, "{s}.desktop", .{wm_class}) catch return error.NameTooLong;
    if (getMetadata(allocator, desktop_id)) |meta| return meta else |_| {}

    const plain_id = std.fmt.bufPrintZ(&buf, "{s}", .{wm_class}) catch return error.NameTooLong;
    return getMetadata(allocator, plain_id);
}

fn getMetadata(allocator: std.mem.Allocator, app_id: [:0]const u8) !AppMetadata {
    const app_info = c.g_desktop_app_info_new(app_id.ptr);
    if (app_info == null) return error.AppNotFound;
    defer c.g_object_unref(app_info);

    var name: []const u8 = "";
    if (c.g_app_info_get_name(@ptrCast(app_info))) |c_name| {
        name = try allocator.dupe(u8, std.mem.span(c_name));
    }

    var icon: []const u8 = "";
    if (c.g_app_info_get_icon(@ptrCast(app_info))) |c_icon| {
        if (c.g_icon_to_string(c_icon)) |c_icon_str| {
            defer c.g_free(c_icon_str);
            icon = try allocator.dupe(u8, std.mem.span(c_icon_str));
        }
    }

    return .{ .name = name, .icon = icon };
}
