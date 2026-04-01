const std = @import("std");
const wm = @import("window_manager.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const manager = wm.WindowManager.init() catch {
        std.debug.print("Failed to connect to D-Bus session bus.\n", .{});
        return error.ConnectionFailed;
    };
    defer manager.deinit();

    const window_list = manager.list(allocator) catch {
        std.debug.print("Failed to list windows.\n", .{});
        return error.ListFailed;
    };
    defer window_list.deinit();

    if (window_list.lastFocused()) |win| {
        std.debug.print("{d}\n", .{win.id});
        manager.activate(win.id) catch {
            std.debug.print("Failed to activate window {d}.\n", .{win.id});
            return error.ActivateFailed;
        };
    } else {
        std.debug.print("There are no open windows.\n", .{});
    }
}
