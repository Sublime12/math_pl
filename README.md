# math_pl

A lightweight mathematical expression evaluator and programming language parser 
written in **Zig**. It features a custom lexer, parser, and recursive evaluator 
for arithmetic, boolean comparisons, and conditional logic.

## Features

* **Lexer & Parser:** Hand-written recursive descent parser.
* **Arithmetic:** Supports addition, subtraction, and multiplication.
* **Conditionals:** `if-then-else` expression support.
* **Booleans:** Equality comparisons and boolean constants.
* **Functions:** Syntax support for function definitions and calls (in progress).

## Usage

### Prerequisites
* **Zig 0.15.2**

### Build 
```bash
zig build 
```

### Run Tests
To execute the unit tests defined in the source files:

```bash
zig build test
```

## Example Syntax
The language handles expressions like:
For now, the arith expression tree is right associative
You need to put parenthese to change the correct associativeness
```ocaml
if (3 + 7) == 2 * 1 - 3
then 1
else (6 * 3) + 1 - 5
```

## Project Structure
* `src/parser.zig`: Expression parsing.
* `src/expression.zig`: Abstract Syntax Tree (AST) definitions.
* `src/eval.zig`: Recursive evaluation logic.
* `src/main.zig`: Entry point and demonstration.
