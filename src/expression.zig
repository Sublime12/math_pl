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

pub const ExprTag = enum {
    if_,
    arith,
    bool_,
    fn_call,
    fn_def,
    var_,
};

pub const Expr = union(ExprTag) {
    const Self = @This();

    if_: IfExpr,
    arith: ArithExpr,
    bool_: BoolExpr,
    fn_call: FnCallExpr,
    fn_def: FnExpr,
    var_: []const u8,

    pub fn print(self: Self) void {
        switch (self) {
            .if_ => |expr| expr.print(),
            .arith => |expr| expr.print(),
            .bool_ => |expr| expr.print(),
            .fn_call => |expr| expr.print(),
            .fn_def => |expr| expr.print(),
            .var_ => |expr| std.debug.print("{s}", .{expr}),
        }
    }

    pub fn tag(self: Self) ExprTag {
        return @as(ExprTag, self);
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
};

pub const ArithExpr = union(ArithTag) {
    const Self = @This();

    prod: BinOp,
    minus: BinOp,
    plus: BinOp,
    constant: i32,

    pub fn print(self: Self) void {
        switch (self) {
            .prod => |expr| expr.print("*"),
            .minus => |expr| expr.print("-"),
            .plus => |expr| expr.print("+"),
            .constant => |expr| std.debug.print("{}", .{expr}),
        }
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
