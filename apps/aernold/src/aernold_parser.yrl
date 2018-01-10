Terminals
true false int operator contract id
type 'if' else

%%Symbols
':' ';' '=' '+' '-' '*' '/' '{' '}'
'(' ')' '=='

.
Nonterminals
file decls decl expr exprAtom exprType
opAdd opSub opMultiply opDivision
.

Rootsymbol file.

file -> decls : '$1'.

decls -> 'contract' id '{' decls '}' : {contract, '$1', '$2', '$4'}.

decls -> decl : '$1'.
decls -> decl ';' : '$1'.
decls -> decl ';' decls : {'$1', '$3'}.

decl -> exprAtom ':' exprType ';' : {decl_var, '$1', '$3'}.
decl -> exprAtom ':' exprType  '=' exprAtom ';' : {def_var, '$1', '$3', '$5'}.
decl -> expr : {decl_expr, '$1'}.

expr -> 'if' '(' expr ')' '{' decls '}' : {if_statemnet, '$1', '$3', '$6'}.
expr -> exprAtom '=' exprAtom ';' : {expr_assign, '$1', '$3'}.
expr -> exprAtom '==' exprAtom : {expr_eq, '$1', '$3'}.

exprType -> type : {type, '$1'}.

exprAtom -> int : {int, get_value('$1')}.
exprAtom -> id : {id, get_value('$1')}.

opAdd -> '+' : '$1'.
opSub -> '-' : '$1'
opMultiply -> '*' : '$1'.
opDivision -> '/' : '$1'.

Erlang code.

get_value({_,_,Value}) -> Value.

%[{:id, 1, 'a'}, {:":", 1}, {:type, 1, 'Int'}]
