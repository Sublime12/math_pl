const std = @import("std");
const parser_pkg = @import("parser.zig");
const expression_pkg = @import("expression.zig");

const Lexer = parser_pkg.Lexer;
const FnExpr = expression_pkg.FnExpr;

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
        std.debug.print("Token: {t:<15} value: {s:<20}\n", .{
            lexer.token,
            if (lexer.token != .TokenEnd) lexer.name.items else "$$",
        });
        if (lexer.token == .TokenEnd) break;
    }
    const allocator = std.heap.page_allocator;

    var args = std.ArrayList([]const u8).empty;
    try args.append(allocator, "a");
    try args.append(allocator, "b");
    try args.append(allocator, "c");

    const simple_fn_expr = FnExpr.init("simple_fn_expr", args, .{ .bool_ = .{ .constant = true } });
    _ = simple_fn_expr;
}
