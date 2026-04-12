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
};

const Expr = union(ExprTag) {
    if_: IfExpr,
    arith: ArithExpr,
    bool_: BoolExpr,
};

const IfExpr = struct {
    eval: *BoolExpr,
    if_: *Expr,
    else_: *Expr,
};

const ArithTag = enum {
    binOp,
    constant,
    var_,
};

const ArithExpr = union(ArithTag) {
    binOp: f32,
    constant: f32,
    var_: []const u8,
};

const BoolTag = enum { constant };

const BoolExpr = union(BoolTag) {
    constant: bool,
};
