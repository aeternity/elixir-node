Terminals
true false int operator contract id
type 'if' else

%%Symbols
':' ';' '=' '+' '-' '{' '}'

.
Nonterminals
file decl decls decls1 expr exprId exprAtom
exprType addOp
.

Rootsymbol file.

file -> decls : '$1'.

decls -> 'contract' id '{' decls '}' : {contract, '$1', '$2', '$4'}.

decls -> decl : '$1'.
decls -> decl ';' : '$1'.
decls -> decl ';' decls : {'$1', '$3'}.

decl -> exprId ':' exprType ';' : {decl, '$1', '$3'}.
decl -> exprId ':' exprType  '=' exprAtom ';' : {assign, '$1', '$3', '$5'}.

%name 'decl' for the lines below needs to be changed for something more appropriate
decl -> exprId : {decl_id, '$1'}.
decl -> exprAtom : {decl_atom, '$1'}.
decl -> exprType : {decl_type, '$1'}.

expr -> exprAtom addOp exprAtom : {expr_add, '$1', '$3'}.

%value -> true : true.
%value -> false : false.
exprAtom -> int : {int, get_value('$1')}.
exprId -> id : '$1'.
exprType -> type : '$1'.

addOp -> '+' : '$1'.

Erlang code.

get_value({_,_,Value}) -> Value.

%[{:id, 1, 'a'}, {:":", 1}, {:type, 1, 'Int'}]
