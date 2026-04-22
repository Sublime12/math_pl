const std = @import("std");

const expression_pkg = @import("expression.zig");

const Expr = expression_pkg.Expr;
const ExprTag = expression_pkg.ExprTag;
const BoolExpr = expression_pkg.BoolExpr;
const ArithExpr = expression_pkg.ArithExpr;
const IfExpr = expression_pkg.IfExpr;

const assert = std.debug.assert;
const panic = std.debug.panic;

pub fn eval(expr: Expr) Expr {
    // std.debug.print("EXPRP : {}\n", .{expr});
    switch (expr) {
        .bool_ => |bool_| {
            return eval_bool(bool_);
        },
        .arith => |arith| {
            return eval_arith(arith);
        },
        .if_ => |if_| {
            return eval_if(if_);
        },
        else => {},
    }
    unreachable;
}

fn eval_if(expr: IfExpr) Expr {
    const cond = eval(expr.eval.*);
    assert(cond.tag() == .bool_);
    assert(cond.bool_.tag() == .constant);
    std.debug.print("If eval result: {}\n", .{cond.bool_.constant});
    return if (cond.bool_.constant)
        eval(expr.then.*)
    else
        eval(expr.else_.*);
}

fn eval_arith(expr: ArithExpr) Expr {
    switch (expr) {
        .constant => |constant| return .{ .arith = .{ .constant = constant } },
        .var_ => panic("eval for var_ not yet implemented ", .{}),
        .prod, .minus, .plus => |op| {
            const lhs = eval(op.lhs.*);
            std.debug.print("eval left result: {}\n", .{lhs.arith.constant});
            const rhs = eval(op.rhs.*);

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

fn eval_bool(expr: BoolExpr) Expr {
    switch (expr) {
        .var_ => |_| panic("Need to pass variables as args of eval_bool", .{}),
        .constant => |const_| return .{ .bool_ = .{
            .constant = const_,
        } },
        .eql => |eql_expr| {
            const lhs = eval(eql_expr.lhs.*);
            const rhs = eval(eql_expr.rhs.*);

            std.debug.print("lhs = {}\n================\n", .{lhs});
            assert(lhs.tag() == .bool_ or lhs.tag() == .arith);
            assert(rhs.tag() == .bool_ or rhs.tag() == .arith);
            assert(lhs.tag() == rhs.tag());

            return .{ .bool_ = .{ .constant = (lhs.arith.constant == rhs.arith.constant) } };
        },
        else => unreachable,
    }
}
