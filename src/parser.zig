const std = @import("std");

const expression_pkg = @import("expression.zig");
const lexer_pkg = @import("lexer.zig");

const Expr = expression_pkg.Expr;
const FnExpr = expression_pkg.FnExpr;
const ArithExpr = expression_pkg.ArithExpr;
const BoolExpr = expression_pkg.BoolExpr;
const ArgsExpr = expression_pkg.ArgsExpr;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const Lexer = lexer_pkg.Lexer;

const panic = std.debug.panic;
const expect = std.testing.expectEqual;
const expectStrings = std.testing.expectEqualStrings;

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
        self.lexer.nexti();

        var program: std.ArrayList(Expr) = .empty;
        var i: i32 = 0;
        while (self.lexer.token != .end) {
            const expr = try parseExpr(self.lexer, self.alloc);
            self.lexer.expect(.semicolon);
            self.lexer.nexti();
            try program.append(self.alloc, expr);
            i += 1;
        }
        return .{ .list = program };
    }

    fn parseFnDef(l: *Lexer, alloc: Allocator) !Expr {
        l.expect(.id);
        const id = l.name.asStr(l.content);
        l.nexti();
        l.expect(.assign);
        l.nexti();
        l.expect(.fn_);
        l.nexti();
        var args = std.ArrayList([]const u8).empty;
        while (l.token == .id) {
            try args.append(alloc, l.name.asStr(l.content));
            l.nexti();
        }
        l.expect(.arrow);
        l.nexti();

        const body = try alloc.create(Expr);
        body.* = try parseExpr(l, alloc);

        const fn_expr: FnExpr = .{
            .name = id,
            .args = args,
            .body = .{ .fn_std = .{ .body = body } },
        };
        return .{ .fn_def = fn_expr };
    }

    /// can be an arith expr a + 1 - 3
    /// or a bool expr a = 1
    /// or a function call a(b, c, d)
    fn parseBeginWithIdOrInt(l: *Lexer, alloc: Allocator) !Expr {
        const name = l.name.asStr(l.content);
        var next_l = l.nextl();
        var lhs = try alloc.create(Expr);
        if (l.token == .id) {
            lhs.* = switch (next_l.token) {
                .oparen => blk: {
                    l.nexti();
                    const expr = try parseFnCall(l, alloc, name);
                    break :blk expr;
                },
                else => blk: {
                    l.nexti();
                    break :blk .{ .var_ = name };
                },
            };
        } else if (l.token == .int) {
            lhs.* = .{ .arith = .{ .constant = l.integer_value.? } };
            l.nexti();
        } else if (l.token == .str) {
            lhs.* = .{ .arith = .{ .str = l.name.asStr(l.content) } };
            l.nexti();
        } else if (l.tokenType == .primary) panic("Must be identifier, integer or string", .{});

        while (l.tokenType == .arith_op or l.tokenType == .bool_op) {
            const op_token = l.token;
            const op_token_type = l.tokenType;
            l.nexti();

            const rhs = try alloc.create(Expr);
            next_l = l.*;
            next_l.nexti();

            const current_name = l.name.asStr(l.content);
            rhs.* = switch (l.token) {
                .id => if (next_l.token == .oparen) blk: {
                    l.nexti();
                    const expr = try parseFnCall(l, alloc, current_name);
                    break :blk expr;
                } else blk: {
                    l.nexti();
                    break :blk .{ .var_ = current_name };
                },
                .int => blk: {
                    l.nexti();
                    break :blk .{ .arith = .{ .constant = l.integer_value.? } };
                },
                .str => blk: {
                    l.nexti();
                    break :blk .{ .arith = .{ .str = current_name } };
                },
                else => blk: {
                    const expr = try parseExpr(l, alloc);
                    break :blk expr;
                },
            };

            if (op_token_type == .arith_op) {
                const op: ArithExpr = switch (op_token) {
                    .prod => .{ .prod = .{ .lhs = lhs, .rhs = rhs } },
                    .plus => .{ .plus = .{ .lhs = lhs, .rhs = rhs } },
                    .minus => .{ .minus = .{ .lhs = lhs, .rhs = rhs } },
                    else => unreachable,
                };

                lhs = try alloc.create(Expr);
                lhs.* = .{ .arith = op };
            } else if (op_token_type == .bool_op) {
                const op: BoolExpr = switch (op_token) {
                    .eql => .{ .eql = .{ .lhs = lhs, .rhs = rhs } },
                    else => panic("not catch for {}", .{op_token}),
                };

                lhs = try alloc.create(Expr);
                lhs.* = .{ .bool_ = op };
            }
        }

        return lhs.*;
    }

    fn parseFnCall(l: *Lexer, alloc: Allocator, name: []const u8) !Expr {
        l.expect(.oparen);
        l.nexti();
        const args = try parseArgs(l, alloc);
        l.expect(.cparen);
        l.nexti();
        const lhs: Expr = .{ .fn_call = .{ .name = name, .args = args } };
        return lhs;
    }

    pub fn parseArgs(l: *Lexer, alloc: Allocator) !ArgsExpr {
        var args: std.ArrayList(Expr) = .empty;
        while (l.token != .cparen) {
            const arg = try parseExpr(l, alloc);
            try args.append(alloc, arg);
            l.expect(.comma);
            l.nexti();
        }
        return args;
    }

    fn parseBeginWithOParen(l: *Lexer, alloc: Allocator) !Expr {
        l.expect(.oparen);
        l.nexti();

        const lhs = try alloc.create(Expr);
        lhs.* = try parseExpr(l, alloc);
        const next_l = l.nextl();

        switch (next_l.tokenType) {
            .bool_op => {
                l.nexti();
                const token = l.token;
                l.nexti();
                const rhs = try alloc.create(Expr);
                rhs.* = try parseExpr(l, alloc);
                const op: BoolExpr = switch (token) {
                    .eql => .{ .eql = .{ .lhs = lhs, .rhs = rhs } },
                    else => panic("panic bool begin with", .{}),
                };
                return .{ .bool_ = op };
            },
            .arith_op => {
                l.nexti();
                const token = l.token;
                l.nexti();
                const rhs = try alloc.create(Expr);
                rhs.* = try parseExpr(l, alloc);
                const op: ArithExpr = switch (token) {
                    .prod => .{ .prod = .{ .lhs = lhs, .rhs = rhs } },
                    .minus => .{ .minus = .{ .lhs = lhs, .rhs = rhs } },
                    .plus => .{ .plus = .{ .lhs = lhs, .rhs = rhs } },
                    else => panic("panic bool begin with", .{}),
                };
                return .{ .arith = op };
            },
            else => {},
        }

        return lhs.*;
    }

    fn parseExpr(l: *Lexer, alloc: Allocator) error{OutOfMemory}!Expr {
        switch (l.token) {
            .let => {
                l.nexti();
                return parseFnDef(l, alloc);
            },
            .if_ => {
                l.nexti();
                return parseIf(l, alloc);
            },
            .id, .int, .str => {
                return parseBeginWithIdOrInt(l, alloc);
            },
            .self_fn => {
                const name = l.name.asStr(l.content);
                l.nexti();
                l.expect(.oparen);
                l.nexti();
                const args = try parseArgs(l, alloc);
                l.expect(.cparen);
                l.nexti();
                return .{ .fn_call = .{ .name = name, .args = args } };
            },
            // an open paren (not in the context of a function)
            .oparen => {
                const expr = parseBeginWithOParen(l, alloc);
                l.expect(.cparen);
                l.nexti();
                return expr;
            },
            .bind => {
                return parseBind(l, alloc);
            },
            .at => {
                return parseStructInstance(l, alloc);
            },
            else => {},
        }

        panic(
            "Panic with token {}, value: {s}",
            .{ l.token, l.name.asStr(l.content) },
        );
    }

    fn parseStructInstance(l: *Lexer, alloc: Allocator) !Expr {
        l.nexti();
        l.expect(.id);
        const name = l.name.asStr(l.content);
        l.nexti();

        l.expect(.obrace);
        l.nexti();
        var fields: std.StringHashMapUnmanaged(Expr) = .empty;
        while (l.token != .cbrace) {
            l.expect(.dot);
            l.nexti();

            l.expect(.id);
            const field = l.name.asStr(l.content);
            l.nexti();

            l.expect(.assign);
            l.nexti();

            const value = try parseExpr(l, alloc);
            l.expect(.comma);
            l.nexti();
            try fields.putNoClobber(alloc, field, value);
        }
        l.nexti();
        return .{ .struct_instance = .{ .name = name, .fields = fields }};
    }

    fn parseBind(l: *Lexer, alloc: Allocator) !Expr {
        l.nexti();
        l.expect(.id);
        const id = l.name.asStr(l.content);
        l.nexti();

        l.expect(.assign);
        l.nexti();
        const body = try alloc.create(Expr);
        body.* = try parseExpr(l, alloc);
        l.expect(.in);
        l.nexti();

        const closure = try alloc.create(Expr);
        closure.* = try parseExpr(l, alloc);
        return .{ .bind = .{
            .id = id,
            .body = body,
            .closure = closure,
        } };
    }

    fn parseIf(l: *Lexer, alloc: Allocator) !Expr {
        const eval = try alloc.create(Expr);
        eval.* = try parseExpr(l, alloc);
        l.expect(.then);
        l.nexti();
        const then = try alloc.create(Expr);
        then.* = try parseExpr(l, alloc);
        l.expect(.else_);
        l.nexti();
        const else_ = try alloc.create(Expr);
        else_.* = try parseExpr(l, alloc);

        return .{
            .if_ = .{
                .eval = eval,
                .then = then,
                .else_ = else_,
            },
        };
    }

    fn parseBool(l: *Lexer, alloc: Allocator) !Expr {
        if (l.token == .id) {
            const lhs = try alloc.create(Expr);
            lhs.* = try parseExpr(l, alloc);
            l.expect(.eql);
            l.nexti();
            const rhs = try alloc.create(Expr);
            rhs.* = try parseExpr(l, alloc);
            return .{
                .bool_ = .{ .eql = .{ .lhs = lhs, .rhs = rhs } },
            };
        }

        panic("Not yet implemented for functions", .{});
    }
};

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

