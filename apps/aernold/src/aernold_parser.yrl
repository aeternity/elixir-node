Terminals
bool int operator contract id
type 'if' else

%%Symbols
':' ';' '=' '+' '-' '*' '/' '{' '}'
'(' ')' '&&' '||' '>' '<' '==' '<='
'>=' '!='
.

Nonterminals
File Contr Statement SimpleStatement CompoundStatement VariableDeclaration
VariableDefinition IfStatement ElseIfStatement ElseStatement Condition
Expression Type Atom OpCondition OpCompare Op
.

Rootsymbol File.

File -> Contr : '$1'.

Contr -> 'contract' id '{' Statement '}' : {contract, '$1', '$2', '$4'}.

Statement -> SimpleStatement ';' : '$1'.
Statement -> SimpleStatement ';' Statement : {'$1', '$3'}.
Statement -> CompoundStatement : '$1'.
Statement -> Expression ';' : '$1'.
Statement -> Expression ';' Statement : {'$1', '$3'}.

SimpleStatement -> VariableDeclaration : '$1'.
SimpleStatement -> VariableDefinition : '$1'.

CompoundStatement -> IfStatement : '$1'.

VariableDeclaration -> Atom ':' Type : {decl_var, '$1', '$3'}.
VariableDefinition -> Atom ':' Type  '=' Atom : {def_var, '$1', '$3', '$5'}.

IfStatement -> 'if' '(' Condition ')' '{' Statement '}' : {if_statement, '$1', '$3', '$6'}.
IfStatement -> 'if' '(' Condition ')' '{' Statement '}' ElseIfStatement : {if_statement, '$1', '$3', '$6', '$8'}.
ElseIfStatement -> 'else' 'if' '(' Condition ')' '{' Statement '}' : {if_statement, '$1', '$3', '$6'}.
ElseIfStatement -> 'else' 'if' '(' Condition ')' '{' Statement '}' ElseIfStatement : {if_statement, '$1', '$3', '$6', '$8'}.
ElseIfStatement -> 'else' 'if' '(' Condition ')' '{' Statement '}' ElseStatement : {if_statement, '$1', '$3', '$6', '$8'}.
ElseStatement -> 'else' '{' Statement '}' : {if_statement, '$1', '$3'}.

Condition -> Expression : '$1'.
Condition -> Expression OpCondition Condition : {'$1', '$2', '$3'}.

Expression -> Atom : '$1'.
Expression -> Atom OpCompare Expression : {'$1', '$2', '$3'}.
Expression -> Atom Op Expression : {'$1', '$2', '$3'}.

Type -> type : {type, '$1'}.

Atom -> id : {id, get_value('$1')}.
Atom -> int : {int, get_value('$1')}.
Atom -> bool : {bool, get_value('$1')}.

OpCondition -> '&&' : '$1'.
OpCondition -> '||' : '$1'.

OpCompare -> '>' : '$1'.
OpCompare -> '<' : '$1'.
OpCompare -> '==' : '$1'.
OpCompare -> '<=' : '$1'.
OpCompare -> '>=' : '$1'.
OpCompare -> '!=' : '$1'.

Op -> '+' : '$1'.
Op -> '-' : '$1'.
Op -> '*' : '$1'.
Op -> '/' : '$1'.
Op -> '=' : '$1'.

Erlang code.

get_value({_,_,Value}) -> Value.

%[{:id, 1, 'a'}, {:":", 1}, {:type, 1, 'Int'}]
