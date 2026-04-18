const std = @import("std");
const wm = @import("window.zig");
const a = @import("app_info.zig");

pub const Format = enum {
    default,
    rofi,
};

pub fn printWindow(writer: anytype, format: Format, w: wm.Window, meta: ?a.AppMetadata) !void {
    var wm_class_buf: [256]u8 = undefined;
    const wm_class_lower = std.ascii.lowerString(&wm_class_buf, w.wm_class);
    const wm_class_str = if (std.mem.lastIndexOf(u8, wm_class_lower, ".")) |last_idx|
        wm_class_lower[last_idx + 1 ..]
    else
        wm_class_lower;

    switch (format) {
        .rofi => {
            const m = meta orelse a.AppMetadata{ .name = "", .icon = "" };
            const display_name = if (m.name.len > 0) m.name else wm_class_str;

            if (m.icon.len > 0) {
                try writer.print("{d}\x00display\x1f{s} > {s}\x1ficon\x1f{s}\x1fmeta\x1f{s}\n", .{ w.id, display_name, w.title, m.icon, w.title });
            } else {
                try writer.print("{d}\x00display\x1f{s} > {s}\x1fmeta\x1f{s}\n", .{ w.id, display_name, w.title, w.title });
            }
        },
        .default => {
            try writer.print("{s} | {s}\n", .{ wm_class_str, w.title });
        },
    }
}

pub fn printApplication(writer: anytype, format: Format, app: a.App) !void {
    switch (format) {
        .rofi => {
            if (app.icon.len > 0) {
                try writer.print("{s}\x00display\x1f{s}\x1ficon\x1f{s}\x1fmeta\x1f{s}\n", .{ app.id, app.name, app.icon, app.name });
            } else {
                try writer.print("{s}\x00display\x1f{s}\x1fmeta\x1f{s}\n", .{ app.id, app.name, app.name });
            }
        },
        .default => {
            try writer.print("{s} | {s}\n", .{ app.id, app.name });
        },
    }
}
