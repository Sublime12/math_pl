const std = @import("std");

const expression_pkg = @import("expression.zig");

const Expr = expression_pkg.Expr;
const ExprTag = expression_pkg.ExprTag;
const BoolExpr = expression_pkg.BoolExpr;
const ArithExpr = expression_pkg.ArithExpr;

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
        else => {},
    }
    unreachable;
}

pub fn eval_arith(expr: ArithExpr) Expr {
    switch (expr) {
        .constant => |constant| return .{ .arith = .{ .constant = constant }},
        .prod => |prod| {
            const lhs = eval(prod.lhs.*);
            const rhs = eval(prod.rhs.*);
            assert(lhs.tag() == .arith);
            assert(rhs.tag() == .arith);
            return .{ .arith = .{ .constant = lhs.arith.constant * rhs.arith.constant }};
        },
        else => {},
    }
    panic("arith not fully implemented", .{});
}

pub fn eval_bool(expr: BoolExpr) Expr {
    switch (expr) {
        .var_ => |_| panic("Need to pass variables as args of eval_bool", .{}),
        .constant => |const_| return .{ .bool_ = .{ .constant = const_, }},
        .eql => |eql_expr|{
            const lhs = eval(eql_expr.lhs.*);
            const rhs = eval(eql_expr.rhs.*);

            std.debug.print("lhs = {}\n================\n", .{lhs});
            assert(lhs.tag() == .bool_ or lhs.tag() == .arith); 
            assert(rhs.tag() == .bool_ or rhs.tag() == .arith); 
            assert(lhs.tag() == rhs.tag());

            return .{ .bool_ = .{ .constant = (lhs.arith.constant == rhs.arith.constant ) }};
        },
        else => unreachable,
    }
}
