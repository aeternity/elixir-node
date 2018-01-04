Terminals
true
false
int
operator
contract
id
type
'if'
else

%%Symbols
':'
';'
'='
.
Nonterminals
decl
expr
value
.
Rootsymbol value.

value -> true : true.
value -> false : false.
value -> int : {int, get_value('$1')}.
value -> id : {id, get_value('$1')}.

decl -> id ':' type  : {type_decl, '$1', '$2'}.
decl -> expr '=' int ';': {type_decl, '$1', '$2',[], get_value('$3'), []}.


Erlang code.

get_value({_,_,Value}) -> Value.
