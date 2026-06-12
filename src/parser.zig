const std = @import("std");

const expression_pkg = @import("expression.zig");
const lexer_pkg = @import("lexer.zig");

const Expr = expression_pkg.Expr;
const FnExpr = expression_pkg.FnExpr;
const ArithExpr = expression_pkg.ArithExpr;
const BoolExpr = expression_pkg.BoolExpr;
const ArgsExpr = expression_pkg.ArgsExpr;
const FieldAccessExpr = expression_pkg.FieldAccessExpr;
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
            self.lexer.eat(.semicolon);
            try program.append(self.alloc, expr);
            i += 1;
        }
        return .{
            .as = .{ .list = program },
            .cursor = self.lexer.cursor,
            .content = self.lexer.content,
            .file_path = self.lexer.file_path,
        };
    }

    fn parseFnDef(l: *Lexer, alloc: Allocator) !Expr {
        l.expect(.id);
        const id = l.name.asStr(l.content);
        l.nexti();
        l.eat(.assign);
        l.eat(.fn_);
        var args = std.ArrayList([]const u8).empty;
        while (l.token == .id) {
            try args.append(alloc, l.name.asStr(l.content));
            l.nexti();
        }
        l.eat(.arrow);

        const body = try alloc.create(Expr);
        body.* = try parseExpr(l, alloc);

        const fn_expr: FnExpr = .{
            .name = id,
            .args = args,
            .body = .{ .fn_std = .{ .body = body } },
        };
        return .{
            .as = .{ .fn_def = fn_expr },
            .cursor = l.previous_cursor,
            .content = l.content,
            .file_path = l.file_path,
        };
    }

    /// can be an arith expr a + 1 - 3
    /// or a bool expr a = 1
    /// or a function call a(b, c, d)
    fn parseBeginWithIdOrIntOrBool(l: *Lexer, alloc: Allocator) !Expr {
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
                .dot => blk: {
                    l.nexti();
                    l.eat(.dot);

                    l.expect(.id);
                    const field = l.name.asStr(l.content);
                    l.nexti();

                    const lhs_dot = try alloc.create(Expr);
                    lhs_dot.* = .{
                        .as = .{ .var_ = name },
                        .cursor = l.previous_cursor,
                        .content = l.content,
                        .file_path = l.file_path,
                    };
                    const expr: Expr = .{
                        .as = .{ .field_access = .{ .lhs = lhs_dot, .field = field } },
                        .cursor = l.previous_cursor,
                        .content = l.content,
                        .file_path = l.file_path,
                    };
                    // l.nexti();
                    break :blk expr;
                },
                else => blk: {
                    l.nexti();
                    break :blk .{
                        .as = .{ .var_ = name },
                        .cursor = l.previous_cursor,
                        .content = l.content,
                        .file_path = l.file_path,
                    };
                },
            };
        } else if (l.token == .int) {
            lhs.* = .{
                .as = .{ .arith = .{ .constant = l.integer_value.? } },
                .cursor = l.previous_cursor,
                .content = l.content,
                .file_path = l.file_path,
            };
            l.nexti();
        } else if (l.token == .str) {
            lhs.* = .{
                .as = .{ .arith = .{ .str = l.name.asStr(l.content) } },
                .cursor = l.previous_cursor,
                .content = l.content,
                .file_path = l.file_path,
            };
            l.nexti();
        } else if (l.token == .bool_) {
            lhs.* = .{
                .as = .{ .bool_ = .{ .constant = l.bool_value.? } },
                .cursor = l.previous_cursor,
                .content = l.content,
                .file_path = l.file_path,
            };
            l.nexti();
        } else if (l.tokenType == .primary) panic("Must be identifier, integer or string or bool", .{});

        while (l.tokenType == .arith_op or l.tokenType == .bool_op or l.token == .dot) {
            const op_token = l.token;
            const op_token_type = l.tokenType;
            l.nexti();

            const rhs = try alloc.create(Expr);
            next_l = l.*;
            next_l.nexti();

            const current_name = l.name.asStr(l.content);
            const int_value = l.integer_value;
            const bool_value = l.bool_value;

            rhs.* = switch (l.token) {
                .id => if (next_l.token == .oparen) blk: {
                    l.nexti();
                    const expr = try parseFnCall(l, alloc, current_name);
                    break :blk expr;
                } else blk: {
                    l.nexti();
                    break :blk .{
                        .as = .{ .var_ = current_name },
                        .cursor = l.previous_cursor,
                        .content = l.content,
                        .file_path = l.file_path,
                    };
                },
                .int => blk: {
                    l.nexti();
                    break :blk .{
                        .as = .{ .arith = .{ .constant = int_value.? } },
                        .cursor = l.previous_cursor,
                        .content = l.content,
                        .file_path = l.file_path,
                    };
                },
                .bool_ => blk: {
                    l.nexti();
                    break :blk .{
                        .as = .{ .bool_ = .{ .constant = bool_value.? } },
                        .cursor = l.previous_cursor,
                        .content = l.content,
                        .file_path = l.file_path,
                    };
                },
                .str => blk: {
                    l.nexti();
                    break :blk .{
                        .as = .{ .arith = .{ .str = current_name } },
                        .cursor = l.previous_cursor,
                        .content = l.content,
                        .file_path = l.file_path,
                    };
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
                lhs.* = .{
                    .as = .{ .arith = op },
                    .cursor = l.previous_cursor,
                    .content = l.content,
                    .file_path = l.file_path,
                };
            } else if (op_token_type == .bool_op) {
                const op: BoolExpr = switch (op_token) {
                    .eql => .{ .eql = .{ .lhs = lhs, .rhs = rhs } },
                    else => panic("not catch for {}", .{op_token}),
                };

                lhs = try alloc.create(Expr);
                lhs.* = .{
                    .as = .{ .bool_ = op },
                    .cursor = l.previous_cursor,
                    .content = l.content,
                    .file_path = l.file_path,
                };
            } else if (op_token == .dot) {
                const op: FieldAccessExpr = .{ .lhs = lhs, .field = rhs.as.var_ };
                lhs = try alloc.create(Expr);
                lhs.* = .{
                    .as = .{ .field_access = op },
                    .cursor = l.previous_cursor,
                    .content = l.content,
                    .file_path = l.file_path,
                };
            }
        }

        return lhs.*;
    }

    fn parseFnCall(l: *Lexer, alloc: Allocator, name: []const u8) !Expr {
        l.eat(.oparen);
        const args = try parseArgs(l, alloc);
        l.eat(.cparen);
        const lhs: Expr = .{
            .as = .{ .fn_call = .{ .name = name, .args = args } },
            .cursor = l.previous_cursor,
            .content = l.content,
            .file_path = l.file_path,
        };
        return lhs;
    }

    pub fn parseArgs(l: *Lexer, alloc: Allocator) !ArgsExpr {
        var args: std.ArrayList(Expr) = .empty;
        while (l.token != .cparen) {
            const arg = try parseExpr(l, alloc);
            try args.append(alloc, arg);
            l.eat(.comma);
        }
        return args;
    }

    fn parseBeginWithOParen(l: *Lexer, alloc: Allocator) !Expr {
        l.eat(.oparen);

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
                return .{
                    .as = .{ .bool_ = op },
                    .cursor = l.previous_cursor,
                    .content = l.content,
                    .file_path = l.file_path,
                };
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
                return .{
                    .as = .{ .arith = op },
                    .cursor = l.previous_cursor,
                    .content = l.content,
                    .file_path = l.file_path,
                };
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
            .id, .int, .bool_, .str => {
                return parseBeginWithIdOrIntOrBool(l, alloc);
            },
            .self_fn => {
                const name = l.name.asStr(l.content);
                l.nexti();
                l.eat(.oparen);
                const args = try parseArgs(l, alloc);
                l.eat(.cparen);
                return .{
                    .as = .{ .fn_call = .{ .name = name, .args = args } },
                    .cursor = l.previous_cursor,
                    .content = l.content,
                    .file_path = l.file_path,
                };
            },
            // an open paren (not in the context of a function)
            .oparen => {
                const expr = parseBeginWithOParen(l, alloc);
                l.eat(.cparen);
                return expr;
            },
            .bind => {
                return parseBind(l, alloc);
            },
            .at => {
                return parseStructInstance(l, alloc);
            },
            .struct_ => {
                return parseStruct(l, alloc);
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

        l.eat(.obrace);
        var fields: std.StringHashMapUnmanaged(Expr) = .empty;
        while (l.token != .cbrace) {
            l.eat(.dot);

            l.expect(.id);
            const field = l.name.asStr(l.content);
            l.nexti();
            l.eat(.assign);

            const value = try parseExpr(l, alloc);
            l.eat(.comma);
            try fields.putNoClobber(alloc, field, value);
        }
        l.nexti();
        return .{
            .as = .{ .struct_instance = .{ .name = name, .fields = fields } },
            .cursor = l.previous_cursor,
            .content = l.content,
            .file_path = l.file_path,
        };
    }

    fn parseStruct(l: *Lexer, alloc: Allocator) !Expr {
        l.eat(.struct_);
        l.expect(.id);
        const struct_name = l.name.asStr(l.content);
        l.nexti();
        l.eat(.obrace);

        var fields: std.ArrayList([]const u8) = .empty;
        while (l.token != .cbrace) {
            l.expect(.id);
            const field = l.name.asStr(l.content);
            l.nexti();
            try fields.append(alloc, field);
            l.eat(.comma);
        }

        l.eat(.cbrace);

        return Expr.create_struct(struct_name, fields, l);
    }

    fn parseBind(l: *Lexer, alloc: Allocator) !Expr {
        l.nexti();
        l.expect(.id);
        const id = l.name.asStr(l.content);
        l.nexti();

        l.eat(.assign);
        const body = try alloc.create(Expr);
        body.* = try parseExpr(l, alloc);
        l.eat(.in);

        const closure = try alloc.create(Expr);
        closure.* = try parseExpr(l, alloc);

        return Expr.create_bind(id, body, closure, l);
    }

    fn parseIf(l: *Lexer, alloc: Allocator) !Expr {
        const eval = try alloc.create(Expr);
        eval.* = try parseExpr(l, alloc);
        l.eat(.then);
        const then = try alloc.create(Expr);
        then.* = try parseExpr(l, alloc);
        l.eat(.else_);
        const else_ = try alloc.create(Expr);
        else_.* = try parseExpr(l, alloc);

        return Expr.create_if(eval, then, else_, l);
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
    var lexer = Lexer.init(source_code, "test.zig");
    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();
    try expect(.list, expr.as.tag());
    const fn_call = expr.as.list.items[0];
    try expect(.fn_call, fn_call.as.tag());

    const args = fn_call.as.fn_call.args;
    try expect(1, args.items.len);
    const arg = args.items[0];
    try expect(.arith, arg.as.tag());
    try expect(.constant, arg.as.arith.tag());
    try expect(97, arg.as.arith.constant);
}

test "parse print_str function" {
    // For now use an arena alloc because we don't free memory
    var arena = arena_alloc();
    defer arena.deinit();
    const alloc = arena.allocator();
    const source_code =
        \\ print_str("bonjour"+"papa",);
    ;
    var lexer = Lexer.init(source_code, "test.zig");

    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();
    try expect(.list, expr.as.tag());

    try expect(1, expr.as.list.items.len);
    const fn_call = expr.as.list.items[0];
    try expect(.fn_call, fn_call.as.tag());
    try expectStrings("print_str", fn_call.as.fn_call.name);

    const args = fn_call.as.fn_call.args;
    try expect(1, args.items.len);
    const arg = args.items[0];
    try expect(.arith, arg.as.tag());
    try expect(.plus, arg.as.arith.tag());

    const lhs = arg.as.arith.plus.lhs;
    const rhs = arg.as.arith.plus.rhs;

    try expect(.arith, lhs.as.tag());
    try expect(.str, lhs.as.arith.tag());
    try expectStrings("bonjour", lhs.as.arith.str);

    try expect(.arith, rhs.as.tag());
    try expect(.str, rhs.as.arith.tag());
    try expectStrings("papa", rhs.as.arith.str);
}

test "parse function definition" {
    var arena = arena_alloc();
    defer arena.deinit();
    const alloc = arena.allocator();

    const source_code =
        \\ let add = fn x y -> x + y;
    ;
    var lexer = Lexer.init(source_code, "test.zig");
    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();

    try expect(.list, expr.as.tag());
    try expect(1, expr.as.list.items.len);

    const fn_def = expr.as.list.items[0];
    try expect(.fn_def, fn_def.as.tag());
    try expectStrings("add", fn_def.as.fn_def.name);
    try expect(2, fn_def.as.fn_def.args.items.len);
    try expectStrings("x", fn_def.as.fn_def.args.items[0]);
    try expectStrings("y", fn_def.as.fn_def.args.items[1]);

    const body = fn_def.as.fn_def.body.fn_std.body.*;
    try expect(.arith, body.as.tag());
    try expect(.plus, body.as.arith.tag());
}

test "parse if expression" {
    var arena = arena_alloc();
    defer arena.deinit();
    const alloc = arena.allocator();

    const source_code =
        \\ if n == 1 then "yes" else "no";
    ;
    var lexer = Lexer.init(source_code, "test.zig");
    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();

    try expect(.list, expr.as.tag());

    const if_expr = expr.as.list.items[0];
    try expect(.if_, if_expr.as.tag());

    const eval_node = if_expr.as.if_.eval.*;
    try expect(.bool_, eval_node.as.tag());
    try expect(.eql, eval_node.as.bool_.tag());

    const lhs = eval_node.as.bool_.eql.lhs;
    try expect(.var_, lhs.as.tag());
    try expectStrings("n", lhs.as.var_);

    const rhs = eval_node.as.bool_.eql.rhs;
    try expect(.arith, rhs.as.tag());
    try expect(.constant, rhs.as.arith.tag());
    try expect(1, rhs.as.arith.constant);

    const then_node = if_expr.as.if_.then.*;
    try expect(.arith, then_node.as.tag());
    try expect(.str, then_node.as.arith.tag());
    try expectStrings("yes", then_node.as.arith.str);

    const else_node = if_expr.as.if_.else_.*;
    try expect(.arith, else_node.as.tag());
    try expect(.str, else_node.as.arith.tag());
    try expectStrings("no", else_node.as.arith.str);
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
    var lexer = Lexer.init(source_code, "test.zig");
    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();

    try expect(.list, expr.as.tag());
    try expect(2, expr.as.list.items.len);

    const fn_def = expr.as.list.items[0];
    try expect(.fn_def, fn_def.as.tag());
    try expectStrings("double", fn_def.as.fn_def.name);

    const bind_n = expr.as.list.items[1];
    try expect(.bind, bind_n.as.tag());
    try expectStrings("n", bind_n.as.bind.id);

    const bind_n_body = bind_n.as.bind.body.*;
    try expect(.arith, bind_n_body.as.tag());
    try expect(.plus, bind_n_body.as.arith.tag());

    const bind_n_double = bind_n.as.bind.closure.*;
    try expect(.bind, bind_n_double.as.tag());
    try expectStrings("n_double", bind_n_double.as.bind.id);

    const bind_n_double_body = bind_n_double.as.bind.body.*;
    try expect(.fn_call, bind_n_double_body.as.tag());
    try expectStrings("double", bind_n_double_body.as.fn_call.name);
    try expect(1, bind_n_double_body.as.fn_call.args.items.len);

    const print_call = bind_n_double.as.bind.closure.*;
    try expect(.fn_call, print_call.as.tag());
    try expectStrings("print_int", print_call.as.fn_call.name);
    try expect(1, print_call.as.fn_call.args.items.len);

    const print_arg = print_call.as.fn_call.args.items[0];
    try expect(.var_, print_arg.as.tag());
    try expectStrings("n_double", print_arg.as.var_);
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
    var lexer = Lexer.init(source_code, "test.zig");
    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();

    try expect(.list, expr.as.tag());
    try expect(1, expr.as.list.items.len);

    const struct_expr = expr.as.list.items[0];
    try expect(.struct_instance, struct_expr.as.tag());
    try expectStrings("Point", struct_expr.as.struct_instance.name);
    try expect(3, struct_expr.as.struct_instance.fields.size);

    const field_x = struct_expr.as.struct_instance.fields.get("x") orelse return std.testing.expect(false);

    try expect(.arith, field_x.as.tag());
    try expect(.constant, field_x.as.arith.tag());
    try expect(2, field_x.as.arith.constant);

    const field_y = struct_expr.as.struct_instance.fields.get("y") orelse return std.testing.expect(false);
    try expect(.arith, field_y.as.tag());
    try expect(.constant, field_y.as.arith.tag());
    try expect(5, field_y.as.arith.constant);

    const field_z = struct_expr.as.struct_instance.fields.get("z") orelse return std.testing.expect(false);
    try expect(.if_, field_z.as.tag());

    const cond = field_z.as.if_.eval.*;
    try expect(.bool_, cond.as.tag());
    try expect(.eql, cond.as.bool_.tag());

    const then_branch = field_z.as.if_.then.*;
    try expect(.arith, then_branch.as.tag());
    try expect(.str, then_branch.as.arith.tag());
    try expectStrings("bonjour", then_branch.as.arith.str);

    const else_branch = field_z.as.if_.else_.*;
    try expect(.fn_call, else_branch.as.tag());
    try expectStrings("double", else_branch.as.fn_call.name);
    try expect(1, else_branch.as.fn_call.args.items.len);

    const arg_expr = else_branch.as.fn_call.args.items[0];
    try expect(.arith, arg_expr.as.tag());
    try expect(.minus, arg_expr.as.arith.tag());

    const lhs_arith = arg_expr.as.arith.minus.lhs.*;
    try expect(.plus, lhs_arith.as.arith.tag());

    const rhs_arith = arg_expr.as.arith.minus.rhs.*;
    try expect(.constant, rhs_arith.as.arith.tag());
    try expect(4, rhs_arith.as.arith.constant);
}

test "parse field access with dot" {
    var arena = arena_alloc();
    defer arena.deinit();
    const alloc = arena.allocator();

    const source_code =
        \\ p.x.y.z;
    ;
    var lexer = Lexer.init(source_code, "test.zig");
    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();

    try expect(.list, expr.as.tag());
    try expect(1, expr.as.list.items.len);

    const level_z = expr.as.list.items[0];
    try expect(.field_access, level_z.as.tag());
    try expectStrings("z", level_z.as.field_access.field);

    const level_y = level_z.as.field_access.lhs.*;
    try expect(.field_access, level_y.as.tag());
    try expectStrings("y", level_y.as.field_access.field);

    const level_x = level_y.as.field_access.lhs.*;
    try expect(.field_access, level_x.as.tag());
    try expectStrings("x", level_x.as.field_access.field);

    const base_var = level_x.as.field_access.lhs.*;
    try expect(.var_, base_var.as.tag());
    try expectStrings("p", base_var.as.var_);
}

test "parse true == false" {
    var arena = arena_alloc();
    defer arena.deinit();
    const alloc = arena.allocator();

    const source_code =
        \\ true == false;
    ;
    var lexer = Lexer.init(source_code, "test.zig");
    var parser = Parser.init(&lexer, alloc);
    const expr = try parser.parse();

    try expect(.list, expr.as.tag());
    try expect(1, expr.as.list.items.len);

    const eql_expr = expr.as.list.items[0];
    try expect(.bool_, eql_expr.as.tag());
    try expect(.eql, eql_expr.as.bool_.tag());

    try expect(.bool_, eql_expr.as.bool_.eql.lhs.as.tag());
    try expect(.constant, eql_expr.as.bool_.eql.lhs.as.bool_.tag());
    try expect(true, eql_expr.as.bool_.eql.lhs.as.bool_.constant);

    try expect(.bool_, eql_expr.as.bool_.eql.rhs.as.tag());
    try expect(.constant, eql_expr.as.bool_.eql.rhs.as.bool_.tag());
    try expect(false, eql_expr.as.bool_.eql.rhs.as.bool_.constant);
}
