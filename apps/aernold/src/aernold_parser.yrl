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
.
Nonterminals
expr
value
.
Rootsymbol value.

value ->
  true : true.
value ->
  false : false.
value ->
  int : {int, unwrap('$1')}.

Erlang code.

unwrap({_,_,V}) -> V.
