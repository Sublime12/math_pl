const std = @import("std");

const expression_pkg = @import("expression.zig");

const Expr = expression_pkg.Expr;
const FnExpr = expression_pkg.FnExpr;
const ArithExpr = expression_pkg.ArithExpr;
const BoolExpr = expression_pkg.BoolExpr;
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

    fn parseFnDef(l: *Lexer, alloc: Allocator) !Expr {
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
    }

    /// can be an arith expr a + 1 - 3
    /// or a bool expr a = 1
    /// or a function call a(b, c, d)
    fn parseBeginWithId(l: *Lexer, alloc: Allocator) !Expr {
        const name = try alloc.dupe(u8, l.name.items);
        const name_expr = try alloc.create(Expr);
        name_expr.* = .{ .arith = .{ .var_ = name } };
        _ = l.next();
        std.debug.print("XXXXXXX {}\n", .{l.token});
        switch (l.tokenType) {
            .ArithOp => {
                const token = l.token;
                _ = l.next();
                const rhs = try alloc.create(Expr);
                rhs.* = try parseExpr(l, alloc);
                const op: ArithExpr = switch (token) {
                    .TokenProd => .{ .prod = .{ .lhs = name_expr, .rhs = rhs } },
                    .TokenMinus => .{ .minus = .{ .lhs = name_expr, .rhs = rhs } },
                    else => panic("not implemented for {}", .{token}),
                };
                return .{ .arith = op };
            },
            .BoolOp => {
                const token = l.token;
                _ = l.next();
                const rhs = try alloc.create(Expr);
                rhs.* = try parseExpr(l, alloc);
                const op: BoolExpr = switch (token) {
                    .TokenEql => .{ .eql = .{ .lhs = name_expr, .rhs = rhs } },
                    else => panic("token : {}", .{token}),
                };
                return .{ .bool_ = op };
            },
            else => panic("tokentype not implemented", .{}),
        }
        return name_expr.*;
    }

    fn parseBeginWithInt(l: *Lexer, alloc: Allocator) !Expr {
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
        } else if (l.token == .TokenMinus) {
            _ = l.next();
            const rhs = try alloc.create(Expr);
            rhs.* = try parseExpr(l, alloc);
            return .{ .arith = .{ .minus = .{ .lhs = name_expr, .rhs = rhs } } };
        }
        return .{ .arith = .{ .constant = value } };
    }

    fn parseExpr(l: *Lexer, alloc: Allocator) error{OutOfMemory}!Expr {
        switch (l.token) {
            .TokenLet => {
                _ = l.next();
                return parseFnDef(l, alloc);
            },
            .TokenIf => {
                _ = l.next();
                return parseIf(l, alloc);
            },
            .TokenId => {
                return parseBeginWithId(l, alloc);
            },
            .TokenInt => {
                return parseBeginWithInt(l, alloc);
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
        eval.* = try parseExpr(l, alloc);
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
    tokenType: TokenType,
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
            .tokenType = .None,
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

    fn setToken(l: *Lexer, token: TokenKind) void {
        switch (token) {
            .TokenMinus, .TokenProd => |t| {
                l.token = t;
                l.tokenType = .ArithOp;
            },
            .TokenEql => |t| {
                l.token = t;
                l.tokenType = .BoolOp;
            },
            .TokenElse, .TokenIf, .TokenFn, .TokenThen, .TokenArrow, .TokenLet, .TokenSelfFn => |t| {
                l.token = t;
                l.tokenType = .Keyword;
            },
            .TokenOParen, .TokenCParen => |t| {
                l.token = t;
                l.tokenType = .Paren;
            },
            .TokenAssign, .TokenComma => |t| {
                l.token = t;
                l.tokenType = .Other;
            },
            .TokenId, .TokenInt => |t| {
                l.token = t;
                l.tokenType = .Primary;
            },
            else => |t| panic("setToken not implemented for {}", .{t}),
        }
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
                    l.setToken(.TokenEql);
                    return true;
                }
                l.setToken(.TokenAssign);
                return true;
            },
            '-' => {
                l.clearAppendSymbol(x);
                const n_char = l.current_char();
                if (n_char == '>') {
                    _ = l.next_char();
                    l.name.appendAssumeCapacity(n_char.?);
                    l.setToken(.TokenArrow);
                    return true;
                }
                l.setToken(.TokenMinus);
                return true;
            },
            '(' => {
                l.clearAppendSymbol(x);
                l.setToken(.TokenOParen);
                return true;
            },
            ')' => {
                l.clearAppendSymbol(x);
                l.setToken(.TokenCParen);
                return true;
            },
            '*' => {
                l.clearAppendSymbol(x);
                l.setToken(.TokenProd);
                return true;
            },
            ',' => {
                l.clearAppendSymbol(x);
                l.setToken(.TokenComma);
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
                l.setToken(.TokenLet);
                return true;
            } else if (eql("if", l.name.items)) {
                l.setToken(.TokenIf);
                return true;
            } else if (eql("self_fn", l.name.items)) {
                l.setToken(.TokenSelfFn);
                return true;
            } else if (eql("fn", l.name.items)) {
                l.setToken(.TokenFn);
                return true;
            } else if (eql("then", l.name.items)) {
                l.setToken(.TokenThen);
                return true;
            } else if (eql("else", l.name.items)) {
                l.setToken(.TokenElse);
                return true;
            } else if (std.ascii.isDigit(l.name.items[0])) {
                const number = std.fmt.parseInt(i32, l.name.items, 10) catch {
                    std.debug.panic("Expected number, found: {s}", .{l.name.items});
                };
                l.integer_value = number;
                l.setToken(.TokenInt);
                return true;
            } else {
                l.setToken(.TokenId);
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
    BoolOp,
    CmpOp,
    Primary,
    Paren,
    Keyword,
    Other,
    None,
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
