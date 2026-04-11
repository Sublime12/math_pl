const std = @import("std");
const math_pl = @import("math_pl");

const eql = std.ascii.eqlIgnoreCase;

pub fn main() !void {
    const source_code =
        \\let fact = fn n ->
        \\    if n == 0
        \\    then 1
        \\    else n * self_fn (n - 1)
    ;
    var buffer: [150]u8 = undefined;

    const tokenStr = std.ArrayList(u8).initBuffer(&buffer);

    var lexer = Lexer.init(source_code, tokenStr);

    while (lexer.next()) {
        std.debug.print("Token: {}, value: {s}\n", .{ lexer.token, lexer.name.items });
        if (lexer.token == .TokenEnd) break;
    }
}

const Lexer = struct {
    content: []const u8,
    token: TokenKind,
    cursor: Cursor,
    name: std.ArrayList(u8),

    pub fn init(content: []const u8, emptyTokenStr: std.ArrayList(u8)) Lexer {
        return .{
            .content = content,
            .token = .TokenNone,
            .cursor = .Empty,
            .name = emptyTokenStr,
        };
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
                if (l.current_char()) |n_char| {
                    if (n_char == '=') {
                        _ = l.next_char();
                        l.name.clearRetainingCapacity();
                        l.name.appendAssumeCapacity(x);
                        l.name.appendAssumeCapacity(n_char);
                        l.token = .TokenEql;
                        return true;
                    }
                }
                l.name.clearRetainingCapacity();
                l.name.appendAssumeCapacity(x);
                l.token = .TokenAssign;
                return true;
            },
            '-' => {
                if (l.current_char()) |n_char| {
                    if (n_char == '>') {
                        _ = l.next_char();
                        l.name.clearRetainingCapacity();
                        l.name.appendAssumeCapacity(x);
                        l.name.appendAssumeCapacity(n_char);
                        l.token = .TokenArrow;
                        return true;
                    }
                }
                l.name.clearRetainingCapacity();
                l.name.appendAssumeCapacity(x);
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
            else => {},
        }

        if (isSymbol(x)) {
            l.name.clearRetainingCapacity();
            l.name.appendAssumeCapacity(x);
            while (l.current_char()) |c| {
                if (!std.ascii.isAlphanumeric(c)) break;
                l.name.appendAssumeCapacity(c);
                _ = l.next_char();
            }

            if (eql("let", l.name.items)) {
                l.token = .TokenLet;
                return true;
            } else if (eql("if", l.name.items)) {
                l.token = .TokenIf;
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

    pub const Empty: Self = .{
        .pos = 0,
        .bol = 0,
        .col = 0,
        .row = 0,
    };
};
