const std = @import("std");

const expression_pkg = @import("expression.zig");

const Expr = expression_pkg.Expr;
const ExprTag = expression_pkg.ExprTag;
const BoolExpr = expression_pkg.BoolExpr;
const ArithExpr = expression_pkg.ArithExpr;
const IfExpr = expression_pkg.IfExpr;

const assert = std.debug.assert;
const panic = std.debug.panic;

const VarTag = enum {
    int,
    bool_,
};
const Var = union(VarTag) {
    const Self = @This();
    int: i32,
    bool_: bool,

    pub fn tag(self: Self) VarTag {
        return @as(VarTag, self);
    }
};
pub const Vars = std.StringHashMap(Var);

pub fn eval(expr: Expr, local_vars: Vars) Expr {
    switch (expr) {
        .bool_ => |bool_| {
            return eval_bool(bool_, local_vars);
        },
        .arith => |arith| {
            return eval_arith(arith, local_vars);
        },
        .if_ => |if_| {
            return eval_if(if_, local_vars);
        },
        .var_ => |var_| {
            return eval_var(var_, local_vars);
        },
        else => {},
    }
    unreachable;
}

fn eval_var(expr: []const u8, local_vars: Vars) Expr {
    const value = local_vars.get(expr) orelse panic("var {s} not in context", .{expr});
    assert(value.tag() == .bool_);
    return .{ .bool_ = .{ .constant = value.bool_ } };
}

fn eval_if(expr: IfExpr, local_vars: Vars) Expr {
    const cond = eval(expr.eval.*, local_vars);
    assert(cond.tag() == .bool_);
    assert(cond.bool_.tag() == .constant);
    std.debug.print("If eval result: {}\n", .{cond.bool_.constant});
    return if (cond.bool_.constant)
        eval(expr.then.*, local_vars)
    else
        eval(expr.else_.*, local_vars);
}

fn eval_arith(expr: ArithExpr, local_vars: Vars) Expr {
    switch (expr) {
        .constant => |constant| return .{ .arith = .{ .constant = constant } },
        .prod, .minus, .plus => |op| {
            const lhs = eval(op.lhs.*, local_vars);
            const rhs = eval(op.rhs.*, local_vars);

            assert(lhs.tag() == .arith);
            assert(rhs.tag() == .arith);
            assert(lhs.arith == .constant);
            assert(rhs.arith == .constant);
            return switch (expr) {
                .prod => .{ .arith = .{ .constant = lhs.arith.constant * rhs.arith.constant } },
                .plus => .{ .arith = .{ .constant = lhs.arith.constant + rhs.arith.constant } },
                .minus => .{ .arith = .{ .constant = lhs.arith.constant - rhs.arith.constant } },
                else => unreachable,
            };
        },
    }
}

fn eval_bool(expr: BoolExpr, local_vars: Vars) Expr {
    switch (expr) {
        .constant => |const_| return .{ .bool_ = .{
            .constant = const_,
        } },
        .eql => |eql_expr| {
            const lhs = eval(eql_expr.lhs.*, local_vars);
            const rhs = eval(eql_expr.rhs.*, local_vars);

            std.debug.print("lhs = {}\n================\n", .{lhs});
            assert(lhs.tag() == .bool_ or lhs.tag() == .arith);
            assert(rhs.tag() == .bool_ or rhs.tag() == .arith);
            assert(lhs.tag() == rhs.tag());

            return .{ .bool_ = .{ .constant = (lhs.arith.constant == rhs.arith.constant) } };
        },
        else => unreachable,
    }
}
