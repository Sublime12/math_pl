const std = @import("std");

const expression_pkg = @import("expression.zig");

const eql = std.ascii.eqlIgnoreCase;
const panic = std.debug.panic;
const print = std.debug.print;

const expectStrings = std.testing.expectEqualStrings;
const expectEqual = std.testing.expectEqual;

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
    file_path: []const u8,
    content: []const u8,
    token: TokenKind,
    tokenType: TokenType,
    integer_value: ?i32,
    bool_value: ?bool,
    cursor: Cursor,
    name: SliceId,

    pub fn init(content: []const u8, file_path: []const u8) Lexer {
        return .{
            .file_path = file_path,
            .content = content,
            .token = .none,
            .cursor = .empty,
            .name = .empty,
            .integer_value = null,
            .bool_value = null,
            .tokenType = .none,
        };
    }

    pub fn eat(l: *Lexer, token: TokenKind) void {
        l.expect(token);
        l.nexti();
    }

    fn current_line(l: *Lexer) []const u8 {
        var begin: usize = l.cursor.pos;
        var end: usize = l.cursor.pos;

        while (begin > 0 and l.content[begin] != '\n') begin -= 1;
        while (end < l.content.len and l.content[end] != '\n') end += 1;

        return l.content[begin..end];
    }

    pub fn expect(l: *Lexer, expected: TokenKind) void {
        const GREEN_TAG = "\x1b[32m";
        const RED_TAG = "\x1b[31m";
        const END_TAG = "\x1b[0m";
        if (l.token != expected) {
            const panic_line = l.current_line();
            std.debug.print("\n" ++ GREEN_TAG ++ "{s}:{}:{}" ++ END_TAG ++ " expected this `{s}`, found: `{s}` in line\n{s}\n", .{
                l.file_path,
                l.cursor.row + 1,
                l.cursor.col,
                expected.getStrRepresention(),
                l.name.asStr(l.content),
                panic_line,
            });

            for (0..l.cursor.col - 1) |_| {
                std.debug.print(" ", .{});
            }
            std.debug.print(RED_TAG ++ "^" ++ END_TAG ++ "\n", .{});

            std.process.exit(1);
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
            .minus, .prod, .plus => |t| {
                l.token = t;
                l.tokenType = .arith_op;
            },
            .eql => |t| {
                l.token = t;
                l.tokenType = .bool_op;
            },
            .else_, .if_, .struct_, .fn_, .then, .arrow, .let, .self_fn, .bind, .in => |t| {
                l.token = t;
                l.tokenType = .keyword;
            },
            .oparen, .cparen, .obrace, .cbrace => |t| {
                l.token = t;
                l.tokenType = .paren;
            },
            .assign, .comma, .dot, .semicolon, .none, .at, .end => |t| {
                l.token = t;
                l.tokenType = .other;
            },
            .id, .int, .bool_, .str => |t| {
                l.token = t;
                l.tokenType = .primary;
            },
            // else => |t| panic("setToken not implemented for {}", .{t}),
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
            l.token = .end;
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
                    l.setToken(.eql);
                    return true;
                }
                l.setToken(.assign);
                return true;
            },
            '-' => {
                l.clearAppendSymbol(x);
                const n_char = l.current_char();
                if (n_char == '>') {
                    _ = l.next_char();
                    l.name.extend();
                    l.setToken(.arrow);
                    return true;
                }
                l.setToken(.minus);
                return true;
            },
            '(' => {
                l.clearAppendSymbol(x);
                l.setToken(.oparen);
                return true;
            },
            ')' => {
                l.clearAppendSymbol(x);
                l.setToken(.cparen);
                return true;
            },
            '{' => {
                l.clearAppendSymbol(x);
                l.setToken(.obrace);
                return true;
            },
            '}' => {
                l.clearAppendSymbol(x);
                l.setToken(.cbrace);
                return true;
            },
            '*' => {
                l.clearAppendSymbol(x);
                l.setToken(.prod);
                return true;
            },
            '+' => {
                l.clearAppendSymbol(x);
                l.setToken(.plus);
                return true;
            },
            ',' => {
                l.clearAppendSymbol(x);
                l.setToken(.comma);
                return true;
            },
            '.' => {
                l.clearAppendSymbol(x);
                l.setToken(.dot);
                return true;
            },
            ';' => {
                l.clearAppendSymbol(x);
                l.setToken(.semicolon);
                return true;
            },
            '@' => {
                l.clearAppendSymbol(x);
                l.setToken(.at);
                return true;
            },
            '"' => {
                const nb = l.countDComma();
                // print("comma count: {}\n", .{nb});
                l.name.clear(l.cursor.pos - 1);
                // l.name.extend();

                l.lexString(nb);
                l.setToken(.str);
                return true;
                // panic("unimplemented str token found", .{});
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
                l.setToken(.let);
                return true;
            } else if (eql("if", l.name.asStr(l.content))) {
                l.setToken(.if_);
                return true;
            } else if (eql("bind", l.name.asStr(l.content))) {
                l.setToken(.bind);
                return true;
            } else if (eql("in", l.name.asStr(l.content))) {
                l.setToken(.in);
                return true;
            } else if (eql("self_fn", l.name.asStr(l.content))) {
                l.setToken(.self_fn);
                return true;
            } else if (eql("fn", l.name.asStr(l.content))) {
                l.setToken(.fn_);
                return true;
            } else if (eql("then", l.name.asStr(l.content))) {
                l.setToken(.then);
                return true;
            } else if (eql("else", l.name.asStr(l.content))) {
                l.setToken(.else_);
                return true;
            } else if (eql("struct", l.name.asStr(l.content))) {
                l.setToken(.struct_);
                return true;
            } else if (eql("true", l.name.asStr(l.content))) {
                l.setToken(.bool_);
                l.bool_value = true;
                return true;
            } else if (eql("false", l.name.asStr(l.content))) {
                l.setToken(.bool_);
                l.bool_value = false;
                return true;
            } else if (std.ascii.isDigit(l.name.asStr(l.content)[0])) {
                const number = std.fmt.parseInt(i32, l.name.asStr(l.content), 10) catch {
                    panic("Expected number, found: {s}", .{l.name.asStr(l.content)});
                };
                l.integer_value = number;
                l.setToken(.int);
                return true;
            } else {
                l.setToken(.id);
                return true;
            }
        }
        return false;
    }

    fn isSymbol(x: u8) bool {
        return std.ascii.isAlphanumeric(x) or x == '_';
    }

    fn lexString(l: *Lexer, nb_delimiter: usize) void {
        const MAX_COMMA_STR = 15;
        loop: while (true) {
            const c = l.next_char() orelse break;
            if (c == '"') {
                var count: usize = 1;
                for (0..MAX_COMMA_STR) |_| {
                    const c2 = l.current_char();
                    if (c2 == '"') {
                        count += 1;
                        _ = l.next_char();
                    } else {
                        // print("extend here???\n", .{});
                        // l.name.extend();
                        break;
                    }
                }
                // print("pos here: {}, count: {}, delimiter: {}\n", .{ l.cursor.pos, count, nb_delimiter });
                if (count != nb_delimiter) {
                    // This is not the end of the string
                    // so we account the "" as in the string
                    // print("name: {s}\n", .{l.name.asStr(l.content)});
                    for (0..count) |_| {
                        l.name.extend();
                    }
                } else {
                    l.name.extend();
                    break :loop;
                }
            } else l.name.extend();
        }
    }

    fn countDComma(l: *Lexer) usize {
        var count: usize = 1;
        while (l.next_char()) |c| {
            if (c != '"') break;
            count += 1;
        }
        return count;
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
    const Self = @This();

    // Cmp ops
    eql,
    assign,

    // Arith ops
    minus,
    plus,
    prod,

    // parentheses
    oparen,
    cparen,
    obrace,
    cbrace,

    // keywords
    arrow,
    fn_,
    else_,
    let,
    if_,
    struct_,
    self_fn,
    then,
    bind,
    in,

    // primary
    int,
    bool_,
    id,
    str,

    // others
    comma,
    dot,
    semicolon,
    at,
    none,
    end,

    pub fn getStrRepresention(token: Self) []const u8 {
        return switch (token) {
            .eql => "==",
            .assign => "=",
            .minus => "-",
            .plus => "+",
            .prod => "*",
            .oparen => "(",
            .cparen => ")",
            .obrace => "{",
            .cbrace => "}",
            .arrow => "->",
            .fn_ => "fn",
            .else_ => "else",
            .let => "let",
            .if_ => "if",
            .struct_ => "struct",
            .self_fn => "self_fn",
            .then => "then",
            .bind => "bind",
            .in => "in",
            .int => "int",
            .bool_ => "bool",
            .id => "identifier",
            .str => "str",
            .comma => ",",
            .dot => ".",
            .semicolon => ";",
            .at => "@",
            .none => "none",
            .end => "end",
        };
    }
};

