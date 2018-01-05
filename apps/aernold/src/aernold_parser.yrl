Terminals
true false int operator contract id
type 'if' else

%%Symbols
':' ';' '=' '+' '-'

.
Nonterminals
file decl decls expr exprId exprAtom
exprType
.

Rootsymbol file.

file -> decls : '$1'.

decls -> '$empty' : [].
decls -> decl : '$1'.

decl -> exprAtom ':' exprType : {decl, ['$1'|'$3']}.
decl -> exprAtom ':' exprType  '=' exprAtom ';': {decl, ['$1'|'$3'], '$5'}.

%name 'decl' for the lines below needs to be changed for something more appropriate
decl -> exprId : {decl_id, '$1'}.
decl -> exprAtom : {decl_atom, '$1'}.
decl -> exprType : {decl_type, '$1'}.

expr -> exprAtom operator exprAtom : {expr_calc, '$1', '$3'}.

%value -> true : true.
%value -> false : false.
exprAtom -> int : {int, get_value('$1')}.
exprId -> id : '$1'.
exprType -> type : '$1'.

Erlang code.

get_value({_,_,Value}) -> Value.

%[{:decl, 1, ['a', 'Int']}, {:=, 1}, {:int, 1, 5}, {:";", 1}]
