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
const buildContext = eval_pkg.buildContext;

pub fn main() !void {
    // const source_code =
    //     \\let fact = fn n ->
    //     \\    if (n +  1== 2 * 1 - 3 )
    //     \\    then 1
    //     \\    else n * self_fn (n - 12 * 3 + 8, )
    // ;

    // The main program is going to be all expressions that are
    // not function declaration in the global scope
    const source_code =
        \\    if 1 + a - 7 + 1 + 2
        \\    then 1
        \\    else 143 + double(6, if i then 0 else 9) * 3 + (if b then 3 else c) ;
        \\    let double = fn n -> n * 2 ;
        \\    let x = fn n -> if n + 1 - 3 == (2 + 7 + n) then 5 else n * 2 ;
    ;

    var lexer = Lexer.init(source_code);

    while (lexer.next()) {
        std.debug.print("Token: {t:<15} value: {s:<20}, type: {t:<15}\n", .{
            lexer.token,
            if (lexer.token != .TokenEnd) lexer.name.toStr(lexer.content) else "$$",
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

    // var it = local_vars.iterator();
    // while (it.next()) |value| {
    //     std.debug.print("key: {s}, value: {}\n", .{ value.key_ptr.*, value.value_ptr });
    // }
    const ctx = try buildContext(expr, alloc);
    const new_expr = eval(expr, ctx, local_vars);
    std.debug.print("new expr: \n", .{});
    new_expr.print();
    // //
    // std.debug.print("new expr: ", .{});
    // new_expr.print();
    // std.debug.print("\n", .{});
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
