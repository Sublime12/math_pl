const std = @import("std");

const expression_pkg = @import("expression.zig");

const Expr = expression_pkg.Expr;
const FnExpr = expression_pkg.FnExpr;
const ArithExpr = expression_pkg.ArithExpr;
const BoolExpr = expression_pkg.BoolExpr;
const ArgsExpr = expression_pkg.ArgsExpr;
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
        self.lexer.nexti();

        var program: std.ArrayList(Expr) = .empty;
        var i: i32 = 0;
        while (self.lexer.token != .TokenEnd) {
            std.debug.print("IIIII = {}\n", .{i});
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
        const id = l.name.toStr(l.content);
        l.nexti();
        l.expect(.TokenAssign);
        l.nexti();
        l.expect(.TokenFn);
        l.nexti();
        var args = std.ArrayList([]const u8).empty;
        while (l.token == .TokenId) {
            try args.append(alloc, l.name.toStr(l.content));
            l.nexti();
        }
        l.expect(.TokenArrow);
        l.nexti();

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
    fn parseBeginWithIdOrInt(l: *Lexer, alloc: Allocator) !Expr {
        const name = l.name.toStr(l.content);
        var next_l = l.nextl();
        var lhs = try alloc.create(Expr);
        if (l.token == .TokenId) {
            lhs.* = switch (next_l.token) {
                .TokenOParen => blk: {
                    l.nexti();
                    const expr = try parseFnCall(l, alloc, name);
                    l.expect(.TokenCParen);
                    l.nexti();
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
        }

        while (l.tokenType == .ArithOp or l.tokenType == .BoolOp) {
            const op_token = l.token;
            const op_token_type = l.tokenType;
            l.nexti();

            const rhs = try alloc.create(Expr);
            next_l = l.*;
            next_l.nexti();

            const current_name = l.name.toStr(l.content);
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
            .TokenId, .TokenInt => {
                return parseBeginWithIdOrInt(l, alloc);
            },
            .TokenSelfFn, .TokenPrint => {
                const name = l.name.toStr(l.content);
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
            .{ l.token, l.name.toStr(l.content) },
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

    pub fn isEmpty(self: Self) bool {
        return self.first == self.end;
    }

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
            .TokenElse, .TokenIf, .TokenFn, .TokenThen, .TokenArrow, .TokenLet, .TokenSelfFn, .TokenPrint => |t| {
                l.token = t;
                l.tokenType = .Keyword;
            },
            .TokenOParen, .TokenCParen => |t| {
                l.token = t;
                l.tokenType = .Paren;
            },
            .TokenAssign, .TokenComma, .TokenSemicolon => |t| {
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

    /// like next but ignore the output
    pub fn nexti(l: *Lexer) void {
        _ = l.next();
    }

    /// Return a new lexer with the token set
    /// to the element in source code
    pub fn nextl(l: Lexer) Lexer {
        var new_l = l;
        new_l.nexti();
        return new_l;
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
            ';' => {
                l.clearAppendSymbol(x);
                l.setToken(.TokenSemicolon);
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
            } else if (eql("print", l.name.toStr(l.content))) {
                l.setToken(.TokenPrint);
                return true;
            } else if (std.ascii.isDigit(l.name.toStr(l.content)[0])) {
                const number = std.fmt.parseInt(i32, l.name.toStr(l.content), 10) catch {
                    panic("Expected number, found: {s}", .{l.name.toStr(l.content)});
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
    TokenPrint,

    // primary
    TokenInt,
    TokenId,

    // others
    TokenComma,
    TokenSemicolon,
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
