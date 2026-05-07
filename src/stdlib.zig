/// Standard lib of the language
const std = @import("std");

const assert = std.debug.assert;

pub fn print(ascii: i32) void {
    assert(ascii < 128 and ascii >= 0);

    const c: u8 = @intCast(ascii);
    std.debug.print("{c}", .{c});
}
