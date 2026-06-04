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
const StructExpr = expression_pkg.StructExpr;
const StructInstanceExpr = expression_pkg.StructInstanceExpr;
const BindExpr = expression_pkg.BindExpr;

const assert = std.debug.assert;
const panic = std.debug.panic;

const print = stdlib_pkg.print;
const print_int = stdlib_pkg.print_int;

// Because functions are meant to be fun to use :)
const Funs = std.StringArrayHashMapUnmanaged(FnExpr);
const Structs = std.StringArrayHashMapUnmanaged(StructExpr);
const Context = struct {
    const Self = @This();

    funs: Funs,
    structs: Structs,
    alloc: Allocator,

    pub fn print(self: Self) void {
        std.debug.print("defined structs: \n", .{});
        var it = self.structs.iterator();

        while (it.next()) |struct_| {
            std.debug.print("{s} -> ", .{struct_.key_ptr.*});
            struct_.value_ptr.print();
            std.debug.print("\n", .{});
        }
    }
};

pub fn semAnal(program: Expr, ctx: Context) void {
    switch (program) {
        // base case
        .struct_instance => |struct_inst| {
            const struct_ = ctx.structs.get(struct_inst.name) orelse {
                panic("tried getting struct {s} but not defined\n", .{struct_inst.name});
            };

            var inst_fields = struct_inst.fields.iterator();
            while (inst_fields.next()) |inst_field| {
                if (!contains(inst_field.key_ptr.*, struct_.fields)) {
                    panic(
                        "struct instance contains field {s} but not defined in {s}",
                        .{ inst_field.key_ptr.*, struct_.name },
                    );
                }
            }
        },
        .arith => |arith_expr| {
            switch (arith_expr) {
                .plus, .minus, .prod => |expr| {
                    semAnal(expr.lhs.*, ctx);
                    semAnal(expr.rhs.*, ctx);
                },
                .constant, .str => {},
            }
        },
        .bool_ => |bool_expr| {
            switch (bool_expr) {
                .eql, .gt, .lt => |expr| {
                    semAnal(expr.lhs.*, ctx);
                    semAnal(expr.rhs.*, ctx);
                },
                .constant => {},
            }
        },
        .bind => |bind_expr| {
            semAnal(bind_expr.body.*, ctx);
            semAnal(bind_expr.closure.*, ctx);
        },
        .field_access => |field_expr| semAnal(field_expr.lhs.*, ctx),
        .fn_call => |fn_call_expr| {
            for (fn_call_expr.args.items) |arg| {
                semAnal(arg, ctx);
            }
        },
        .fn_def => |fn_def_expr| {
            switch (fn_def_expr.body) {
                .fn_std => |fn_std| semAnal(fn_std.body.*, ctx),
                .fn_binding => {},
            }
        },
        .list => |list_expr| {
            for (list_expr.items) |sub_expr| {
                semAnal(sub_expr, ctx);
            }
        },
        .if_ => |if_expr| {
            semAnal(if_expr.eval.*, ctx);
            semAnal(if_expr.then.*, ctx);
            semAnal(if_expr.else_.*, ctx);
        },
        .struct_, .var_, .void_ => {},
    }
}

fn contains(item: []const u8, values: std.ArrayList([]const u8)) bool {
    for (values.items) |val| {
        if (std.mem.eql(u8, item, val)) return true;
    }
    return false;
}

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
    var print_int_args: std.ArrayList([]const u8) = .empty;
    try print_int_args.append(alloc, "c");
    const print_int_fn: FnExpr = .{
        .name = "print_int",
        .args = print_int_args,
        .body = .{ .fn_binding = .{ .fn_ = print_int } },
    };
    try functions.put(alloc, "print", print_fn);
    try functions.put(alloc, "print_int", print_int_fn);

    var ctx: Context = .{ .funs = functions, .alloc = alloc, .structs = .empty };

    try add_structs(program, &ctx);
    return ctx;
}

