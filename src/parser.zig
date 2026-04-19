const std = @import("std");

const expression_pkg = @import("expression.zig");

const Expr = expression_pkg.Expr;
const FnExpr = expression_pkg.FnExpr;
const Allocator = std.mem.Allocator;

const eql = std.ascii.eqlIgnoreCase;
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
        _ = self.lexer.next();

        return parseExpr(self.lexer, self.alloc);
    }

    fn parseExpr(l: *Lexer, alloc: Allocator) error{OutOfMemory}!Expr {
        switch (l.token) {
            .TokenLet => {
                _ = l.next();
                l.expect(.TokenId);
                const id = try alloc.dupe(u8, l.name.items);
                _ = l.next();
                l.expect(.TokenAssign);
                _ = l.next();
                l.expect(.TokenFn);
                _ = l.next();
                var args = std.ArrayList([]const u8).empty;
                while (l.token == .TokenId) {
                    try args.append(alloc, try alloc.dupe(u8, l.name.items));
                    _ = l.next();
                }
                l.expect(.TokenArrow);
                _ = l.next();

                const body = try alloc.create(Expr);
                body.* = try parseExpr(l, alloc);

                const fn_expr: FnExpr = .{
                    .name = id,
                    .args = args,
                    .body = body,
                };
                return .{ .fn_def = fn_expr };
            },
            .TokenIf => {
                _ = l.next();
                return parseIf(l, alloc);
            },
            .TokenId => {
                const name = try alloc.dupe(u8, l.name.items);
                const name_expr = try alloc.create(Expr);
                name_expr.* = .{ .arith = .{ .var_ = name } };
                _ = l.next();
                std.debug.print("XXXXXXX {}\n", .{l.token});
                if (l.token == .TokenProd) {
                    _ = l.next();
                    const rhs = try alloc.create(Expr);
                    rhs.* = try parseExpr(l, alloc);
                    // rhs.print();
                    // std.debug.print(", TOKEN = {}", .{l.token});
                    return .{ .arith = .{ .prod = .{ .lhs = name_expr, .rhs = rhs } } };
                }
                return name_expr.*;
            },
            .TokenInt => {
                const value = l.integer_value.?;
                const name_expr = try alloc.create(Expr);
                name_expr.* = .{ .arith = .{ .constant = value } };
                _ = l.next();
                if (l.token == .TokenEql) {
                    _ = l.next();
                    const rhs = try alloc.create(Expr);
                    rhs.* = try parseExpr(l, alloc);
                    return .{ .bool_ = .{ .eql = .{ .lhs = name_expr, .rhs = rhs } } };
                } else if (l.token == .TokenProd) {
                    _ = l.next();
                    const rhs = try alloc.create(Expr);
                    rhs.* = try parseExpr(l, alloc);
                    return .{ .arith = .{ .prod = .{ .lhs = name_expr, .rhs = rhs } } };
                }
                return .{ .arith = .{ .constant = value } };
            },
            .TokenFn, .TokenSelfFn => {
                const name = try alloc.dupe(u8, l.name.items);
                _ = l.next();
                l.expect(.TokenOParen);
                _ = l.next();
                var args: std.ArrayList(Expr) = .empty;
                while (l.token != .TokenCParen) {
                    const arg = try parseExpr(l, alloc);
                    try args.append(alloc, arg);
                    l.expect(.TokenComma);
                    _ = l.next();
                }
                l.expect(.TokenCParen);
                _ = l.next();
                return .{ .fn_call = .{ .name = name, .args = args } };
            },
            else => {},
        }

        panic(
            "Panic with token {}, value: {s}",
            .{ l.token, l.name.items },
        );
    }

    fn parseIf(l: *Lexer, alloc: Allocator) !Expr {
        l.expect(.TokenOParen);
        _ = l.next();
        const eval = try alloc.create(Expr);
        eval.* = try parseBool(l, alloc);
        _ = l.expect(.TokenCParen);
        _ = l.next();
        _ = l.expect(.TokenThen);
        _ = l.next();
        const then = try alloc.create(Expr);
        then.* = try parseExpr(l, alloc);
        l.expect(.TokenElse);
        _ = l.next();
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
            _ = l.next();
            const rhs = try alloc.create(Expr);
            rhs.* = try parseExpr(l, alloc);
            return .{
                .bool_ = .{ .eql = .{ .lhs = lhs, .rhs = rhs } },
            };
        }

        panic("Not yet implemented for functions", .{});
    }
};

