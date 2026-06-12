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
const semAnal = eval_pkg.semAnal;
const expect = std.testing.expectEqual;

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    const args = try std.process.argsAlloc(alloc);
    assert(args.len == 2);

    const file_path = args[1];
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const MAX_SIZE = 1024 * 1024;

    const source_code = try file.readToEndAlloc(alloc, MAX_SIZE);
    defer alloc.free(source_code);

    var lexer = Lexer.init(source_code, file_path);

    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();

    var local_vars: Vars = .init(alloc);
    defer local_vars.deinit();

    const ctx = try buildContext(expr, alloc, source_code, file_path);
    semAnal(expr, ctx);

    _ = eval(expr, ctx, local_vars);
    print("\n", .{});
}

test {
    std.testing.refAllDecls(@This());
}
