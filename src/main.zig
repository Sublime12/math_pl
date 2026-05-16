const std = @import("std");
const parser_pkg = @import("parser.zig");
const lexer_pkg = @import("lexer.zig");
const expression_pkg = @import("expression.zig");
const eval_pkg = @import("eval.zig");

const Lexer = lexer_pkg.Lexer;
const FnExpr = expression_pkg.FnExpr;
const BoolExpr = expression_pkg.BoolExpr;
const Expr = expression_pkg.Expr;
const IfExpr = expression_pkg.IfExpr;
const Parser = parser_pkg.Parser;
const Vars = eval_pkg.Vars;

const expect = std.testing.expectEqual;
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
    // print(ascii_code), print the char corresponding to that ascii code
    const source_code =
        // \\ print(98 + (if 2 == 2 then (0 - 1) else (1)), );
        \\    let double = fn n -> n * 2 ;
        \\    let x = fn n -> if n + 1 - 3 == (2 + 7 + n) then 5 else n * 2 ;
        \\    if 1 + a - 7 + 1 + 2 == 0
        \\    then 1
        \\    else 143 + double(if 3 == 2 then 0 else 9,) * 3 + (if b then 3 else c) ;
    ;

    var lexer = Lexer.init(source_code);

    while (lexer.next()) {
        std.debug.print("Token: {t:<15} value: {s:<20}, type: {t:<15}\n", .{
            lexer.token,
            if (lexer.token != .TokenEnd) lexer.name.asStr(lexer.content) else "$$",
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

    var it = ctx.funs.iterator();

    while (it.next()) |fn_expr| {
        const name = fn_expr.key_ptr.*;
        std.debug.print("fn {s}\n", .{name});
    }

    const new_expr = eval(expr, ctx, local_vars);
    std.debug.print("new expr: \n", .{});
    new_expr.print();
    std.debug.print("\n", .{});
    // //
    // std.debug.print("new expr: ", .{});
    // new_expr.print();
    // std.debug.print("\n", .{});
}

test "simple fn expression" {
    // For now use an arena alloc because we don't free memory
    const backed_alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(backed_alloc);
    defer arena.deinit();
    const alloc = arena.allocator();
    const source_code =
        \\ print(97, );
    ;
    var lexer = Lexer.init(source_code);
    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();
    try expect(.list, expr.tag());
    const fn_call = expr.list.items[0];
    try expect(.fn_call, fn_call.tag());

    const args = fn_call.fn_call.args;
    try expect(1, args.items.len);
    const arg = args.items[0];
    try expect(.arith, arg.tag());
    try expect(.constant, arg.arith.tag());
    try expect(97, arg.arith.constant);
}
