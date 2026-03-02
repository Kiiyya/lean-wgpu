import Lean.Syntax
import Lean.Parser
/-!
# WGSL Syntax Categories and Rules

Mechanical translation of the [WGSL grammar](https://www.w3.org/TR/WGSL/#syntax)
into Lean `declare_syntax_cat` / `syntax` declarations.

Reference BNF: `tmp/wgsl_syntax.bnf`

## Translation notes
- `_disambiguate_template` dropped (parser-internal hint).
- `_template_args_start`/`_template_args_end` → `<`/`>`.
- `_shift_left`→`<<`, `_shift_right`→`>>`.
- `_less_than`→`<`, `_greater_than`→`>`, `_less_than_equal`→`<=`, `_greater_than_equal`→`>=`.
- `_shift_left_assign`→`<<=`, `_shift_right_assign`→`>>=`.
- Regex tokens approximated with Lean `ident`/`num`/`scientific` parsers.
- Numeric literal suffixes (`i`, `u`, `f`, `h`) not yet validated.
- Left-recursive expression rules may need explicit priorities.
- Optional trailing commas handled via `","?`.
- Lean-reserved words (`return`, `if`, `else`, `for`, `while`, `break`, `continue`)
  overlap only with WGSL keywords, not identifiers — no conflict.
- `let` is both a WGSL keyword and a Lean keyword; it appears only as a string
  literal `"let"` in syntax rules, so there is no conflict.

## Keyword pollution
In Lean 4, any `syntax "foo" : cat` globally registers `"foo"` as a keyword
token, preventing `ident` from matching it in *every* syntax category.  To avoid
this, only genuinely WGSL-reserved words (`var`, `fn`, `return`, `diagnostic`, …)
appear as string-literal keywords.  Contextual keywords (attribute names like
`vertex`, `binding`, `align`; swizzle letters `x`, `y`, `z`, `w`, `r`, `g`,
`b`, `a`) are parsed via `ident` and validated semantically later.

Individual attribute sub-categories (`align_attr`, `binding_attr`, …) from the
spec are collapsed into a single catch-all `wgsl_attribute` rule for the same
reason.
-/


-- Helper: the mixed repetition (global_decl | global_assert | ';')* in translation_unit
-- needs a wrapper since Lean syntax `*` applies to a single category.
declare_syntax_cat wgsl_global_item

-- ============================================================
-- Top-level / translation unit
-- ============================================================
declare_syntax_cat wgsl_translation_unit
declare_syntax_cat wgsl_global_directive
declare_syntax_cat wgsl_global_decl
declare_syntax_cat wgsl_global_assert

-- ============================================================
-- Literals
-- ============================================================
declare_syntax_cat wgsl_bool_literal
declare_syntax_cat wgsl_int_literal
declare_syntax_cat wgsl_decimal_int_literal
declare_syntax_cat wgsl_hex_int_literal
declare_syntax_cat wgsl_float_literal
declare_syntax_cat wgsl_decimal_float_literal
declare_syntax_cat wgsl_hex_float_literal
declare_syntax_cat wgsl_literal

-- ============================================================
-- Identifiers
-- ============================================================
declare_syntax_cat wgsl_ident
declare_syntax_cat wgsl_member_ident
declare_syntax_cat wgsl_ident_pattern_token

-- ============================================================
-- Diagnostics
-- ============================================================
declare_syntax_cat wgsl_diagnostic_directive
declare_syntax_cat wgsl_diagnostic_name_token
declare_syntax_cat wgsl_diagnostic_rule_name
declare_syntax_cat wgsl_diagnostic_control
declare_syntax_cat wgsl_severity_control_name

-- ============================================================
-- Templates
-- ============================================================
declare_syntax_cat wgsl_template_list
declare_syntax_cat wgsl_template_arg_comma_list
declare_syntax_cat wgsl_template_arg_expression
declare_syntax_cat wgsl_template_elaborated_ident

-- ============================================================
-- Attributes
-- ============================================================
-- NOTE: individual attribute sub-categories (align_attr, binding_attr, …)
-- are intentionally omitted.  Encoding their names as string-literal keywords
-- (e.g. `"vertex"`, `"align"`) would register them in Lean's global token
-- table, preventing `ident` from matching those tokens anywhere else — which
-- breaks parsing of valid WGSL identifiers like `var vertex : f32;`.
-- Instead, `wgsl_attribute` uses a single catch-all rule with `ident`;
-- specific attribute validation is deferred to semantic analysis.
declare_syntax_cat wgsl_attribute

-- ============================================================
-- Types
-- ============================================================
declare_syntax_cat wgsl_type_specifier
declare_syntax_cat wgsl_type_alias_decl

-- ============================================================
-- Structs
-- ============================================================
declare_syntax_cat wgsl_struct_decl
declare_syntax_cat wgsl_struct_body_decl
declare_syntax_cat wgsl_struct_member

-- ============================================================
-- Variables & declarations
-- ============================================================
declare_syntax_cat wgsl_variable_or_value_statement
declare_syntax_cat wgsl_variable_decl
declare_syntax_cat wgsl_optionally_typed_ident
declare_syntax_cat wgsl_global_variable_decl
declare_syntax_cat wgsl_global_value_decl

-- ============================================================
-- Expressions
-- ============================================================
declare_syntax_cat wgsl_primary_expression
declare_syntax_cat wgsl_call_expression
declare_syntax_cat wgsl_call_phrase
declare_syntax_cat wgsl_paren_expression
declare_syntax_cat wgsl_argument_expression_list
declare_syntax_cat wgsl_expression_comma_list
declare_syntax_cat wgsl_component_or_swizzle_specifier
declare_syntax_cat wgsl_unary_expression
declare_syntax_cat wgsl_singular_expression
declare_syntax_cat wgsl_lhs_expression
declare_syntax_cat wgsl_core_lhs_expression
declare_syntax_cat wgsl_multiplicative_expression
declare_syntax_cat wgsl_multiplicative_operator
declare_syntax_cat wgsl_additive_expression
declare_syntax_cat wgsl_additive_operator
declare_syntax_cat wgsl_shift_expression
declare_syntax_cat wgsl_relational_expression
declare_syntax_cat wgsl_short_circuit_and_expression
declare_syntax_cat wgsl_short_circuit_or_expression
declare_syntax_cat wgsl_binary_or_expression
declare_syntax_cat wgsl_binary_and_expression
declare_syntax_cat wgsl_binary_xor_expression
declare_syntax_cat wgsl_bitwise_expression
declare_syntax_cat wgsl_expression
declare_syntax_cat wgsl_swizzle_name

-- ============================================================
-- Statements
-- ============================================================
declare_syntax_cat wgsl_statement
declare_syntax_cat wgsl_compound_statement
declare_syntax_cat wgsl_assignment_statement
declare_syntax_cat wgsl_compound_assignment_operator
declare_syntax_cat wgsl_increment_statement
declare_syntax_cat wgsl_decrement_statement
declare_syntax_cat wgsl_variable_updating_statement
declare_syntax_cat wgsl_return_statement
declare_syntax_cat wgsl_func_call_statement
declare_syntax_cat wgsl_const_assert
declare_syntax_cat wgsl_assert_statement

-- ============================================================
-- Control flow – if
-- ============================================================
declare_syntax_cat wgsl_if_statement
declare_syntax_cat wgsl_if_clause
declare_syntax_cat wgsl_else_if_clause
declare_syntax_cat wgsl_else_clause

-- ============================================================
-- Control flow – switch
-- ============================================================
declare_syntax_cat wgsl_switch_statement
declare_syntax_cat wgsl_switch_body
declare_syntax_cat wgsl_switch_clause
declare_syntax_cat wgsl_case_clause
declare_syntax_cat wgsl_default_alone_clause
declare_syntax_cat wgsl_case_selectors
declare_syntax_cat wgsl_case_selector

-- ============================================================
-- Control flow – loops
-- ============================================================
declare_syntax_cat wgsl_loop_statement
declare_syntax_cat wgsl_for_statement
declare_syntax_cat wgsl_for_header
declare_syntax_cat wgsl_for_init
declare_syntax_cat wgsl_for_update
declare_syntax_cat wgsl_while_statement

-- ============================================================
-- Control flow – break / continue
-- ============================================================
declare_syntax_cat wgsl_break_statement
declare_syntax_cat wgsl_break_if_statement
declare_syntax_cat wgsl_continue_statement
declare_syntax_cat wgsl_continuing_statement
declare_syntax_cat wgsl_continuing_compound_statement

-- ============================================================
-- Functions
-- ============================================================
declare_syntax_cat wgsl_function_decl
declare_syntax_cat wgsl_function_header
declare_syntax_cat wgsl_param_list
declare_syntax_cat wgsl_param

-- ============================================================
-- Enable / requires directives
-- ============================================================
declare_syntax_cat wgsl_enable_directive
declare_syntax_cat wgsl_enable_extension_list
declare_syntax_cat wgsl_enable_extension_name
declare_syntax_cat wgsl_requires_directive
declare_syntax_cat wgsl_language_extension_list
declare_syntax_cat wgsl_language_extension_name

-- ============================================================
-- Top-level / translation unit  (syntax rules)
-- ============================================================

-- translation_unit
syntax wgsl_global_decl : wgsl_global_item
syntax wgsl_global_assert : wgsl_global_item
syntax ";" : wgsl_global_item
syntax wgsl_global_directive* wgsl_global_item* : wgsl_translation_unit

-- global_directive
syntax wgsl_diagnostic_directive : wgsl_global_directive
syntax wgsl_enable_directive : wgsl_global_directive
syntax wgsl_requires_directive : wgsl_global_directive

-- global_decl
syntax wgsl_global_variable_decl ";" : wgsl_global_decl
syntax wgsl_global_value_decl ";" : wgsl_global_decl
syntax wgsl_type_alias_decl ";" : wgsl_global_decl
syntax wgsl_struct_decl : wgsl_global_decl
syntax wgsl_function_decl : wgsl_global_decl

-- global_assert
syntax wgsl_const_assert ";" : wgsl_global_assert

-- ============================================================
-- Literals  (syntax rules)
-- ============================================================

-- bool_literal
-- Use nonReservedSymbol to avoid polluting Lean's keyword space
-- (syntax "true"/"false" would break Bool.true/Bool.false in Lean code)
open Lean Parser in
@[wgsl_bool_literal_parser] def wgslBoolTrue :=
  leadingNode `wgsl_bool_true 0 (nonReservedSymbol "true")
open Lean Parser in
@[wgsl_bool_literal_parser] def wgslBoolFalse :=
  leadingNode `wgsl_bool_false 0 (nonReservedSymbol "false")

-- int_literal
syntax wgsl_decimal_int_literal : wgsl_int_literal
syntax wgsl_hex_int_literal : wgsl_int_literal

-- decimal_int_literal
syntax num : wgsl_decimal_int_literal

-- hex_int_literal
syntax num : wgsl_hex_int_literal

-- float_literal
syntax wgsl_decimal_float_literal : wgsl_float_literal
syntax wgsl_hex_float_literal : wgsl_float_literal

-- decimal_float_literal
syntax scientific : wgsl_decimal_float_literal
syntax num : wgsl_decimal_float_literal  -- integer-like floats (e.g. 0f)

-- hex_float_literal
-- Lean's `scientific` only handles decimal floats; hex floats (0x1.0p5)
-- will need a custom token parser in the future.
-- For now, `num` covers the hex-int-like prefix (0xABC).
syntax num : wgsl_hex_float_literal

-- literal
syntax wgsl_int_literal : wgsl_literal
syntax wgsl_float_literal : wgsl_literal
syntax wgsl_bool_literal : wgsl_literal
-- WGSL number suffixes (u, i, f, h).  Lean's `num`/`scientific` parsers do
-- not consume trailing suffix letters, so they appear as a separate `ident`
-- token.  `reprint` faithfully reproduces the original spacing, so `2u` in
-- the source stays `2u` in the output string.
syntax wgsl_int_literal ident : wgsl_literal
syntax wgsl_float_literal ident : wgsl_literal

-- ============================================================
-- Identifiers  (syntax rules)
-- ============================================================

-- ident
syntax wgsl_ident_pattern_token : wgsl_ident

-- member_ident
syntax wgsl_ident_pattern_token : wgsl_member_ident

-- ident_pattern_token
syntax ident : wgsl_ident_pattern_token
-- `in` is a Lean-reserved keyword but a valid WGSL identifier (commonly used
-- as a parameter name).  Since it is already globally reserved, adding it here
-- causes no additional keyword pollution.
syntax "in" : wgsl_ident_pattern_token

-- ============================================================
-- Diagnostics  (syntax rules)
-- ============================================================

-- diagnostic_directive
syntax "diagnostic" wgsl_diagnostic_control ";" : wgsl_diagnostic_directive

-- diagnostic_name_token
syntax wgsl_ident_pattern_token : wgsl_diagnostic_name_token

-- diagnostic_rule_name
syntax wgsl_diagnostic_name_token : wgsl_diagnostic_rule_name
syntax wgsl_diagnostic_name_token "." wgsl_diagnostic_name_token : wgsl_diagnostic_rule_name

-- diagnostic_control
syntax "(" wgsl_severity_control_name "," wgsl_diagnostic_rule_name ","? ")" : wgsl_diagnostic_control

-- severity_control_name
syntax wgsl_ident_pattern_token : wgsl_severity_control_name

-- ============================================================
-- Templates  (syntax rules)
-- ============================================================

-- template_list
syntax "<" wgsl_template_arg_comma_list ">" : wgsl_template_list

-- template_arg_comma_list
syntax wgsl_template_arg_expression ("," wgsl_template_arg_expression)* ","? : wgsl_template_arg_comma_list

-- template_arg_expression
-- Restricted from full `expression` to `shift_expression` to avoid ambiguity:
-- without WGSL's `_disambiguate_template` pre-pass, `>` inside a template arg
-- would be consumed by the relational-expression parser, closing the template
-- list prematurely.  In practice, template arguments are identifiers, numbers,
-- or simple arithmetic — never comparisons.
syntax wgsl_shift_expression : wgsl_template_arg_expression

-- template_elaborated_ident
-- Split into two rules (with/without template list) instead of using
-- `(wgsl_template_list)?`.  Lean's `optional` combinator does NOT backtrack
-- once the inner parser has consumed input (PEG semantics), so `(template_list)?`
-- commits after seeing `<` even if the remainder fails.  Two separate rules
-- allow the category-level alternation to backtrack and try the simpler rule.
syntax wgsl_ident wgsl_template_list : wgsl_template_elaborated_ident
syntax wgsl_ident : wgsl_template_elaborated_ident

-- ============================================================
-- Attributes  (syntax rules)
-- ============================================================

-- attribute (catch-all)
-- Parses `@name`, `@name(args)`, and `@diagnostic(control)`.
-- Attribute name validation (vertex, fragment, binding, …) is deferred to
-- semantic analysis so that we avoid polluting Lean's keyword table.
syntax "@" wgsl_ident_pattern_token (wgsl_argument_expression_list)? : wgsl_attribute
syntax "@" "diagnostic" wgsl_diagnostic_control : wgsl_attribute

-- ============================================================
-- Types  (syntax rules)
-- ============================================================

-- type_specifier
syntax wgsl_template_elaborated_ident : wgsl_type_specifier

-- type_alias_decl
syntax "alias" wgsl_ident "=" wgsl_type_specifier : wgsl_type_alias_decl

-- ============================================================
-- Structs  (syntax rules)
-- ============================================================

-- struct_decl
syntax "struct" wgsl_ident wgsl_struct_body_decl : wgsl_struct_decl

-- struct_body_decl
syntax "{" (wgsl_struct_member),+,? "}" : wgsl_struct_body_decl



-- struct_member
syntax wgsl_attribute* wgsl_member_ident ":" wgsl_type_specifier : wgsl_struct_member

-- ============================================================
-- Variables & declarations  (syntax rules)
-- ============================================================

-- variable_or_value_statement
syntax wgsl_variable_decl : wgsl_variable_or_value_statement
syntax wgsl_variable_decl "=" wgsl_expression : wgsl_variable_or_value_statement
syntax "let" wgsl_optionally_typed_ident "=" wgsl_expression : wgsl_variable_or_value_statement
syntax "const" wgsl_optionally_typed_ident "=" wgsl_expression : wgsl_variable_or_value_statement

-- variable_decl
syntax "var" (wgsl_template_list)? wgsl_optionally_typed_ident : wgsl_variable_decl

-- optionally_typed_ident
syntax wgsl_ident (":" wgsl_type_specifier)? : wgsl_optionally_typed_ident

-- global_variable_decl
syntax wgsl_attribute* wgsl_variable_decl ("=" wgsl_expression)? : wgsl_global_variable_decl

-- global_value_decl
syntax "const" wgsl_optionally_typed_ident "=" wgsl_expression : wgsl_global_value_decl
syntax wgsl_attribute* "override" wgsl_optionally_typed_ident ("=" wgsl_expression)? : wgsl_global_value_decl

-- ============================================================
-- Expressions  (syntax rules)
-- ============================================================

-- primary_expression
-- Use `wgsl_ident` instead of `wgsl_template_elaborated_ident` here.
-- In WGSL, `<` after an identifier in expression context is ALWAYS a comparison
-- operator, never a template-list opener (WGSL's `_disambiguate_template`
-- pre-pass ensures this).  Template-parameterized references only appear in
-- call expressions (handled by `call_phrase`) and type specifiers.
syntax wgsl_ident : wgsl_primary_expression
syntax wgsl_call_expression : wgsl_primary_expression
syntax wgsl_literal : wgsl_primary_expression
syntax wgsl_paren_expression : wgsl_primary_expression

-- call_expression
syntax wgsl_call_phrase : wgsl_call_expression

-- call_phrase
-- Custom parser: the template_list attempt is wrapped in `atomic` so that
-- when `<` is actually a comparison operator (not a template delimiter), the
-- failing template-list parse doesn't advance Lean's "furthest error" state
-- and prevent successful alternatives from being selected.
open Lean Parser in
@[wgsl_call_phrase_parser] def wgslCallPhraseWithTemplate :=
  leadingNode `wgsl_call_phrase_templ 0
    (categoryParser `wgsl_ident 0 >>
     atomic (categoryParser `wgsl_template_list 0) >>
     categoryParser `wgsl_argument_expression_list 0)
open Lean Parser in
@[wgsl_call_phrase_parser] def wgslCallPhrasePlain :=
  leadingNode `wgsl_call_phrase_plain 0
    (categoryParser `wgsl_ident 0 >>
     categoryParser `wgsl_argument_expression_list 0)

-- paren_expression
syntax "(" wgsl_expression ")" : wgsl_paren_expression

-- argument_expression_list
syntax "(" (wgsl_expression_comma_list)? ")" : wgsl_argument_expression_list

-- expression_comma_list
syntax (wgsl_expression),+,? : wgsl_expression_comma_list

-- component_or_swizzle_specifier
syntax "[" wgsl_expression "]" (wgsl_component_or_swizzle_specifier)? : wgsl_component_or_swizzle_specifier
syntax "." wgsl_member_ident (wgsl_component_or_swizzle_specifier)? : wgsl_component_or_swizzle_specifier
syntax "." wgsl_swizzle_name (wgsl_component_or_swizzle_specifier)? : wgsl_component_or_swizzle_specifier

-- unary_expression
syntax wgsl_singular_expression : wgsl_unary_expression
syntax "-" wgsl_unary_expression : wgsl_unary_expression
syntax "!" wgsl_unary_expression : wgsl_unary_expression
syntax "~" wgsl_unary_expression : wgsl_unary_expression
syntax "*" wgsl_unary_expression : wgsl_unary_expression
syntax "&" wgsl_unary_expression : wgsl_unary_expression

-- singular_expression
syntax wgsl_primary_expression (wgsl_component_or_swizzle_specifier)? : wgsl_singular_expression

-- lhs_expression
syntax wgsl_core_lhs_expression (wgsl_component_or_swizzle_specifier)? : wgsl_lhs_expression
syntax "*" wgsl_lhs_expression : wgsl_lhs_expression
syntax "&" wgsl_lhs_expression : wgsl_lhs_expression

-- core_lhs_expression
syntax wgsl_ident : wgsl_core_lhs_expression
syntax "(" wgsl_lhs_expression ")" : wgsl_core_lhs_expression

-- multiplicative_expression
syntax wgsl_unary_expression : wgsl_multiplicative_expression
syntax wgsl_multiplicative_expression wgsl_multiplicative_operator wgsl_unary_expression : wgsl_multiplicative_expression

-- multiplicative_operator
syntax "*" : wgsl_multiplicative_operator
syntax "/" : wgsl_multiplicative_operator
syntax "%" : wgsl_multiplicative_operator

-- additive_expression
syntax wgsl_multiplicative_expression : wgsl_additive_expression
syntax wgsl_additive_expression wgsl_additive_operator wgsl_multiplicative_expression : wgsl_additive_expression

-- additive_operator
syntax "+" : wgsl_additive_operator
syntax "-" : wgsl_additive_operator

-- shift_expression
syntax wgsl_additive_expression : wgsl_shift_expression
syntax wgsl_unary_expression "<<" wgsl_unary_expression : wgsl_shift_expression
syntax wgsl_unary_expression ">>" wgsl_unary_expression : wgsl_shift_expression

-- relational_expression
syntax wgsl_shift_expression : wgsl_relational_expression
syntax wgsl_shift_expression "<" wgsl_shift_expression : wgsl_relational_expression
syntax wgsl_shift_expression ">" wgsl_shift_expression : wgsl_relational_expression
syntax wgsl_shift_expression "<=" wgsl_shift_expression : wgsl_relational_expression
syntax wgsl_shift_expression ">=" wgsl_shift_expression : wgsl_relational_expression
syntax wgsl_shift_expression "==" wgsl_shift_expression : wgsl_relational_expression
syntax wgsl_shift_expression "!=" wgsl_shift_expression : wgsl_relational_expression

-- short_circuit_and_expression
syntax wgsl_relational_expression : wgsl_short_circuit_and_expression
syntax wgsl_short_circuit_and_expression "&&" wgsl_relational_expression : wgsl_short_circuit_and_expression

-- short_circuit_or_expression
-- Base case chains through short_circuit_and (not relational) per WGSL spec
syntax wgsl_short_circuit_and_expression : wgsl_short_circuit_or_expression
syntax wgsl_short_circuit_or_expression "||" wgsl_short_circuit_and_expression : wgsl_short_circuit_or_expression

-- bitwise_expression
-- Replaces separate binary_or/and/xor categories to avoid Pratt parser greedy-consumption conflict.
-- (The old binary_*_expression "|"/"&"/"^" rules consumed all operators, leaving none for bitwise_expression.)
syntax wgsl_unary_expression : wgsl_bitwise_expression
syntax wgsl_bitwise_expression "&" wgsl_unary_expression : wgsl_bitwise_expression
syntax wgsl_bitwise_expression "|" wgsl_unary_expression : wgsl_bitwise_expression
syntax wgsl_bitwise_expression "^" wgsl_unary_expression : wgsl_bitwise_expression

-- expression
-- The || and && chaining is handled by the short_circuit categories above.
-- Adding sc_or "||" rel here would conflict with the Pratt parser's greedy consumption.
syntax wgsl_short_circuit_or_expression : wgsl_expression
syntax wgsl_bitwise_expression : wgsl_expression

-- swizzle_name
-- Valid WGSL swizzles are 1-4 component names from [rgba] or [xyzw].
-- We parse with `ident` and defer validation to semantic analysis.
-- Registering individual letters ("r", "x", …) as keywords would break
-- `ident` matching for common shader variable names.
syntax ident : wgsl_swizzle_name

-- ============================================================
-- Statements  (syntax rules)
-- ============================================================

-- statement
syntax ";" : wgsl_statement
syntax wgsl_return_statement ";" : wgsl_statement
syntax wgsl_if_statement : wgsl_statement
syntax wgsl_switch_statement : wgsl_statement
syntax wgsl_loop_statement : wgsl_statement
syntax wgsl_for_statement : wgsl_statement
syntax wgsl_while_statement : wgsl_statement
syntax wgsl_func_call_statement ";" : wgsl_statement
syntax wgsl_variable_or_value_statement ";" : wgsl_statement
syntax wgsl_break_statement ";" : wgsl_statement
syntax wgsl_continue_statement ";" : wgsl_statement
syntax "discard" ";" : wgsl_statement
syntax wgsl_variable_updating_statement ";" : wgsl_statement
syntax wgsl_compound_statement : wgsl_statement
syntax wgsl_assert_statement ";" : wgsl_statement

-- compound_statement
syntax wgsl_attribute* "{" wgsl_statement* "}" : wgsl_compound_statement

-- assignment_statement
syntax wgsl_lhs_expression "=" wgsl_expression : wgsl_assignment_statement
syntax wgsl_lhs_expression wgsl_compound_assignment_operator wgsl_expression : wgsl_assignment_statement
syntax "_" "=" wgsl_expression : wgsl_assignment_statement

-- compound_assignment_operator
syntax "+=" : wgsl_compound_assignment_operator
syntax "-=" : wgsl_compound_assignment_operator
syntax "*=" : wgsl_compound_assignment_operator
syntax "/=" : wgsl_compound_assignment_operator
syntax "%=" : wgsl_compound_assignment_operator
syntax "&=" : wgsl_compound_assignment_operator
syntax "|=" : wgsl_compound_assignment_operator
syntax "^=" : wgsl_compound_assignment_operator
syntax ">>=" : wgsl_compound_assignment_operator
syntax "<<=" : wgsl_compound_assignment_operator

-- increment_statement
syntax wgsl_lhs_expression "++" : wgsl_increment_statement

-- decrement_statement
syntax wgsl_lhs_expression "--" : wgsl_decrement_statement

-- variable_updating_statement
syntax wgsl_assignment_statement : wgsl_variable_updating_statement
syntax wgsl_increment_statement : wgsl_variable_updating_statement
syntax wgsl_decrement_statement : wgsl_variable_updating_statement

-- return_statement
syntax "return" (wgsl_expression)? : wgsl_return_statement

-- func_call_statement
syntax wgsl_call_phrase : wgsl_func_call_statement

-- const_assert
syntax "const_assert" wgsl_expression : wgsl_const_assert

-- assert_statement
syntax wgsl_const_assert : wgsl_assert_statement

-- ============================================================
-- Control flow – if  (syntax rules)
-- ============================================================

-- if_statement
syntax wgsl_attribute* wgsl_if_clause wgsl_else_if_clause* (wgsl_else_clause)? : wgsl_if_statement

-- if_clause
syntax "if" wgsl_expression wgsl_compound_statement : wgsl_if_clause

-- else_if_clause
-- Use atomic to prevent "else" from being consumed when not followed by "if"
-- (otherwise else_if_clause* greedily eats "else" and blocks else_clause)
open Lean Parser in
@[wgsl_else_if_clause_parser] def wgslElseIfClause :=
  leadingNode `wgsl_else_if_clause 0
    (atomic (symbol "else" >> symbol "if") >>
     categoryParser `wgsl_expression 0 >>
     categoryParser `wgsl_compound_statement 0)

-- else_clause
syntax "else" wgsl_compound_statement : wgsl_else_clause

-- ============================================================
-- Control flow – switch  (syntax rules)
-- ============================================================

-- switch_statement
syntax wgsl_attribute* "switch" wgsl_expression wgsl_switch_body : wgsl_switch_statement

-- switch_body
syntax wgsl_attribute* "{" wgsl_switch_clause+ "}" : wgsl_switch_body

-- switch_clause
syntax wgsl_case_clause : wgsl_switch_clause
syntax wgsl_default_alone_clause : wgsl_switch_clause

-- case_clause
syntax "case" wgsl_case_selectors ":"? wgsl_compound_statement : wgsl_case_clause

-- default_alone_clause
syntax "default" ":"? wgsl_compound_statement : wgsl_default_alone_clause

-- case_selectors
syntax (wgsl_case_selector),+,? : wgsl_case_selectors

-- case_selector
syntax "default" : wgsl_case_selector
syntax wgsl_expression : wgsl_case_selector

-- ============================================================
-- Control flow – loops  (syntax rules)
-- ============================================================

-- loop_statement
syntax wgsl_attribute* "loop" wgsl_attribute* "{" wgsl_statement* (wgsl_continuing_statement)? "}" : wgsl_loop_statement

-- for_statement
syntax wgsl_attribute* "for" "(" wgsl_for_header ")" wgsl_compound_statement : wgsl_for_statement

-- for_header
syntax (wgsl_for_init)? ";" (wgsl_expression)? ";" (wgsl_for_update)? : wgsl_for_header

-- for_init
syntax wgsl_variable_or_value_statement : wgsl_for_init
syntax wgsl_variable_updating_statement : wgsl_for_init
syntax wgsl_func_call_statement : wgsl_for_init

-- for_update
syntax wgsl_variable_updating_statement : wgsl_for_update
syntax wgsl_func_call_statement : wgsl_for_update

-- while_statement
syntax wgsl_attribute* "while" wgsl_expression wgsl_compound_statement : wgsl_while_statement

-- ============================================================
-- Control flow – break / continue  (syntax rules)
-- ============================================================

-- break_statement
syntax "break" : wgsl_break_statement

-- break_if_statement
syntax "break" "if" wgsl_expression ";" : wgsl_break_if_statement

-- continue_statement
syntax "continue" : wgsl_continue_statement

-- continuing_statement
syntax "continuing" wgsl_continuing_compound_statement : wgsl_continuing_statement

-- continuing_compound_statement
syntax wgsl_attribute* "{" wgsl_statement* (wgsl_break_if_statement)? "}" : wgsl_continuing_compound_statement

-- ============================================================
-- Functions  (syntax rules)
-- ============================================================

-- function_decl
syntax wgsl_attribute* wgsl_function_header wgsl_compound_statement : wgsl_function_decl

-- function_header
syntax "fn" wgsl_ident "(" (wgsl_param_list)? ")" ("->" wgsl_attribute* wgsl_template_elaborated_ident)? : wgsl_function_header

-- param_list
syntax (wgsl_param),+,? : wgsl_param_list

-- param
syntax wgsl_attribute* wgsl_ident ":" wgsl_type_specifier : wgsl_param

-- ============================================================
-- Enable / requires directives  (syntax rules)
-- ============================================================

-- enable_directive
syntax "enable" wgsl_enable_extension_list ";" : wgsl_enable_directive

-- enable_extension_list
syntax (wgsl_enable_extension_name),+,? : wgsl_enable_extension_list

-- enable_extension_name
syntax wgsl_ident_pattern_token : wgsl_enable_extension_name

-- requires_directive
syntax "requires" wgsl_language_extension_list ";" : wgsl_requires_directive

-- language_extension_list
syntax (wgsl_language_extension_name),+,? : wgsl_language_extension_list

-- language_extension_name
syntax wgsl_ident_pattern_token : wgsl_language_extension_name

macro "!WGSL{" u:wgsl_translation_unit "}" : term => do
  return Lean.Syntax.mkStrLit u.raw.reprint.get! u.raw.getHeadInfo