test "parse print_str function" {
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

    try expect(1, expr.list.items.len);
    const fn_call = expr.list.items[0];
    try expect(.fn_call, fn_call.tag());
    try expectStrings("print_str", fn_call.fn_call.name);

    const args = fn_call.fn_call.args;
    try expect(1, args.items.len);
    const arg = args.items[0];
    try expect(.arith, arg.tag());
    try expect(.plus, arg.arith.tag());

    const lhs = arg.arith.plus.lhs;
    const rhs = arg.arith.plus.rhs;

    try expect(.arith, lhs.tag());
    try expect(.str, lhs.arith.tag());
    try expectStrings("bonjour", lhs.*.arith.str);

    try expect(.arith, rhs.tag());
    try expect(.str, rhs.arith.tag());
    try expectStrings("papa", rhs.*.arith.str);
}

test "parse function definition" {
    var arena = arena_alloc();
    defer arena.deinit();
    const alloc = arena.allocator();

    const source_code =
        \\ let add = fn x y -> x + y;
    ;
    var lexer = Lexer.init(source_code);
    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();

    try expect(.list, expr.tag());
    try expect(1, expr.list.items.len);

    const fn_def = expr.list.items[0];
    try expect(.fn_def, fn_def.tag());
    try expectStrings("add", fn_def.fn_def.name);
    try expect(2, fn_def.fn_def.args.items.len);
    try expectStrings("x", fn_def.fn_def.args.items[0]);
    try expectStrings("y", fn_def.fn_def.args.items[1]);

    const body = fn_def.fn_def.body.fn_std.body.*;
    try expect(.arith, body.tag());
    try expect(.plus, body.arith.tag());
}

