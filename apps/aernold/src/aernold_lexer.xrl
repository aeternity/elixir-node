Definitions.

DIGIT      = [0-9]
HEXDIGIT   = [0-9a-fA-F]
LOWER      = [a-z_]
UPPER      = [A-Z]
WHITESPACE = [\s\t\n\r]
ID         = {LOWER}[a-zA-Z0-9_]*
TYPE       = {UPPER}[a-zA-Z0-9]*
HEX        = 0x{HEXDIGIT}+
INT        = {DIGIT}+
DECL       = {ID}[:]{TYPE}
CON        = {}
OP         = [+\-=!<>:&|]

Rules.

Contract   : {token, {contract, TokenLine}}.
if         : {token, {'if', TokenLine}}.
else       : {token, {else, TokenLine}}.
func       : {token, {func, TokenLine}}.
true|false : {token, {bool, TokenLine, list_to_atom(TokenChars)}}.

: : {token, {':', TokenLine}}.
; : {token, {';', TokenLine}}.
{ : {token, {'{', TokenLine}}.
} : {token, {'}', TokenLine}}.
\( : {token, {'(', TokenLine}}.
\) : {token, {')', TokenLine}}.
, : {token, {',', TokenLine}}.

true|false   : {token, {bool, TokenLine, list_to_atom(TokenChars)}}.
{OP}+        : {token, {list_to_atom(TokenChars), TokenLine}}.
{INT}        : {token, {int, TokenLine, list_to_integer(TokenChars)}}.
{ID}         : {token, {id, TokenLine, TokenChars}}.
{TYPE}       : {token, {type, TokenLine, TokenChars}}.
{HEX}        : {token, {hex, TokenLine, parse_hex(TokenChars)}}.
{WHITESPACE} : skip_token.

Erlang code.

parse_hex("0x" ++ Chars) -> Chars.
