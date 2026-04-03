const std = @import("std");

const c = @cImport({
    @cInclude("gio/gio.h");
    @cInclude("gio/gdesktopappinfo.h");
});

pub const App = struct {
    id: []const u8,
    name: []const u8,
};

pub const AppList = struct {
    apps_buf: []App,
    arena: std.heap.ArenaAllocator,

    pub fn init(base_allocator: std.mem.Allocator) !AppList {
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

            try buf.appendBounded(.{ .name = name_str, .id = id_str });
        }

        return .{
            .apps_buf = try buf.toOwnedSlice(alloc),
            .arena = arena,
        };
    }

    pub fn deinit(self: AppList) void {
        self.arena.deinit();
    }
};