test "parse if expression" {
    var arena = arena_alloc();
    defer arena.deinit();
    const alloc = arena.allocator();

    const source_code =
        \\ if n == 1 then "yes" else "no";
    ;
    var lexer = Lexer.init(source_code);
    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();

    try expect(.list, expr.tag());

    const if_expr = expr.list.items[0];
    try expect(.if_, if_expr.tag());

    const eval_node = if_expr.if_.eval.*;
    try expect(.bool_, eval_node.tag());
    try expect(.eql, eval_node.bool_.tag());

    const lhs = eval_node.bool_.eql.lhs;
    try expect(.var_, lhs.tag());
    try expectStrings("n", lhs.var_);

    const rhs = eval_node.bool_.eql.rhs;
    try expect(.arith, rhs.tag());
    try expect(.constant, rhs.arith.tag());
    try expect(1, rhs.arith.constant);

    const then_node = if_expr.if_.then.*;
    try expect(.arith, then_node.tag());
    try expect(.str, then_node.arith.tag());
    try expectStrings("yes", then_node.arith.str);

    const else_node = if_expr.if_.else_.*;
    try expect(.arith, else_node.tag());
    try expect(.str, else_node.arith.tag());
    try expectStrings("no", else_node.arith.str);
}

test "parse nested bind expressions" {
    var arena = arena_alloc();
    defer arena.deinit();
    const alloc = arena.allocator();

    const source_code =
        \\ let double = fn x -> x * 2;
        \\ bind n = 15 + 3 in
        \\ bind n_double = double(n, ) in
        \\ print_int(n_double,);
    ;
    var lexer = Lexer.init(source_code);
    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();

    try expect(.list, expr.tag());
    try expect(2, expr.list.items.len);

    const fn_def = expr.list.items[0];
    try expect(.fn_def, fn_def.tag());
    try expectStrings("double", fn_def.fn_def.name);

    const bind_n = expr.list.items[1];
    try expect(.bind, bind_n.tag());
    try expectStrings("n", bind_n.bind.id);

    const bind_n_body = bind_n.bind.body.*;
    try expect(.arith, bind_n_body.tag());
    try expect(.plus, bind_n_body.arith.tag());

    const bind_n_double = bind_n.bind.closure.*;
    try expect(.bind, bind_n_double.tag());
    try expectStrings("n_double", bind_n_double.bind.id);

    const bind_n_double_body = bind_n_double.bind.body.*;
    try expect(.fn_call, bind_n_double_body.tag());
    try expectStrings("double", bind_n_double_body.fn_call.name);
    try expect(1, bind_n_double_body.fn_call.args.items.len);

    const print_call = bind_n_double.bind.closure.*;
    try expect(.fn_call, print_call.tag());
    try expectStrings("print_int", print_call.fn_call.name);
    try expect(1, print_call.fn_call.args.items.len);

    const print_arg = print_call.fn_call.args.items[0];
    try expect(.var_, print_arg.tag());
    try expectStrings("n_double", print_arg.var_);
}

