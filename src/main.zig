const std = @import("std");
const parser_pkg = @import("parser.zig");
const lexer_pkg = @import("lexer.zig");
const expression_pkg = @import("expression.zig");
const eval_pkg = @import("eval.zig");

const ArenaAllocator = std.heap.ArenaAllocator;

const Lexer = lexer_pkg.Lexer;
const FnExpr = expression_pkg.FnExpr;
const BoolExpr = expression_pkg.BoolExpr;
const Expr = expression_pkg.Expr;
const IfExpr = expression_pkg.IfExpr;
const Parser = parser_pkg.Parser;
const Vars = eval_pkg.Vars;

const assert = std.debug.assert;
const print = std.debug.print;
const eql = std.ascii.eqlIgnoreCase;
const eval = eval_pkg.eval;
const buildContext = eval_pkg.buildContext;
const expect = std.testing.expectEqual;

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

    const alloc = std.heap.page_allocator;
    const args = try std.process.argsAlloc(alloc);
    assert(args.len == 2);

    const file_path = args[1];
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const MAX_SIZE = 1024 * 1024;

    const source_code = try file.readToEndAlloc(alloc, MAX_SIZE);
    defer alloc.free(source_code);

    var lexer = Lexer.init(source_code);

    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();

    var local_vars: Vars = .init(alloc);
    defer local_vars.deinit();

    const ctx = try buildContext(expr, alloc);

    _ = eval(expr, ctx, local_vars);
    print("\n", .{});
}

fn arena_alloc() ArenaAllocator {
    const backed_alloc = std.testing.allocator;
    return std.heap.ArenaAllocator.init(backed_alloc);
}

test "simple fn expression" {
    // For now use an arena alloc because we don't free memory
    var arena = arena_alloc();
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

test "print string" {
    // For now use an arena alloc because we don't free memory
    var arena = arena_alloc();
    defer arena.deinit();
    const alloc = arena.allocator();
    const source_code =
        \\ print_str("bonjour"+"papa",);
    ;
    var lexer = Lexer.init(source_code);

    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();
    try expect(.list, expr.tag());
}
