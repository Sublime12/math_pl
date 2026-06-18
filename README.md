# sub_pl

A simple functional programming language written from scratch without dependencies.
This project is `incomplete`, the goal for me is to learn language design and how to
implement the differents parts of the pipeline of creating a programming language
(lexing, parsing, sema, error displays, etc).

## Syntax
Example of correct simple programs can be found in `examples/`,

* simple example of factorial:
```ocaml
    (base) sublime@sublime:~/Documents/projects/sub_pl
    $ cat examples/fact.sub
    let fact = fn n -> if n == 1 then 1 else n * fact(n - 1,);
    print_int(fact(5, ), ) ;
    (base) sublime@sublime:~/Documents/projects/sub_pl
    $ ./zig-out/bin/sub_pl examples/fact.sub
    120
    (base) sublime@sublime:~/Documents/projects/sub_pl
```

## Usage

### Prerequisites
* **Zig 0.16.0**

### Build
```bash
zig build
```

### Run Tests
To execute the unit tests defined in the source files:

```bash
./zig-out/bin/test
```

## Syntax Rules
For now, most of the syntax are in the `examples/` folder and in the
`src/parser.zig` tests,
Comments for now are not supporting (will be add pretty soon)
This is a cat of the files `examples/`,

(base) sublime@sublime:~/Documents/projects/sub_pl
$ for f in examples/*; do echo "File: $f "; cat "$f"; echo ""; done
`File: examples/bind_var.sub`
```ocaml
let double = fn x -> x * 2;
bind n = 15 + 3 in
bind n_double = double(n, ) in
print_int(n_double,);
```

`File: examples/bool.sub`\
bind syntax allow to bind a var\
with a value you can use in the `in` sub expression

```ocaml
bind x = true in
if x then
  print_str("bonjour is true",)
else
  print_str("bonjour is false",);
```

`File: examples/fact.sub`
```ocaml
let fact = fn n -> if n == 1 then 1 else n * fact(n - 1,);
print_int(fact(5, ), ) ;
```

`File: examples/getc.sub`\
other stdlib function can be registered in stdlib.zig
```ocaml
print_underscore("bonjour", 0, 7,);
let print_underscore = fn str n l ->
  if n == l then 0
  else
    bind c = getc(str, n,) in
    bind _a = print(c,) in
    bind _b = print_str("_",) in
    print_underscore(str, n + 1, l,)
;
```

`File: examples/string.sub`\
Strings are parse as seen in the source code\
the number of \" seen in the beginning of a string is the\
must match at the end\
Design of string for now is a little bit imcomplete, i'm\
going to rework that and think longer about the architecture
```ocaml
print_str(""" Hello "sub" """,);
```

`File: examples/struct.sub`\
To create a struct, define a struct with fields, the language is\
untyped, to create an instance use the @ symbol
```ocaml
bind p = @Point{ .x = 2, .y = @Point{ .x = 69, .y = 15, }, } in
print_int(p.x + (p.y.x),);
struct Point {
  x, y,
};
```
