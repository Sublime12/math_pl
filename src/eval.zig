const std = @import("std");

const expression_pkg = @import("expression.zig");
const stdlib_pkg = @import("stdlib.zig");

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

const print = stdlib_pkg.print;

// Because functions are meant to be fun to use :)
const Funs = std.StringArrayHashMapUnmanaged(FnExpr);
const Context = struct {
    funs: Funs,
    alloc: Allocator,
};

pub fn buildContext(program: Expr, alloc: Allocator) !Context {
    assert(program.tag() == .list);
    var functions: Funs = .empty;
    for (program.list.items) |expr| {
        if (expr.tag() == .fn_def) {
            try functions.put(alloc, expr.fn_def.name, expr.fn_def);
        }
    }
    var print_args: std.ArrayList([]const u8) = .empty;
    try print_args.append(alloc, "c");

    const print_fn: FnExpr = .{
        .name = "print",
        .args = print_args,
        .body = .{ .fn_binding = .{ .fn_ = print } },
    };
    try functions.put(alloc, "print", print_fn);
    return .{ .funs = functions, .alloc = alloc };
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
        .fn_def => {
            return expr;
        },
        .list => |list| {
            var list_evaluated: std.ArrayList(Expr) = .empty;
            for (list.items) |el_expr| {
                const new_expr = eval(el_expr, ctx, local_vars);
                list_evaluated.append(ctx.alloc, new_expr) catch unreachable;
            }
            return list_evaluated.getLast();
        },
        .void_ => return expr,
    }
}

fn eval_fn_call(expr: FnCallExpr, ctx: Context, local_vars: Vars) Expr {
    // if (std.mem.eql(u8, expr.name, "print")) {
    //     const arg = eval(expr.args.items[0], ctx, local_vars);
    //     print(arg);
    //     return .{ .bool_ = .{ .constant = false } };
    // }
    const fn_def = ctx.funs.get(expr.name) orelse {
        panic("Called this function {s} but it does not exist\n", .{expr.name});
    };
    var fn_params: Vars = .init(ctx.alloc);
    // assert(expr.args.items.len == fn_def.fn_std.args.items.len);
    for (0..expr.args.items.len) |i| {
        const arg = expr.args.items[i];
        const arg_name = fn_def.args.items[i];
        const arg_eval = eval(arg, ctx, local_vars);
        assert(arg_eval.tag() == .bool_ or arg_eval.tag() == .arith);
        const var_: Var = if (arg_eval.tag() == .bool_)
            .{ .bool_ = arg_eval.bool_.constant }
        else
            .{ .int = arg_eval.arith.constant };
        fn_params.putNoClobber(arg_name, var_) catch unreachable;
    }

    return eval_fn(fn_def, ctx, fn_params);
}

fn eval_fn(fn_def: FnExpr, ctx: Context, fn_params: Vars) Expr {
    return switch (fn_def.body) {
        .fn_std => |fn_std| eval(fn_std.body.*, ctx, fn_params),
        .fn_binding => |fn_binding| fn_binding.fn_(fn_params),
    };
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
