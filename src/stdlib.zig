/// Standard lib of the language
const std = @import("std");

const expression_pkg = @import("expression.zig");

const Expr = expression_pkg.Expr;

const assert = std.debug.assert;

pub fn print(expr: Expr) void {
    assert(expr.tag() == .arith and expr.arith.tag() == .constant);
    print_ascii(expr.arith.constant);
}

pub fn print_ascii(ascii: i32) void {
    assert(ascii < 128 and ascii >= 0);

    const c: u8 = @intCast(ascii);
    std.debug.print("{c}", .{c});
}
