const std = @import("std");

pub const FnExpr = struct {
    name: []const u8,
    args: std.ArrayList([]const u8),
    body: Expr,

    pub fn init(name: []const u8, args: std.ArrayList([]const u8), body: Expr) FnExpr {
        return .{
            .name = name,
            .args = args,
            .body = body,
        };
    }
};

const ExprTag = enum {
    if_,
    arith,
    bool_,
    fn_call,
};

pub const Expr = union(ExprTag) {
    if_: IfExpr,
    arith: ArithExpr,
    bool_: BoolExpr,
    fn_call: FnCallExpr,
};

const FnCallExpr = struct {
    name: std.ArrayList(u8),
    args: std.ArrayList(Expr),
};

pub const IfExpr = struct {
    eval: *BoolExpr,
    then: *Expr,
    else_: *Expr,
};

const ArithTag = enum {
    binOp,
    constant,
    var_,
};

pub const ArithExpr = union(ArithTag) {
    binOp: BinOp,
    constant: f32,
    var_: []const u8,
};

pub const BinOp = struct {
    lhs: *ArithExpr,
    rhs: *ArithExpr,
};

pub const BinCmpExpr = struct {
    lhs: *const BoolExpr,
    rhs: *const BoolExpr,
};

const BoolTag = enum {
    var_,
    constant,
    eql,
    gt,
    lt,
};

pub const BoolExpr = union(BoolTag) {
    var_: []const u8,
    constant: f32,
    eql: BinCmpExpr,
    gt: BinCmpExpr,
    lt: BinCmpExpr,
};
