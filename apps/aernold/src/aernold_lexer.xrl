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
OP         = [+\-=!<>:&|/*%]

CHARTEXT = ([^\'\\]|(\\.))
STRINGTEXT = ([^\"\\]|(\\.))

Rules.
%%'

Contract   : {token, {contract, TokenLine}}.
if         : {token, {'if', TokenLine}}.
else       : {token, {else, TokenLine}}.
switch     : {token, {switch, TokenLine}}.
case       : {token, {'case', TokenLine}}.
foreach    : {token, {foreach, TokenLine}}.
as         : {token, {as, TokenLine}}.
func       : {token, {func, TokenLine}}.
true|false : {token, {bool, TokenLine, list_to_atom(TokenChars)}}.

: : {token, {':', TokenLine}}.
; : {token, {';', TokenLine}}.
{ : {token, {'{', TokenLine}}.
} : {token, {'}', TokenLine}}.
\( : {token, {'(', TokenLine}}.
\) : {token, {')', TokenLine}}.
, : {token, {',', TokenLine}}.
\[ : {token, {'[', TokenLine}}.
\] : {token, {']', TokenLine}}.
\%{ : {token, {'%{', TokenLine}}.
=> : {token, {'=>', TokenLine}}.
\. : {token, {'.', TokenLine}}.
\+\+ : {token, {'++', TokenLine}}.
\-\- : {token, {'--', TokenLine}}.

"{STRINGTEXT}*" : parse_string(TokenLine, TokenChars).
'{CHARTEXT}'    : parse_char(TokenLine, TokenChars).

true|false   : {token, {bool, TokenLine, list_to_atom(TokenChars)}}.
{OP}+        : {token, {list_to_atom(TokenChars), TokenLine}}.
{INT}        : {token, {int, TokenLine, list_to_integer(TokenChars)}}.
{ID}         : {token, {id, TokenLine, TokenChars}}.
{TYPE}       : {token, {type, TokenLine, TokenChars}}.
{HEX}        : {token, {hex, TokenLine, parse_hex(TokenChars)}}.
{WHITESPACE} : skip_token.

Erlang code.

parse_hex("0x" ++ Chars) -> Chars.

parse_string(Line, [$" | Chars]) ->
    unescape(Line, Chars).

parse_char(Line, [$', $\\, Code, $']) ->
    Ok = fun(C) -> {token, {char, Line, C}} end,
    case Code of
        $'  -> Ok($');
        $\\ -> Ok($\\);
        $b  -> Ok($\b);
        $e  -> Ok($\e);
        $f  -> Ok($\f);
        $n  -> Ok($\n);
        $r  -> Ok($\r);
        $t  -> Ok($\t);
        $v  -> Ok($\v);
        _   -> {error, "Bad control sequence: \\" ++ [Code]}
    end;
parse_char(Line, [$', C, $']) -> {token, {char, Line, C}}.

unescape(Line, Str) -> unescape(Line, Str, []).
unescape(Line, [$"], Acc) ->
    {token, {string, Line, list_to_binary(lists:reverse(Acc))}};
unescape(Line, [$\\, Code | Chars], Acc) ->
    Ok = fun(C) -> unescape(Line, Chars, [C | Acc]) end,
    case Code of
        $"  -> Ok($");
        $\\ -> Ok($\\);
        $b  -> Ok($\b);
        $e  -> Ok($\e);
        $f  -> Ok($\f);
        $n  -> Ok($\n);
        $r  -> Ok($\r);
        $t  -> Ok($\t);
        $v  -> Ok($\v);
        _   -> {error, "Bad control sequence: \\" ++ [Code]}
    end;
unescape(Line, [C | Chars], Acc) ->
    unescape(Line, Chars, [C | Acc]).
