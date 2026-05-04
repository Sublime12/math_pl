const std = @import("std");

const expression_pkg = @import("expression.zig");

const Allocator = std.mem.Allocator;

const Expr = expression_pkg.Expr;
const ExprTag = expression_pkg.ExprTag;
const BoolExpr = expression_pkg.BoolExpr;
const ArithExpr = expression_pkg.ArithExpr;
const IfExpr = expression_pkg.IfExpr;
const FnCallExpr = expression_pkg.FnCallExpr;
const FnExpr = expression_pkg.FnExpr;

const assert = std.debug.assert;
const panic = std.debug.panic;

// Because functions are meant to be fun to use :)
const Funs = std.StringArrayHashMapUnmanaged(FnExpr);
const Context = struct {
    funs: Funs,
};

pub fn buildContext(program: Expr, alloc: Allocator) !Context {
    assert(program.tag() == .list);
    var functions: Funs = .empty;
    for (program.list.items) |expr| {
        if (expr.tag() == .fn_def) {
            try functions.put(alloc, expr.fn_def.name, expr.fn_def);
        }
    }
    return .{ .funs = functions };
}

pub fn eval(expr: Expr, ctx: Context, local_vars: Vars) Expr {
    switch (expr) {
        .bool_ => |bool_| {
            return eval_bool(bool_, ctx, local_vars);
        },
        .arith => |arith| {
            return eval_arith(arith, ctx, local_vars);
        },
        .if_ => |if_| {
            return eval_if(if_, ctx, local_vars);
        },
        .var_ => |var_| {
            return eval_var(var_, ctx, local_vars);
        },
        .fn_call => |fn_call| {
            return eval_fn_call(fn_call, ctx, local_vars);
        },
        else => {},
    }
    unreachable;
}

fn eval_fn_call(expr: FnCallExpr, ctx: Context, local_vars: Vars) Expr {
    _ = expr;
    _ = local_vars;
    _ = ctx;
    panic(
        "Can not evaluate fn_call for now, we need to pass program context containing function definitions",
        .{},
    );
}

fn eval_var(expr: []const u8, ctx: Context, local_vars: Vars) Expr {
    _ = ctx;
    const value = local_vars.get(expr) orelse panic("var {s} not in context", .{expr});
    return switch (value) {
        .bool_ => |var_| .{ .bool_ = .{ .constant = var_ } },
        .int => |var_| .{ .arith = .{ .constant = var_ } },
    };
}

fn eval_if(expr: IfExpr, ctx: Context, local_vars: Vars) Expr {
    const cond = eval(expr.eval.*, ctx, local_vars);
    assert(cond.tag() == .bool_);
    assert(cond.bool_.tag() == .constant);
    return if (cond.bool_.constant)
        eval(expr.then.*, ctx, local_vars)
    else
        eval(expr.else_.*, ctx, local_vars);
}

fn eval_arith(expr: ArithExpr, ctx: Context, local_vars: Vars) Expr {
    switch (expr) {
        .constant => |constant| return .{ .arith = .{ .constant = constant } },
        .prod, .minus, .plus => |op| {
            const lhs = eval(op.lhs.*, ctx, local_vars);
            const rhs = eval(op.rhs.*, ctx, local_vars);

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

fn eval_bool(expr: BoolExpr, ctx: Context, local_vars: Vars) Expr {
    switch (expr) {
        .constant => |const_| return .{ .bool_ = .{
            .constant = const_,
        } },
        .eql => |eql_expr| {
            const lhs = eval(eql_expr.lhs.*, ctx, local_vars);
            const rhs = eval(eql_expr.rhs.*, ctx, local_vars);

            assert(lhs.tag() == .bool_ or lhs.tag() == .arith);
            assert(rhs.tag() == .bool_ or rhs.tag() == .arith);
            assert(lhs.tag() == rhs.tag());

            return .{ .bool_ = .{ .constant = (lhs.arith.constant == rhs.arith.constant) } };
        },
        else => unreachable,
    }
}

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
