Terminals
bool int contract id type 'if'
else switch 'case' func hex char string

%%Symbols
':' ';' '=' '+' '-' '*' '/' '{' '}'
'(' ')' '&&' '||' '>' '<' '==' '<='
'>=' '!=' ',' '!' '[' ']'
.

Nonterminals
File Contr Statement SimpleStatement CompoundStatement VariableDeclaration
VariableDefinition IfStatement ElseIfStatement ElseStatement SwitchStatement
SwitchCase Condition
FunctionDefinition FunctionParameters FunctionCall FunctionArguments Expression
Id Type Value OpCondition OpCompare Op DataStructure TupleDefinition TupleValues
ListDeclaration ListDefinition ListValues Tuple
.

Rootsymbol File.

File -> Contr : '$1'.

Contr -> 'contract' Id '{' Statement '}' : {'$1', '$2', list_to_tuple('$4')}.

Statement -> SimpleStatement ';' : ['$1'].
Statement -> SimpleStatement ';' Statement : ['$1' | '$3'].
Statement -> CompoundStatement : ['$1'].
Statement -> CompoundStatement  Statement : ['$1' | '$2'].
Statement -> Expression ';' : ['$1'].
Statement -> Expression ';' Statement : ['$1' | '$3'].
Statement -> DataStructure ';' : ['$1'].
Statement -> DataStructure ';' Statement : ['$1' | '$3'].

% DataStructure -> TupleDefinition : '$1'.
DataStructure -> TupleDefinition : '$1'.
DataStructure -> ListDeclaration : '$1'.
DataStructure -> ListDefinition : '$1'.

SimpleStatement -> VariableDeclaration : '$1'.
SimpleStatement -> VariableDefinition : '$1'.

CompoundStatement -> IfStatement : {if_statement, list_to_tuple('$1')}.
CompoundStatement -> SwitchStatement : {switch_statement, '$1'}.
CompoundStatement -> FunctionDefinition : '$1'.

%TODO: to be able to do {}; or {1,2};
TupleDefinition -> Id ':' Type '=' '{' '}' : {def_tuple, '$1', '$3', empty}.
TupleDefinition -> Id ':' Type '=' '{' TupleValues '}': {def_tuple, '$1', '$3', list_to_tuple('$6')}.

%TODO: to be able to do []; or [1,2};
ListDeclaration -> Id ':' Type '<' Type '>' : {decl_list, '$1', '$3', '$5'}.
ListDefinition -> Id ':' Type '<' Type '>' '=' '[' ']' : {def_list, '$1', '$3', '$5', 'empty'}.
ListDefinition -> Id ':' Type '<' Type '>' '=' '[' ListValues ']' : {def_list, '$1', '$3', '$5', list_to_tuple('$9')}.

VariableDeclaration -> Id ':' Type : {decl_var, '$1', '$3'}.
VariableDefinition -> Id ':' Type  '=' Expression : {def_var, '$1', '$3', '$5'}.

IfStatement -> 'if' '(' Condition ')' '{' Statement '}' : [{'$3', list_to_tuple('$6')}].
IfStatement -> 'if' '(' Condition ')' '{' Statement '}' ElseStatement : [{'$3', list_to_tuple('$6')} | '$8'].
IfStatement -> 'if' '(' Condition ')' '{' Statement '}' ElseIfStatement : [{'$3', list_to_tuple('$6')} | '$8'].
ElseIfStatement -> 'else' 'if' '(' Condition ')' '{' Statement '}' : [{'$4', list_to_tuple('$7')}].
ElseIfStatement -> 'else' 'if' '(' Condition ')' '{' Statement '}' ElseIfStatement : [{'$4', list_to_tuple('$7')} | '$9'].
ElseIfStatement -> 'else' 'if' '(' Condition ')' '{' Statement '}' ElseStatement : [{'$4', list_to_tuple('$7')} | '$9'].
ElseStatement -> 'else' '{' Statement '}' : [{{bool, true}, list_to_tuple('$3')}].

SwitchStatement -> switch '(' Expression ')' '{' SwitchCase '}' : {'$3', list_to_tuple('$6')}.

SwitchCase -> 'case' Expression ':' Statement : [{'$2', list_to_tuple('$4')}].
SwitchCase -> 'case' Expression ':' Statement SwitchCase : [{'$2', list_to_tuple('$4')} | '$5'].

FunctionDefinition -> 'func' Id '(' FunctionParameters ')' '{' Statement '}' : {func_definition, '$2', list_to_tuple('$4'), list_to_tuple('$7')}.

FunctionCall -> Id '(' ')' : {func_call, '$1'}.
FunctionCall -> Id '(' FunctionArguments ')' : {func_call, '$1', list_to_tuple('$3')}.

FunctionParameters -> VariableDeclaration : ['$1'].
FunctionParameters -> VariableDeclaration ',' FunctionParameters : ['$1' | '$3'].

FunctionArguments -> Expression : ['$1'].
FunctionArguments -> Expression ',' FunctionArguments : ['$1' | '$3'].

Condition -> Expression : '$1'.
Condition -> Expression OpCondition Condition : {'$1', '$2', '$3'}.

Expression -> Value : '$1'.
Expression -> DataStructure : '$1'.
Expression -> '!' Value : {'$1', '$2'}.
Expression -> Expression OpCompare Expression : {'$1', '$2', '$3'}.
Expression -> Expression Op Expression : {'$1', '$2', '$3'}.
Expression -> '(' Expression ')' : '$2'.
Expression -> '!' '(' Expression ')' : {'$1', '$3'}.
Expression -> '(' Expression ')' Op Expression : {'$2', '$4', '$5'}.
Expression -> '!' '(' Expression ')' Op Expression : {'$3', '$5', '$6'}.

Id -> id : {id, get_value('$1')}.
Type -> type : {type, get_value('$1')}.

% Tuple -> '{' '}' : {}.
% Tuple -> '{' TupleValues '}' : '$2'.

TupleValues -> Value : ['$1'].
TupleValues -> Value ',' TupleValues: ['$1' | '$3'].

ListValues -> Value : ['$1'].
ListValues -> Value ',' ListValues: ['$1' | '$3'].

Value -> Id : '$1'.
Value -> FunctionCall : '$1'.
Value -> int : {int, get_value('$1')}.
Value -> bool : {bool, get_value('$1')}.
Value -> hex : {hex, get_value('$1')}.
Value -> char : {char, get_value('$1')}.
Value -> string : {string, get_value('$1')}.

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

get_value({_, _, Value}) -> Value.

%get_hex_value({_, _, Value}) -> "0x" ++ Value.
