/// Standard lib of the language
const std = @import("std");

const expression_pkg = @import("expression.zig");
const eval_pkg = @import("eval.zig");

const Expr = expression_pkg.Expr;
const Vars = eval_pkg.Vars;

const assert = std.debug.assert;

pub fn print(vars: Vars) Expr {
    // assert(vars.tag() == .arith and vars.arith.tag() == .constant);
    assert(vars.count() == 1);
    assert(vars.contains("c"));
    const c = vars.get("c").?;
    assert(c.tag() == .int);

    print_ascii(c.int);
    return .{ .void_ = 0 };
}

pub fn print_int(vars: Vars) Expr {
    // assert(vars.tag() == .arith and vars.arith.tag() == .constant);
    assert(vars.count() == 1);
    assert(vars.contains("c"));
    const c = vars.get("c").?;

    assert(c.tag() == .int);
    std.debug.print("{}", .{c.int});
    return .{ .void_ = 0 };
}

pub fn print_ascii(ascii: i32) void {
    assert(ascii < 128 and ascii >= 0);

    const c: u8 = @intCast(ascii);
    std.debug.print("{c}", .{c});
}