test "parse struct instance" {
    var arena = arena_alloc();
    defer arena.deinit();
    const alloc = arena.allocator();

    const source_code =
        \\ @Point{
        \\   .x = 2,
        \\   .y = 5,
        \\   .z = if 15 == 2 then "bonjour" else double(1 + 3 - 4,),
        \\ };
    ;
    var lexer = Lexer.init(source_code);
    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();

    try expect(.list, expr.tag());
    try expect(1, expr.list.items.len);

    const struct_expr = expr.list.items[0];
    try expect(.struct_instance, struct_expr.tag());
    try expectStrings("Point", struct_expr.struct_instance.name);
    try expect(3, struct_expr.struct_instance.fields.size);

    const field_x = struct_expr.struct_instance.fields.get("x") orelse return std.testing.expect(false);

    try expect(.arith, field_x.tag());
    try expect(.constant, field_x.arith.tag());
    try expect(2, field_x.arith.constant);

    const field_y = struct_expr.struct_instance.fields.get("y") orelse return std.testing.expect(false);
    try expect(.arith, field_y.tag());
    try expect(.constant, field_y.arith.tag());
    try expect(5, field_y.arith.constant);

    const field_z = struct_expr.struct_instance.fields.get("z") orelse return std.testing.expect(false);
    try expect(.if_, field_z.tag());

    const cond = field_z.if_.eval.*;
    try expect(.bool_, cond.tag());
    try expect(.eql, cond.bool_.tag());

    const then_branch = field_z.if_.then.*;
    try expect(.arith, then_branch.tag());
    try expect(.str, then_branch.arith.tag());
    try expectStrings("bonjour", then_branch.arith.str);

    const else_branch = field_z.if_.else_.*;
    try expect(.fn_call, else_branch.tag());
    try expectStrings("double", else_branch.fn_call.name);
    try expect(1, else_branch.fn_call.args.items.len);

    const arg_expr = else_branch.fn_call.args.items[0];
    try expect(.arith, arg_expr.tag());
    try expect(.minus, arg_expr.arith.tag());

    const lhs_arith = arg_expr.arith.minus.lhs.*;
    try expect(.plus, lhs_arith.arith.tag());

    const rhs_arith = arg_expr.arith.minus.rhs.*;
    try expect(.constant, rhs_arith.arith.tag());
    try expect(4, rhs_arith.arith.constant);
}
