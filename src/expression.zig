const std = @import("std");

const eval_pkg = @import("eval.zig");

const Vars = eval_pkg.Vars;

const FnExprTag = enum { fn_std, fn_binding };

const panic = std.debug.panic;

pub const FnExpr = struct {
    const Self = @This();

    name: []const u8,
    args: std.ArrayList([]const u8),
    body: FnBody,

    pub fn init(name: []const u8, args: std.ArrayList([]const u8), body: *const Expr) FnExpr {
        return .{
            .name = name,
            .args = args,
            .body = FnBody.init(body),
        };
    }

    pub fn print(self: Self) void {
        std.debug.print("let {s} = fn ", .{self.name});
        for (self.args.items) |arg| {
            std.debug.print("{s} ", .{arg});
        }
        std.debug.print(" -> ", .{});
        switch (self.body) {
            .fn_binding => std.debug.print("binding:  ...", .{}),
            .fn_std => |fn_std| fn_std.print(),
        }
    }
};

pub const BindExpr = struct {
    const Self = @This();

    id: []const u8,
    body: *Expr,
    closure: *Expr,

    pub fn print(self: Self) void {
        std.debug.print("bind {s} = ", .{self.id});
        self.body.print();
        std.debug.print(" in (", .{});
        self.closure.print();
        std.debug.print(")", .{});
    }
};

pub const FnBody = union(FnExprTag) {
    const Self = @This();
    fn_std: FnStdExpr,
    fn_binding: FnBindingExpr,

    pub fn init(body: *const Expr) FnExpr {
        return .{ .fn_std = FnStdExpr.init(body) };
    }

    pub fn print(self: Self) void {
        self.fn_std.print();
    }
};

pub const FnBindingExpr = struct {
    fn_: *const fn (args: Vars) Expr,
};

pub const FnStdExpr = struct {
    const Self = @This();

    body: *const Expr,

    pub fn init(body: *const Expr) FnStdExpr {
        return .{
            .body = body,
        };
    }

    pub fn print(self: Self) void {
        self.body.print();
    }
};

pub const ExprTag = enum {
    if_,
    arith,
    bool_,
    fn_call,
    fn_def,
    var_,
    bind,
    list,
    struct_,
    struct_instance,
    void_,
};

pub const Expr = union(ExprTag) {
    const Self = @This();

    if_: IfExpr,
    arith: ArithExpr,
    bool_: BoolExpr,
    fn_call: FnCallExpr,
    fn_def: FnExpr,
    var_: []const u8,
    bind: BindExpr,
    list: std.ArrayList(Expr),
    struct_: StructExpr,
    struct_instance: StructInstanceExpr,
    void_: i32,

    pub fn isInt(self: Self) bool {
        if (self.tag() != .arith) return false;
        return self.arith.tag() == .constant;
    }

    pub fn isBool(self: Self) bool {
        if (self.tag() != .bool_) return false;
        return self.bool_.tag() == .constant;
    }

    pub fn print(self: Self) void {
        switch (self) {
            .if_ => |expr| expr.print(),
            .arith => |expr| expr.print(),
            .bool_ => |expr| expr.print(),
            .fn_call => |expr| expr.print(),
            .fn_def => |expr| expr.print(),
            .var_ => |expr| std.debug.print("{s}", .{expr}),
            .struct_instance => |expr| expr.print(),
            .list => |expr| {
                for (expr.items) |el| {
                    el.print();
                    std.debug.print("; \n", .{});
                }
            },
            .void_ => std.debug.print("void", .{}),
            .struct_ => panic("print for struct_ not yet implemented", .{}),
            .bind => |expr| expr.print(),
        }
    }

    pub fn tag(self: Self) ExprTag {
        return @as(ExprTag, self);
    }
};

const StructExpr = struct {
    name: []const u8,
    fields: std.ArrayList([]const u8),
};

const Values = std.StringHashMap(Expr);

const StructInstanceExpr = struct {
    const Self = @This();
    name: []const u8,
    values: std.StringHashMapUnmanaged(Expr),

    pub fn print(self: Self) void {
        std.debug.print("@{s}{{ ", .{self.name});
        var it = self.values.iterator();
        while (it.next()) |value| {
            std.debug.print(".{s} = ", .{value.key_ptr.*});
            value.value_ptr.print();
            std.debug.print(", ", .{});
        }
        std.debug.print("}}", .{});
    }
};

pub const ArgsExpr = std.ArrayList(Expr);

pub const FnCallExpr = struct {
    const Self = @This();

    name: []const u8,
    args: ArgsExpr,

    pub fn print(self: Self) void {
        std.debug.print("{s} (", .{self.name});
        for (self.args.items) |arg| {
            std.debug.print(" ", .{});
            arg.print();
            std.debug.print(",", .{});
        }
        std.debug.print(")", .{});
    }
};

pub const IfExpr = struct {
    const Self = @This();

    eval: *Expr,
    then: *Expr,
    else_: *Expr,

    pub fn print(self: Self) void {
        std.debug.print("if (", .{});
        self.eval.print();
        std.debug.print(") {{ ", .{});
        self.then.print();
        std.debug.print(" }} else {{ ", .{});
        self.else_.print();
        std.debug.print(" }}", .{});
    }
};

const ArithTag = enum {
    prod,
    minus,
    plus,
    constant,
    str,
};

pub const ArithExpr = union(ArithTag) {
    const Self = @This();

    prod: BinOp,
    minus: BinOp,
    plus: BinOp,
    constant: i32,
    str: []const u8,

    pub fn print(self: Self) void {
        switch (self) {
            .prod => |expr| expr.print("*"),
            .minus => |expr| expr.print("-"),
            .plus => |expr| expr.print("+"),
            .constant => |expr| std.debug.print("{}", .{expr}),
            .str => |expr| std.debug.print("s\"{s}\"", .{expr}),
        }
    }

    pub fn tag(self: Self) ArithTag {
        return @as(ArithTag, self);
    }
};

pub const BinOp = struct {
    const Self = @This();
    lhs: *Expr,
    rhs: *Expr,

    pub fn print(self: Self, str: []const u8) void {
        std.debug.print("(", .{});
        self.lhs.print();
        std.debug.print(" {s} ", .{str});
        self.rhs.print();

        std.debug.print(")", .{});
    }
};

pub const BinCmpExpr = struct {
    const Self = @This();

    lhs: *const Expr,
    rhs: *const Expr,

    pub fn print(self: Self, op: []const u8) void {
        self.lhs.print();
        std.debug.print(" {s} ", .{op});
        self.rhs.print();
    }
};

const BoolTag = enum {
    constant,
    eql,
    gt,
    lt,
};

pub const BoolExpr = union(BoolTag) {
    const Self = @This();

    constant: bool,
    eql: BinCmpExpr,
    gt: BinCmpExpr,
    lt: BinCmpExpr,

    pub fn tag(self: Self) BoolTag {
        return @as(BoolTag, self);
    }

    pub fn print(self: Self) void {
        switch (self) {
            .constant => |expr| std.debug.print("{}", .{expr}),
            .eql => |expr| {
                expr.print("==");
                std.debug.print(")", .{});
            },
            .gt => |expr| {
                expr.print("<");
                std.debug.print(")", .{});
            },
            .lt => |expr| {
                expr.print(">");
                std.debug.print(")", .{});
            },
        }
    }
};