const TokenType = enum {
    arith_op,
    bool_op,
    cmp_op,
    primary,
    paren,
    keyword,
    other,
    none,
};

pub const Cursor = struct {
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

test "lex string" {
    const source_code =
        //       x                  x        x    x
        \\ """"""bon "abc" x"""""" "amis "
        \\ ""a""
        \\ "a\n"
    ;
    var l = Lexer.init(source_code, "test.zig");

    l.nexti();
    try expectStrings("bon \"abc\" x", l.name.asStr(l.content));
    l.nexti();
    try expectStrings("amis ", l.name.asStr(l.content));
    l.nexti();
    try expectStrings("a", l.name.asStr(l.content));
    l.nexti();
    try expectStrings("a\\n", l.name.asStr(l.content));

    l.nexti();
    try expectEqual(.end, l.token);
}

test "lex identifiers" {
    const source_code =
        \\ variable_name x123 _secret_id
    ;
    var l = Lexer.init(source_code, "test.zig");

    l.nexti();
    try expectStrings("variable_name", l.name.asStr(l.content));
    try expectEqual(.id, l.token);

    l.nexti();
    try expectStrings("x123", l.name.asStr(l.content));
    try expectEqual(.id, l.token);

    l.nexti();
    try expectStrings("_secret_id", l.name.asStr(l.content));
    try expectEqual(.id, l.token);

    l.nexti();
    try expectEqual(.end, l.token);
}

test "lex integers" {
    const source_code =
        \\ 123 0 4567
    ;
    var l = Lexer.init(source_code, "test.zig");

    l.nexti();
    try expectEqual(123, l.integer_value);
    try expectEqual(.int, l.token);

    l.nexti();
    try expectEqual(0, l.integer_value);
    try expectEqual(.int, l.token);

    l.nexti();
    try expectStrings("4567", l.name.asStr(l.content));
    try expectEqual(4567, l.integer_value);
    try expectEqual(.int, l.token);

    l.nexti();
    try expectEqual(.end, l.token);
}

test "lex booleans" {
    const source_code =
        \\ true false
    ;
    var l = Lexer.init(source_code, "test.zig");

    l.nexti();
    try expectEqual(true, l.bool_value);
    try expectEqual(.bool_, l.token);

    l.nexti();
    try expectEqual(false, l.bool_value);
    try expectEqual(.bool_, l.token);

    l.nexti();
    try expectEqual(.end, l.token);
}

test "lex if expression" {
    const source_code =
        \\ if 1 + 3 = 7 then
        \\ print_str("" hello "world" "",)
        \\ else double(7) ;
    ;
    var l = Lexer.init(source_code, "test.zig");

    l.nexti();
    try expectStrings("if", l.name.asStr(l.content));
    try expectEqual(.if_, l.token);

    l.nexti();
    try expectStrings("1", l.name.asStr(l.content));
    try expectEqual(1, l.integer_value);
    try expectEqual(.int, l.token);

    l.nexti();
    try expectStrings("+", l.name.asStr(l.content));
    try expectEqual(.plus, l.token);

    l.nexti();
    try expectStrings("3", l.name.asStr(l.content));
    try expectEqual(3, l.integer_value);
    try expectEqual(.int, l.token);

    l.nexti();
    try expectStrings("=", l.name.asStr(l.content));
    try expectEqual(.assign, l.token);

    l.nexti();
    try expectStrings("7", l.name.asStr(l.content));
    try expectEqual(7, l.integer_value);
    try expectEqual(.int, l.token);

    l.nexti();
    try expectStrings("then", l.name.asStr(l.content));
    try expectEqual(.then, l.token);

    l.nexti();
    try expectStrings("print_str", l.name.asStr(l.content));
    try expectEqual(.id, l.token);

    l.nexti();
    try expectStrings("(", l.name.asStr(l.content));
    try expectEqual(.oparen, l.token);

    l.nexti();
    try expectStrings(" hello \"world\" ", l.name.asStr(l.content));
    try expectEqual(.str, l.token);

    l.nexti();
    try expectStrings(",", l.name.asStr(l.content));
    try expectEqual(.comma, l.token);

    l.nexti();
    try expectStrings(")", l.name.asStr(l.content));
    try expectEqual(.cparen, l.token);

    l.nexti();
    try expectStrings("else", l.name.asStr(l.content));
    try expectEqual(.else_, l.token);

    l.nexti();
    try expectStrings("double", l.name.asStr(l.content));
    try expectEqual(.id, l.token);

    l.nexti();
    try expectStrings("(", l.name.asStr(l.content));
    try expectEqual(.oparen, l.token);

    l.nexti();
    try expectStrings("7", l.name.asStr(l.content));
    try expectEqual(7, l.integer_value);
    try expectEqual(.int, l.token);

    l.nexti();
    try expectStrings(")", l.name.asStr(l.content));
    try expectEqual(.cparen, l.token);

    l.nexti();
    try expectStrings(";", l.name.asStr(l.content));
    try expectEqual(.semicolon, l.token);

    l.nexti();
    try expectEqual(.end, l.token);
}

test "lex bind and self_fn" {
    const source_code =
        \\ bind f = x;
    ;
    var l = Lexer.init(source_code, "test.zig");

    l.nexti();
    try expectStrings("bind", l.name.asStr(l.content));
    try expectEqual(.bind, l.token);

    l.nexti();
    try expectStrings("f", l.name.asStr(l.content));
    try expectEqual(.id, l.token);

    l.nexti();
    try expectStrings("=", l.name.asStr(l.content));
    try expectEqual(.assign, l.token);

    l.nexti();
    try expectStrings("x", l.name.asStr(l.content));
    try expectEqual(.id, l.token);
}

test "lex false and equality" {
    const source_code =
        \\ false == true
    ;
    var l = Lexer.init(source_code, "test.zig");

    l.nexti();
    try expectStrings("false", l.name.asStr(l.content));
    try expectEqual(false, l.bool_value);
    try expectEqual(.bool_, l.token);

    l.nexti();
    try expectStrings("==", l.name.asStr(l.content));
    try expectEqual(.eql, l.token);

    l.nexti();
    try expectStrings("true", l.name.asStr(l.content));
    try expectEqual(true, l.bool_value);
    try expectEqual(.bool_, l.token);
}

test "lex empty input and end token" {
    const source_code = "   ";
    var l = Lexer.init(source_code, "test.zig");

    l.nexti();
    try expectEqual(.end, l.token);
}

test "lex arithmetic operators and punctuation" {
    const source_code =
        \\ (1 + 2) * 3 - 4,
    ;
    var l = Lexer.init(source_code, "test.zig");

    l.nexti();
    try expectStrings("(", l.name.asStr(l.content));
    try expectEqual(.oparen, l.token);

    l.nexti();
    try expectEqual(1, l.integer_value);
    try expectEqual(.int, l.token);

    l.nexti();
    try expectStrings("+", l.name.asStr(l.content));
    try expectEqual(.plus, l.token);

    l.nexti();
    try expectEqual(2, l.integer_value);
    try expectEqual(.int, l.token);

    l.nexti();
    try expectStrings(")", l.name.asStr(l.content));
    try expectEqual(.cparen, l.token);

    l.nexti();
    try expectStrings("*", l.name.asStr(l.content));
    try expectEqual(.prod, l.token);

    l.nexti();
    try expectEqual(3, l.integer_value);
    try expectEqual(.int, l.token);

    l.nexti();
    try expectStrings("-", l.name.asStr(l.content));
    try expectEqual(.minus, l.token);

    l.nexti();
    try expectEqual(4, l.integer_value);
    try expectEqual(.int, l.token);

    l.nexti();
    try expectStrings(",", l.name.asStr(l.content));
    try expectEqual(.comma, l.token);

    l.nexti();
    try expectEqual(.end, l.token);
}

test "lex core keywords" {
    const source_code =
        \\ let fn if then else in bind @ . { } { struct @
    ;
    var l = Lexer.init(source_code, "test.zig");

    l.nexti();
    try expectStrings("let", l.name.asStr(l.content));
    try expectEqual(.let, l.token);

    l.nexti();
    try expectStrings("fn", l.name.asStr(l.content));
    try expectEqual(.fn_, l.token);

    l.nexti();
    try expectStrings("if", l.name.asStr(l.content));
    try expectEqual(.if_, l.token);

    l.nexti();
    try expectStrings("then", l.name.asStr(l.content));
    try expectEqual(.then, l.token);

    l.nexti();
    try expectStrings("else", l.name.asStr(l.content));
    try expectEqual(.else_, l.token);

    l.nexti();
    try expectStrings("in", l.name.asStr(l.content));
    try expectEqual(.in, l.token);

    l.nexti();
    try expectStrings("bind", l.name.asStr(l.content));
    try expectEqual(.bind, l.token);

    l.nexti();
    try expectStrings("@", l.name.asStr(l.content));
    try expectEqual(.at, l.token);

    l.nexti();
    try expectStrings(".", l.name.asStr(l.content));
    try expectEqual(.dot, l.token);

    l.nexti();
    try expectStrings("{", l.name.asStr(l.content));
    try expectEqual(.obrace, l.token);

    l.nexti();
    try expectStrings("}", l.name.asStr(l.content));
    try expectEqual(.cbrace, l.token);

    l.nexti();
    try expectStrings("{", l.name.asStr(l.content));
    try expectEqual(.obrace, l.token);

    l.nexti();
    try expectStrings("struct", l.name.asStr(l.content));
    try expectEqual(.struct_, l.token);

    l.nexti();
    try expectStrings("@", l.name.asStr(l.content));
    try expectEqual(.at, l.token);

    l.nexti();
    try expectEqual(.end, l.token);
}
