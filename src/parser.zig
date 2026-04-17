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

    fn parseExpr(l: *Lexer, alloc: Allocator) !Expr {
        if (l.token == .TokenLet) {
            // return a function
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
        } else if (l.token == .TokenIf) {
            _ = l.next();
            const bool_expr = try alloc.create(Expr);
            bool_expr.* = parseBool(l, alloc);
        }
        unreachable;
    }

    fn parseBool(l: *Lexer, alloc: Allocator) Expr {
        _ = l;
        _ = alloc;
        return .{ .bool_ = .{ .constant = 0 } };
    }
};

pub const Lexer = struct {
    content: []const u8,
    token: TokenKind,
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
        };
    }

    pub fn expect(l: *Lexer, expected: TokenKind) void {
        if (l.token != expected) {
            panic("expected this {}, found this {} at {}:{}", .{ expected, l.token, l.cursor.row, l.cursor.col });
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
                l.name.clearRetainingCapacity();
                l.name.appendAssumeCapacity(x);
                const n_char = l.current_char();
                if (n_char == '=') {
                    _ = l.next_char();
                    l.name.appendAssumeCapacity(n_char.?);
                    l.token = .TokenEql;
                    return true;
                }
                l.token = .TokenAssign;
                return true;
            },
            '-' => {
                l.name.clearRetainingCapacity();
                l.name.appendAssumeCapacity(x);
                const n_char = l.current_char();
                if (n_char == '>') {
                    _ = l.next_char();
                    l.name.appendAssumeCapacity(n_char.?);
                    l.token = .TokenArrow;
                    return true;
                }
                l.token = .TokenMinus;
                return true;
            },
            '(' => {
                l.name.clearRetainingCapacity();
                l.name.appendAssumeCapacity(x);
                l.token = .TokenOParen;
                return true;
            },
            ')' => {
                l.name.clearRetainingCapacity();
                l.name.appendAssumeCapacity(x);
                l.token = .TokenCParen;
                return true;
            },
            '*' => {
                l.name.clearRetainingCapacity();
                l.name.appendAssumeCapacity(x);
                l.token = .TokenProd;
                return true;
            },
            else => {},
        }

        if (isSymbol(x)) {
            l.name.clearRetainingCapacity();
            l.name.appendAssumeCapacity(x);
            while (l.current_char()) |c| {
                if (!isSymbol(c)) break;
                l.name.appendAssumeCapacity(c);
                _ = l.next_char();
            }

            // std.debug.print("XXXXXXX: {s}\n", .{l.name.items});
            if (eql("let", l.name.items)) {
                l.token = .TokenLet;
                return true;
            } else if (eql("if", l.name.items)) {
                l.token = .TokenIf;
                return true;
            } else if (eql("self_fn", l.name.items)) {
                l.token = .TokenSelfFn;
                return true;
            } else if (eql("fn", l.name.items)) {
                l.token = .TokenFn;
                return true;
            } else if (eql("then", l.name.items)) {
                l.token = .TokenThen;
                return true;
            } else if (eql("else", l.name.items)) {
                l.token = .TokenElse;
                return true;
            } else if (std.ascii.isDigit(l.name.items[0])) {
                const number = std.fmt.parseInt(i32, l.name.items, 10) catch {
                    std.debug.panic("Expected number, found: {s}", .{l.name.items});
                };
                l.integer_value = number;
                l.token = .TokenInt;
                return true;
            } else {
                l.token = .TokenId;
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
    TokenLet,
    TokenId,
    TokenIf,
    TokenEql,
    TokenAssign,
    TokenSelfFn,
    TokenThen,
    TokenNone,
    TokenOParen,
    TokenCParen,
    TokenArrow,
    TokenMinus,
    TokenProd,
    TokenFn,
    TokenElse,
    TokenInt,
    TokenEnd,
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