fn add_structs(program: Expr, ctx: *Context) !void {
    switch (program) {
        .arith => |expr| {
            switch (expr) {
                .plus, .minus, .prod => |arith_expr| {
                    try add_structs(arith_expr.lhs.*, ctx);
                    try add_structs(arith_expr.rhs.*, ctx);
                },
                .constant, .str => {},
            }
        },
        .bool_ => |expr| {
            switch (expr) {
                .eql, .gt, .lt => |bool_expr| {
                    try add_structs(bool_expr.lhs.*, ctx);
                    try add_structs(bool_expr.rhs.*, ctx);
                },
                .constant => {},
            }
        },
        .struct_ => |expr| {
            try ctx.structs.putNoClobber(ctx.alloc, expr.name, expr);
        },
        .list => |list| {
            for (list.items) |sub_expr| {
                try add_structs(sub_expr, ctx);
            }
        },
        // if you need to add structs for more elements,
        // you can finish implement switch for all other types of expr
        else => {},
    }
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
        .fn_def => return expr,
        .list => |list| {
            var list_evaluated: std.ArrayList(Expr) = .empty;
            for (list.items) |el_expr| {
                const new_expr = eval(el_expr, ctx, local_vars);
                list_evaluated.append(ctx.alloc, new_expr) catch unreachable;
            }
            return list_evaluated.getLast();
        },
        .struct_ => panic("eval not yet implemented for struct_", .{}),
        .struct_instance => |struct_instance| {
            var new_expr: StructInstanceExpr = .{ .name = struct_instance.name, .fields = .empty };
            var it = struct_instance.fields.iterator();
            while (it.next()) |inst_field| {
                const efield = eval(inst_field.value_ptr.*, ctx, local_vars);
                new_expr.fields.putNoClobber(ctx.alloc, inst_field.key_ptr.*, efield) catch unreachable;
            }
            return .{ .struct_instance = new_expr };
        },
        .field_access => |field_access| {
            const elhs = eval(field_access.lhs.*, ctx, local_vars);
            assert(elhs.tag() == .struct_instance);
            return elhs.struct_instance.fields.get(field_access.field) orelse {
                panic("tried accessing {s} in struct {s} but do not exist", .{field_access.field, elhs.struct_instance.name});
            };
        },
        .bind => |bind| return eval_bind(bind, ctx, local_vars),
        .void_ => return expr,
    }
}

fn eval_bind(bind: BindExpr, ctx: Context, local_vars: Vars) Expr {
    const id = bind.id;
    const ebody = eval(bind.body.*, ctx, local_vars);
    const body: Var =
        if (ebody.isInt())
            .{ .int = ebody.arith.constant }
        else if (ebody.isBool())
            .{ .bool_ = ebody.bool_.constant }
        else if (ebody.isStructInstance())
            .{ .struct_instance = ebody.struct_instance }
        else
            panic("body must be evaluated of type int or bool", .{});

    var bind_vars = local_vars.clone() catch unreachable;
    bind_vars.putNoClobber(id, body) catch unreachable;
    return eval(bind.closure.*, ctx, bind_vars);
}

fn eval_fn_call(expr: FnCallExpr, ctx: Context, local_vars: Vars) Expr {
    const fn_def = ctx.funs.get(expr.name) orelse {
        panic("Called this function {s} but it does not exist\n", .{expr.name});
    };
    var fn_params: Vars = .init(ctx.alloc);
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
        .struct_instance => |var_| .{ .struct_instance = var_ },
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
        .str => |op| panic("eval_arith unimplemented for str: \"{s}\"", .{op}),
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
    struct_instance,
};

const Var = union(VarTag) {
    const Self = @This();
    int: i32,
    bool_: bool,
    struct_instance: StructInstanceExpr,

    pub fn tag(self: Self) VarTag {
        return @as(VarTag, self);
    }
};

pub const Vars = std.StringHashMap(Var);
