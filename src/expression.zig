const std = @import("std");

pub const FnExpr = struct {
    const Self = @This();

    name: []const u8,
    args: std.ArrayList([]const u8),
    body: *const Expr,

    pub fn init(name: []const u8, args: std.ArrayList([]const u8), body: *const Expr) FnExpr {
        return .{
            .name = name,
            .args = args,
            .body = body,
        };
    }

    pub fn print(self: Self) void {
        std.debug.print("let {s} = fn ", .{self.name});
        for (self.args.items) |arg| {
            std.debug.print("{s} ", .{arg});
        }
        std.debug.print(" -> ", .{});
        self.body.print();
    }
};

const ExprTag = enum {
    if_,
    arith,
    bool_,
    fn_call,
    fn_def,
};

pub const Expr = union(ExprTag) {
    const Self = @This();

    if_: IfExpr,
    arith: ArithExpr,
    bool_: BoolExpr,
    fn_call: FnCallExpr,
    fn_def: FnExpr,

    pub fn print(self: Self) void {
        switch (self) {
            .if_ => |expr| expr.print(),
            .arith => |expr| expr.print(),
            .bool_ => |expr| expr.print(),
            .fn_call => |expr| expr.print(),
            .fn_def => |expr| expr.print(),
        }
    }
};

const FnCallExpr = struct {
    const Self = @This();

    name: std.ArrayList(u8),
    args: std.ArrayList(Expr),

    pub fn print(self: Self) void {
        _ = self;
        unreachable;
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
    constant,
    var_,
};

pub const ArithExpr = union(ArithTag) {
    const Self = @This();

    prod: BinOp,
    constant: i32,
    var_: []const u8,

    pub fn print(self: Self) void {
        switch (self) {
            .prod => |expr| expr.print(),
            .constant => |expr| std.debug.print("{}", .{expr}),
            .var_=> |expr| std.debug.print("{s}", .{expr}),
        }
    }
};

pub const BinOp = struct {
    const Self = @This();
    lhs: *Expr,
    rhs: *Expr,

    pub fn print(self: Self) void { 
        self.lhs.print();
        std.debug.print(" ", .{});
        self.rhs.print();
    }
};

pub const BinCmpExpr = struct {
    const Self = @This();

    lhs: *const Expr,
    rhs: *const Expr,

    pub fn print(self: Self) void {
        self.lhs.print();
        std.debug.print(" ", .{});
        self.rhs.print();
    }
};

const BoolTag = enum {
    var_,
    constant,
    eql,
    gt,
    lt,
};

pub const BoolExpr = union(BoolTag) {
    const Self = @This();

    var_: []const u8,
    constant: f32,
    eql: BinCmpExpr,
    gt: BinCmpExpr,
    lt: BinCmpExpr,

    pub fn print(self: Self) void {
        switch (self) {
            .var_ => |expr| std.debug.print("{s}", .{expr}),
            .constant => |expr| std.debug.print("{}", .{expr}),
            .eql=> |expr| {
                std.debug.print("(== ", .{});
                expr.print();
                std.debug.print(")", .{});
            },
            .gt => |expr| {
                std.debug.print("(= ", .{});
                expr.print();
                std.debug.print(")", .{});
            },
            .lt => |expr| {
                std.debug.print("(= ", .{});
                expr.print();
                std.debug.print(")", .{});
            },
        }
    }
};
