const std = @import("std");

const expression_pkg = @import("expression.zig");

const eql = std.ascii.eqlIgnoreCase;
const panic = std.debug.panic;

// A slice indexing where is the id
// in the content
const SliceId = struct {
    const Self = @This();
    pub const empty: Self = .{ .first = 0, .end = 0 };
    first: usize,
    end: usize,

    pub fn asStr(self: Self, content: []const u8) []const u8 {
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
    bool_value: ?bool,
    cursor: Cursor,
    name: SliceId,

    pub fn init(content: []const u8) Lexer {
        return .{
            .content = content,
            .token = .TokenNone,
            .cursor = .empty,
            .name = .empty,
            .integer_value = null,
            .bool_value = null,
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
                l.name.asStr(l.content),
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
            .TokenId, .TokenInt, .TokenBool => |t| {
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

            if (eql("let", l.name.asStr(l.content))) {
                l.setToken(.TokenLet);
                return true;
            } else if (eql("if", l.name.asStr(l.content))) {
                l.setToken(.TokenIf);
                return true;
            } else if (eql("self_fn", l.name.asStr(l.content))) {
                l.setToken(.TokenSelfFn);
                return true;
            } else if (eql("fn", l.name.asStr(l.content))) {
                l.setToken(.TokenFn);
                return true;
            } else if (eql("then", l.name.asStr(l.content))) {
                l.setToken(.TokenThen);
                return true;
            } else if (eql("else", l.name.asStr(l.content))) {
                l.setToken(.TokenElse);
                return true;
            } else if (eql("print", l.name.asStr(l.content))) {
                l.setToken(.TokenPrint);
                return true;
            } else if (eql("true", l.name.asStr(l.content))) {
                l.setToken(.TokenBool);
                l.bool_value = true;
                return true;
            } else if (eql("false", l.name.asStr(l.content))) {
                l.setToken(.TokenBool);
                l.bool_value = false;
                return true;
            } else if (std.ascii.isDigit(l.name.asStr(l.content)[0])) {
                const number = std.fmt.parseInt(i32, l.name.asStr(l.content), 10) catch {
                    panic("Expected number, found: {s}", .{l.name.asStr(l.content)});
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
    TokenBool,
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
