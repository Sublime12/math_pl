const std = @import("std");

const expression_pkg = @import("expression.zig");
const lexer_pkg = @import("lexer.zig");

const Expr = expression_pkg.Expr;
const FnExpr = expression_pkg.FnExpr;
const ArithExpr = expression_pkg.ArithExpr;
const BoolExpr = expression_pkg.BoolExpr;
const ArgsExpr = expression_pkg.ArgsExpr;
const Allocator = std.mem.Allocator;

const Lexer = lexer_pkg.Lexer;

const panic = std.debug.panic;

pub const Parser = struct {
    const Self = @This();
    lexer: *Lexer,
    alloc: Allocator,

    pub fn init(l: *Lexer, alloc: Allocator) Self {
        return .{
            .lexer = l,
            .alloc = alloc,
        };
    }

    pub fn parse(self: *Self) !Expr {
        self.lexer.cursor = .empty;
        self.lexer.nexti();

        var program: std.ArrayList(Expr) = .empty;
        var i: i32 = 0;
        while (self.lexer.token != .TokenEnd) {
            const expr = try parseExpr(self.lexer, self.alloc);
            self.lexer.expect(.TokenSemicolon);
            self.lexer.nexti();
            try program.append(self.alloc, expr);
            i += 1;
        }
        return .{ .list = program };
    }

    fn parseFnDef(l: *Lexer, alloc: Allocator) !Expr {
        l.expect(.TokenId);
        const id = l.name.asStr(l.content);
        l.nexti();
        l.expect(.TokenAssign);
        l.nexti();
        l.expect(.TokenFn);
        l.nexti();
        var args = std.ArrayList([]const u8).empty;
        while (l.token == .TokenId) {
            try args.append(alloc, l.name.asStr(l.content));
            l.nexti();
        }
        l.expect(.TokenArrow);
        l.nexti();

        const body = try alloc.create(Expr);
        body.* = try parseExpr(l, alloc);

        const fn_expr: FnExpr = .{
            .name = id,
            .args = args,
            .body = .{ .fn_std = .{ .body = body } },
        };
        return .{ .fn_def = fn_expr };
    }

    /// can be an arith expr a + 1 - 3
    /// or a bool expr a = 1
    /// or a function call a(b, c, d)
    fn parseBeginWithIdOrInt(l: *Lexer, alloc: Allocator) !Expr {
        const name = l.name.asStr(l.content);
        var next_l = l.nextl();
        var lhs = try alloc.create(Expr);
        if (l.token == .TokenId) {
            lhs.* = switch (next_l.token) {
                .TokenOParen => blk: {
                    l.nexti();
                    const expr = try parseFnCall(l, alloc, name);
                    break :blk expr;
                },
                else => blk: {
                    l.nexti();
                    break :blk .{ .var_ = name };
                },
            };
        } else if (l.token == .TokenInt) {
            lhs.* = .{ .arith = .{ .constant = l.integer_value.? } };
            l.nexti();
        } else if (l.token == .TokenStr) {
            lhs.* = .{ .arith = .{ .str = l.name.asStr(l.content) } };
            l.nexti();
        } else if (l.tokenType == .Primary) panic("Must be identifier, integer or string", .{});

        while (l.tokenType == .ArithOp or l.tokenType == .BoolOp) {
            const op_token = l.token;
            const op_token_type = l.tokenType;
            l.nexti();

            const rhs = try alloc.create(Expr);
            next_l = l.*;
            next_l.nexti();

            const current_name = l.name.asStr(l.content);
            rhs.* = switch (l.token) {
                .TokenId => if (next_l.token == .TokenOParen) blk: {
                    l.nexti();
                    const expr = try parseFnCall(l, alloc, current_name);
                    break :blk expr;
                } else blk: {
                    l.nexti();
                    break :blk .{ .var_ = current_name };
                },
                .TokenInt => blk: {
                    l.nexti();
                    break :blk .{ .arith = .{ .constant = l.integer_value.? } };
                },
                .TokenStr => blk: {
                    l.nexti();
                    break :blk .{ .arith = .{ .str = current_name } };
                },
                else => blk: {
                    const expr = try parseExpr(l, alloc);
                    break :blk expr;
                },
            };

            if (op_token_type == .ArithOp) {
                const op: ArithExpr = switch (op_token) {
                    .TokenProd => .{ .prod = .{ .lhs = lhs, .rhs = rhs } },
                    .TokenPlus => .{ .plus = .{ .lhs = lhs, .rhs = rhs } },
                    .TokenMinus => .{ .minus = .{ .lhs = lhs, .rhs = rhs } },
                    else => unreachable,
                };

                lhs = try alloc.create(Expr);
                lhs.* = .{ .arith = op };
            } else if (op_token_type == .BoolOp) {
                const op: BoolExpr = switch (op_token) {
                    .TokenEql => .{ .eql = .{ .lhs = lhs, .rhs = rhs } },
                    else => panic("not catch for {}", .{op_token}),
                };

                lhs = try alloc.create(Expr);
                lhs.* = .{ .bool_ = op };
            }
        }

        return lhs.*;
    }

    fn parseFnCall(l: *Lexer, alloc: Allocator, name: []const u8) !Expr {
        l.expect(.TokenOParen);
        l.nexti();
        const args = try parseArgs(l, alloc);
        l.expect(.TokenCParen);
        l.nexti();
        const lhs: Expr = .{ .fn_call = .{ .name = name, .args = args } };
        return lhs;
    }

    pub fn parseArgs(l: *Lexer, alloc: Allocator) !ArgsExpr {
        var args: std.ArrayList(Expr) = .empty;
        while (l.token != .TokenCParen) {
            const arg = try parseExpr(l, alloc);
            try args.append(alloc, arg);
            l.expect(.TokenComma);
            l.nexti();
        }
        return args;
    }

    fn parseBeginWithOParen(l: *Lexer, alloc: Allocator) !Expr {
        l.expect(.TokenOParen);
        l.nexti();

        const lhs = try alloc.create(Expr);
        lhs.* = try parseExpr(l, alloc);
        const next_l = l.nextl();

        switch (next_l.tokenType) {
            .BoolOp => {
                l.nexti();
                const token = l.token;
                l.nexti();
                const rhs = try alloc.create(Expr);
                rhs.* = try parseExpr(l, alloc);
                const op: BoolExpr = switch (token) {
                    .TokenEql => .{ .eql = .{ .lhs = lhs, .rhs = rhs } },
                    else => panic("panic bool begin with", .{}),
                };
                return .{ .bool_ = op };
            },
            .ArithOp => {
                l.nexti();
                const token = l.token;
                l.nexti();
                const rhs = try alloc.create(Expr);
                rhs.* = try parseExpr(l, alloc);
                const op: ArithExpr = switch (token) {
                    .TokenProd => .{ .prod = .{ .lhs = lhs, .rhs = rhs } },
                    .TokenMinus => .{ .minus = .{ .lhs = lhs, .rhs = rhs } },
                    .TokenPlus => .{ .plus = .{ .lhs = lhs, .rhs = rhs } },
                    else => panic("panic bool begin with", .{}),
                };
                return .{ .arith = op };
            },
            else => {},
        }

        return lhs.*;
    }

    fn parseExpr(l: *Lexer, alloc: Allocator) error{OutOfMemory}!Expr {
        switch (l.token) {
            .TokenLet => {
                l.nexti();
                return parseFnDef(l, alloc);
            },
            .TokenIf => {
                l.nexti();
                return parseIf(l, alloc);
            },
            .TokenId, .TokenInt, .TokenStr => {
                return parseBeginWithIdOrInt(l, alloc);
            },
            .TokenSelfFn => {
                const name = l.name.asStr(l.content);
                l.nexti();
                l.expect(.TokenOParen);
                l.nexti();
                const args = try parseArgs(l, alloc);
                l.expect(.TokenCParen);
                l.nexti();
                return .{ .fn_call = .{ .name = name, .args = args } };
            },
            // an open paren (not in the context of a function)
            .TokenOParen => {
                const expr = parseBeginWithOParen(l, alloc);
                l.expect(.TokenCParen);
                l.nexti();
                return expr;
            },
            else => {},
        }

        panic(
            "Panic with token {}, value: {s}",
            .{ l.token, l.name.asStr(l.content) },
        );
    }

    fn parseIf(l: *Lexer, alloc: Allocator) !Expr {
        const eval = try alloc.create(Expr);
        eval.* = try parseExpr(l, alloc);
        l.expect(.TokenThen);
        l.nexti();
        const then = try alloc.create(Expr);
        then.* = try parseExpr(l, alloc);
        l.expect(.TokenElse);
        l.nexti();
        const else_ = try alloc.create(Expr);
        else_.* = try parseExpr(l, alloc);

        return .{
            .if_ = .{
                .eval = eval,
                .then = then,
                .else_ = else_,
            },
        };
    }

    fn parseBool(l: *Lexer, alloc: Allocator) !Expr {
        if (l.token == .TokenId) {
            const lhs = try alloc.create(Expr);
            lhs.* = try parseExpr(l, alloc);
            l.expect(.TokenEql);
            l.nexti();
            const rhs = try alloc.create(Expr);
            rhs.* = try parseExpr(l, alloc);
            return .{
                .bool_ = .{ .eql = .{ .lhs = lhs, .rhs = rhs } },
            };
        }

        panic("Not yet implemented for functions", .{});
    }
};
