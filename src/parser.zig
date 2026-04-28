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
        // const id = try alloc.dupe(u8, l.name.items);
        const id = l.name.toStr(l.content);
        _ = l.next();
        l.expect(.TokenAssign);
        _ = l.next();
        l.expect(.TokenFn);
        _ = l.next();
        var args = std.ArrayList([]const u8).empty;
        while (l.token == .TokenId) {
            // try args.append(alloc, try alloc.dupe(u8, l.name.items));
            try args.append(alloc, try alloc.dupe(u8, l.name.toStr(l.content)));
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
        const name = try alloc.dupe(u8, l.name.toStr(l.content));
        var lhs = try alloc.create(Expr);
        lhs.* = .{ .var_ = name };
        _ = l.next();

        while (l.tokenType == .ArithOp) {
            const op_token = l.token;
            _ = l.next();
            const token = l.token;
            const rhs = try alloc.create(Expr);
            rhs.* = switch (token) {
                .TokenId => .{ .var_ = try alloc.dupe(u8, l.name.toStr(l.content)) },
                .TokenInt => .{ .arith = .{ .constant = l.integer_value.? } },
                else => try parseExpr(l, alloc),
            };
            const op: ArithExpr = switch (op_token) {
                .TokenProd => .{ .prod = .{ .lhs = lhs, .rhs = rhs } },
                .TokenMinus => .{ .minus = .{ .lhs = lhs, .rhs = rhs } },
                .TokenPlus => .{ .plus = .{ .lhs = lhs, .rhs = rhs } },
                else => panic("panic bool begin with", .{}),
            };
            lhs = try alloc.create(Expr);
            lhs.* = .{ .arith = op };
            _ = l.next();
        }
        switch (l.tokenType) {
            .BoolOp => {
                const token = l.token;
                _ = l.next();
                const rhs = try alloc.create(Expr);
                rhs.* = try parseExpr(l, alloc);
                const op: BoolExpr = switch (token) {
                    .TokenEql => .{ .eql = .{ .lhs = lhs, .rhs = rhs } },
                    else => panic("token : {}", .{token}),
                };
                return .{ .bool_ = op };
            },
            else => {},
        }
        return lhs.*;
    }

    fn parseBeginWithInt(l: *Lexer, alloc: Allocator) !Expr {
        const value = l.integer_value.?;
        var lhs = try alloc.create(Expr);
        lhs.* = .{ .arith = .{ .constant = value } };
        _ = l.next();

        while (l.tokenType == .ArithOp) {
            const op_token = l.token;
            _ = l.next();
            const token = l.token;
            const rhs = try alloc.create(Expr);
            rhs.* = switch (token) {
                .TokenId => .{ .var_ = try alloc.dupe(u8, l.name.toStr(l.content)) },
                .TokenInt => .{ .arith = .{ .constant = l.integer_value.? } },
                else => try parseExpr(l, alloc),
            };
            const op: ArithExpr = switch (op_token) {
                .TokenProd => .{ .prod = .{ .lhs = lhs, .rhs = rhs } },
                .TokenMinus => .{ .minus = .{ .lhs = lhs, .rhs = rhs } },
                .TokenPlus => .{ .plus = .{ .lhs = lhs, .rhs = rhs } },
                else => panic("panic bool begin with", .{}),
            };
            lhs = try alloc.create(Expr);
            lhs.* = .{ .arith = op };
            _ = l.next();
        }
        switch (l.tokenType) {
            .BoolOp => {
                const token = l.token;
                _ = l.next();
                const rhs = try alloc.create(Expr);
                rhs.* = try parseExpr(l, alloc);
                const op: BoolExpr = switch (token) {
                    .TokenEql => .{ .eql = .{ .lhs = lhs, .rhs = rhs } },
                    else => panic("panic bool begin with", .{}),
                };
                return .{ .bool_ = op };
            },
            else => {},
        }
        return lhs.*;
    }

    fn parseBeginWithOParen(l: *Lexer, alloc: Allocator) !Expr {
        l.expect(.TokenOParen);
        _ = l.next();

        const lhs = try alloc.create(Expr);
        lhs.* = try parseExpr(l, alloc);
        l.expect(.TokenCParen);
        _ = l.next();

        switch (l.tokenType) {
            .BoolOp => {
                const token = l.token;
                _ = l.next();
                const rhs = try alloc.create(Expr);
                rhs.* = try parseExpr(l, alloc);
                const op: BoolExpr = switch (token) {
                    .TokenEql => .{ .eql = .{ .lhs = lhs, .rhs = rhs } },
                    else => panic("panic bool begin with", .{}),
                };
                return .{ .bool_ = op };
            },
            .ArithOp => {
                const token = l.token;
                _ = l.next();
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
                const name = try alloc.dupe(u8, l.name.toStr(l.content));
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
            // an open paren (not in the context of a function)
            .TokenOParen => {
                return parseBeginWithOParen(l, alloc);
            },
            else => {},
        }

        panic(
            "Panic with token {}, value: {s}",
            .{ l.token, l.name.toStr(l.content)},
        );
    }

    fn parseIf(l: *Lexer, alloc: Allocator) !Expr {
        const eval = try alloc.create(Expr);
        eval.* = try parseExpr(l, alloc);
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

// A slice indexing where is the id
// in the content 
const SliceId = struct {
    const Self = @This();
    pub const empty: Self = .{ .first = 0, .end = 0 };
    first: usize,
    end: usize,

    pub fn toStr(self: Self, content: []const u8) []const u8 {
        return content[self.first..self.end];
    }

    pub fn clear(self: *Self, pos: usize) void {
        self.first = pos;
        self.end = pos;
    }

    pub fn isEmpty(self: Self) bool { return self.first == self.end; }

    pub fn extend(self: *Self) void {
        self.end += 1;
    }
};

pub const Lexer = struct {
    content: []const u8,
    token: TokenKind,
    tokenType: TokenType,
    integer_value: ?i32,
    cursor: Cursor,
    name: SliceId,

    pub fn init(content: []const u8) Lexer {
        return .{
            .content = content,
            .token = .TokenNone,
            .cursor = .empty,
            .name = .empty,
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
                l.name.toStr(l.content),
                l.integer_value,
            });
        }
    }

    fn clearAppendSymbol(l: *Lexer, x: u8) void {
        _ = x;
        // l.name.clearRetainingCapacity();
        // cursor.pos always return the position after the last
        // character that was processed
        l.name.clear(l.cursor.pos - 1);
        l.name.extend();
    }

    fn setToken(l: *Lexer, token: TokenKind) void {
        switch (token) {
            .TokenMinus, .TokenProd, .TokenPlus => |t| {
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
                    l.name.extend();
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
                    l.name.extend();
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
            '+' => {
                l.clearAppendSymbol(x);
                l.setToken(.TokenPlus);
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
                l.name.extend();
                _ = l.next_char();
            }

            if (eql("let", l.name.toStr(l.content))) {
                l.setToken(.TokenLet);
                return true;
            } else if (eql("if", l.name.toStr(l.content))) {
                l.setToken(.TokenIf);
                return true;
            } else if (eql("self_fn", l.name.toStr(l.content))) {
                l.setToken(.TokenSelfFn);
                return true;
            } else if (eql("fn", l.name.toStr(l.content))) {
                l.setToken(.TokenFn);
                return true;
            } else if (eql("then", l.name.toStr(l.content))) {
                l.setToken(.TokenThen);
                return true;
            } else if (eql("else", l.name.toStr(l.content))) {
                l.setToken(.TokenElse);
                return true;
            } else if (std.ascii.isDigit(l.name.toStr(l.content)[0])) {
                const number = std.fmt.parseInt(i32, l.name.toStr(l.content), 10) catch {
                    std.debug.panic("Expected number, found: {s}", .{l.name.toStr(l.content)});
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
    TokenPlus,
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
