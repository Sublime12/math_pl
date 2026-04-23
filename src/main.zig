const std = @import("std");
const parser_pkg = @import("parser.zig");
const expression_pkg = @import("expression.zig");
const eval_pkg = @import("eval.zig");

const Lexer = parser_pkg.Lexer;
const FnExpr = expression_pkg.FnExpr;
const BoolExpr = expression_pkg.BoolExpr;
const Expr = expression_pkg.Expr;
const IfExpr = expression_pkg.IfExpr;
const Parser = parser_pkg.Parser;
const Vars = eval_pkg.Vars;

const eql = std.ascii.eqlIgnoreCase;
const eval = eval_pkg.eval;

pub fn main() !void {
    // const source_code =
    //     \\let fact = fn n ->
    //     \\    if (n +  1== 2 * 1 - 3 )
    //     \\    then 1
    //     \\    else n * self_fn (n - 12 * 3 + 8, )
    // ;

    const source_code =
        \\    if (3 + a) == 2 * 1 - 3
        \\    then 1
        \\    else 6 * 3 + (if b then 3 else (c - 15))
    ;

    // const source_code = "24 ==  1 * 2 * 3 * 4";
    var buffer: [150]u8 = undefined;

    const tokenStr = std.ArrayList(u8).initBuffer(&buffer);

    var lexer = Lexer.init(source_code, tokenStr);

    while (lexer.next()) {
        std.debug.print("Token: {t:<15} value: {s:<20}, type: {t:<15}\n", .{
            lexer.token,
            if (lexer.token != .TokenEnd) lexer.name.items else "$$",
            lexer.tokenType,
        });
        if (lexer.token == .TokenEnd) break;
    }

    const alloc = std.heap.page_allocator;
    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();

    expr.print();
    std.debug.print("\n", .{});

    var local_vars: Vars = .init(alloc);
    defer local_vars.deinit();

    try local_vars.put("a", .{ .int = 5 });
    try local_vars.put("b", .{ .bool_ = true });
    try local_vars.put("c", .{ .int = 5 });

    var it = local_vars.iterator();
    while (it.next()) |value| {
        std.debug.print("key: {s}, value: {}\n", .{ value.key_ptr.*, value.value_ptr });
    }

    const new_expr = eval(expr, local_vars);
    //
    std.debug.print("new expr: ", .{});
    new_expr.print();
    std.debug.print("\n", .{});
    // var args = std.ArrayList([]const u8).empty;
    // try args.append(allocator, "a");
    // try args.append(allocator, "b");
    // try args.append(allocator, "c");
    //
    // const simple_fn_expr = FnExpr.init("simple_fn_expr", args, .{ .bool_ = .{ .constant = 0 } });
    // _ = simple_fn_expr;
}

test "simple fn expression" {
    const allocator = std.testing.allocator;
    var eql_expr: Expr = .{ .bool_ = .{
        .eql = .{
            .lhs = &.{ .var_ = "n" },
            .rhs = &.{ .arith = .{ .constant = 0 } },
        },
    } };
    var then: Expr = .{
        .arith = .{ .constant = 1 },
    };
    var else_: Expr = .{ .var_ = "n" };

    const if_expr: IfExpr = .{ .eval = &eql_expr, .then = &then, .else_ = &else_ };

    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);
    try args.append(allocator, "a");
    try args.append(allocator, "b");
    try args.append(allocator, "c");
    const fn_expr: FnExpr = FnExpr.init("fact", args, &.{ .if_ = if_expr });

    std.debug.print("fn fact: {}\n", .{fn_expr});
}