pub const Lexer = struct {
    content: []const u8,
    token: TokenKind,
    tokenType: ?TokenType,
    integer_value: ?i32,
    cursor: Cursor,
    name: std.ArrayList(u8),

    pub fn init(content: []const u8, emptyTokenStr: std.ArrayList(u8)) Lexer {
        return .{
            .content = content,
            .token = .TokenNone,
            .cursor = .empty,
            .name = emptyTokenStr,
            .integer_value = null,
            .tokenType = null,
        };
    }

    pub fn expect(l: *Lexer, expected: TokenKind) void {
        if (l.token != expected) {
            panic("expected this {}, found this {} at {}:{}, name: {s}, integer {?}", .{
                expected,
                l.token,
                l.cursor.row,
                l.cursor.col,
                l.name.items,
                l.integer_value,
            });
        }
    }

    fn clearAppendSymbol(l: *Lexer, x: u8) void {
        l.name.clearRetainingCapacity();
        l.name.appendAssumeCapacity(x);
    }

    pub fn next(l: *Lexer) bool {
        l.trim_left();

        const x_opt = l.next_char();
        if (x_opt == null) {
            l.token = .TokenEnd;
            return true;
        }

        const x = x_opt.?;
        switch (x) {
            '=' => {
                l.clearAppendSymbol(x);
                const n_char = l.current_char();
                if (n_char == '=') {
                    _ = l.next_char();
                    l.name.appendAssumeCapacity(n_char.?);
                    l.token = .TokenEql;
                    l.tokenType = .BinOp;
                    return true;
                }
                l.token = .TokenAssign;
                l.tokenType = .Other;
                return true;
            },
            '-' => {
                l.clearAppendSymbol(x);
                const n_char = l.current_char();
                if (n_char == '>') {
                    _ = l.next_char();
                    l.name.appendAssumeCapacity(n_char.?);
                    l.token = .TokenArrow;
                    l.tokenType = .Keyword;
                    return true;
                }
                l.tokenType = .BinOp;
                l.token = .TokenMinus;
                return true;
            },
            '(' => {
                l.clearAppendSymbol(x);
                l.tokenType = .Paren;
                l.token = .TokenOParen;
                return true;
            },
            ')' => {
                l.clearAppendSymbol(x);
                l.tokenType = .Paren;
                l.token = .TokenCParen;
                return true;
            },
            '*' => {
                l.clearAppendSymbol(x);
                l.tokenType = .ArithOp;
                l.token = .TokenProd;
                return true;
            },
            ',' => {
                l.clearAppendSymbol(x);
                l.tokenType = .Other;
                l.token = .TokenComma;
                return true;
            },
            else => {},
        }

        if (isSymbol(x)) {
            l.clearAppendSymbol(x);
            while (l.current_char()) |c| {
                if (!isSymbol(c)) break;
                l.name.appendAssumeCapacity(c);
                _ = l.next_char();
            }

            if (eql("let", l.name.items)) {
                l.token = .TokenLet;
                l.tokenType = .Keyword;
                return true;
            } else if (eql("if", l.name.items)) {
                l.token = .TokenIf;
                l.tokenType = .Keyword;
                return true;
            } else if (eql("self_fn", l.name.items)) {
                l.token = .TokenSelfFn;
                l.tokenType = .Keyword;
                return true;
            } else if (eql("fn", l.name.items)) {
                l.token = .TokenFn;
                l.tokenType = .Keyword;
                return true;
            } else if (eql("then", l.name.items)) {
                l.token = .TokenThen;
                l.tokenType = .Keyword;
                return true;
            } else if (eql("else", l.name.items)) {
                l.token = .TokenElse;
                l.tokenType = .Keyword;
                return true;
            } else if (std.ascii.isDigit(l.name.items[0])) {
                const number = std.fmt.parseInt(i32, l.name.items, 10) catch {
                    std.debug.panic("Expected number, found: {s}", .{l.name.items});
                };
                l.integer_value = number;
                l.token = .TokenInt;
                l.tokenType = .Primary;
                return true;
            } else {
                l.token = .TokenId;
                l.tokenType = .Primary;
                return true;
            }
        }
        return false;
    }

    fn isSymbol(x: u8) bool {
        return std.ascii.isAlphanumeric(x) or x == '_';
    }

    pub fn trim_left(l: *Lexer) void {
        while (std.ascii.isWhitespace(l.current_char() orelse return)) {
            _ = l.next_char();
        }
    }

    fn next_char(l: *Lexer) ?u8 {
        if (l.cursor.pos >= l.content.len) return null;

        const x = l.current_char().?;
        l.cursor.pos += 1;
        l.cursor.col += 1;

        if (isLn(x)) {
            l.cursor.bol = l.cursor.pos;
            l.cursor.row += 1;
            l.cursor.col = 0;
        }
        return x;
    }

    fn current_char(l: *Lexer) ?u8 {
        if (l.cursor.pos >= l.content.len) return null;
        return l.content[l.cursor.pos];
    }

    fn peek_next_char(l: *Lexer) ?u8 {
        if (l.cursor.pos + 1 >= l.content.len) return null;
        return l.content[l.cursor.pos + 1];
    }

    fn isLn(c: u8) bool {
        return c == '\n';
    }
};

const TokenKind = enum {
    // Cmp ops
    TokenEql,
    TokenAssign,

    // Arith ops
    TokenMinus,
    TokenProd,

    // parentheses
    TokenOParen,
    TokenCParen,

    // keywords
    TokenArrow,
    TokenFn,
    TokenElse,
    TokenLet,
    TokenIf,
    TokenSelfFn,
    TokenThen,

    // primary
    TokenInt,
    TokenId,

    // others
    TokenComma,
    TokenNone,
    TokenEnd,
};

const TokenType = enum {
    ArithOp,
    BinOp,
    CmpOp,
    Primary,
    Paren,
    Keyword,
    Other,
};

const Cursor = struct {
    const Self = @This();

    // absolute position in str
    pos: usize,
    // beginning of the current line
    bol: usize,
    // what column the cursor is at
    col: usize,
    // what row the cursor is at (can also be (pos - bol)
    row: usize,

    pub const empty: Self = .{
        .pos = 0,
        .bol = 0,
        .col = 0,
        .row = 0,
    };
};
