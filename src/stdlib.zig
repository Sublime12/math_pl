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
    return .{ .void_ = {} };
}

pub fn print_int(vars: Vars) Expr {
    assert(vars.count() == 1);
    assert(vars.contains("c"));
    const c = vars.get("c").?;

    assert(c.tag() == .int);
    std.debug.print("{}", .{c.int});
    return .{ .void_ = {} };
}

pub fn print_str(vars: Vars) Expr {
    assert(vars.count() == 1);
    assert(vars.contains("str"));
    const str = vars.get("str").?;

    assert(str.tag() == .str);
    std.debug.print("{s}", .{str.str});
    return .{ .void_ = {} };
}

pub fn getc(vars: Vars) Expr {
    assert(vars.count() == 2);

    assert(vars.contains("str"));
    const str = vars.get("str").?;
    assert(str.tag() == .str);

    assert(vars.contains("i"));
    const i = vars.get("i").?;
    assert(i.tag() == .int);

    assert(i.int < str.str.len);
    return .{ .arith = .{ .constant = str.str[@intCast(i.int)] } };
}

pub fn print_ascii(ascii: i32) void {
    assert(ascii < 128 and ascii >= 0);

    const c: u8 = @intCast(ascii);
    std.debug.print("{c}", .{c});
}
