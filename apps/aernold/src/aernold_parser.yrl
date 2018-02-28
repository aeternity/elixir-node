Terminals
bool int contract id type 'if'
else switch 'case' foreach as func hex char string

%%Symbols
':' ';' '=' '+' '-' '*' '/' '%' '{' '}'
'(' ')' '&&' '||' '>' '<' '==' '<=' '.'
'>=' '!=' ',' '!' '[' ']' '=>' '%{' '++'
'--'
.

Nonterminals
File Contr Statement SimpleStatement CompoundStatement VariableDeclaration
VariableDefinition IfStatement ElseIfStatement ElseStatement SwitchStatement
SwitchCase Condition ForeachStatement
FunctionDefinition FunctionParameters FunctionCall FunctionArguments Expression
Id Type Value OpCondition OpCompare Op DataStructure TupleDefinition TupleValues
ListDeclaration ListDefinition ListValues MapDeclaration MapDefinition MapValues
Tuple List Map
.

Rootsymbol File.

File -> Contr : '$1'.

%Contr -> 'contract' Id '{' Statement '}' : {'$1', '$2', list_to_tuple('$4')}.
Contr -> 'contract' Id '(' FunctionParameters ')' '{' Statement '}' '(' FunctionArguments ')' ';' : {'$1', '$2', list_to_tuple('$4'), list_to_tuple('$10'), list_to_tuple('$7')}.
Contr -> 'contract' Id '(' ')' '{' Statement '}' '(' ')' ';' : {'$1', '$2', [], [], list_to_tuple('$6')}.

Statement -> SimpleStatement ';' : ['$1'].
Statement -> SimpleStatement ';' Statement : ['$1' | '$3'].
Statement -> CompoundStatement : ['$1'].
Statement -> CompoundStatement  Statement : ['$1' | '$2'].
Statement -> Expression ';' : ['$1'].
Statement -> Expression ';' Statement : ['$1' | '$3'].
Statement -> DataStructure ';' : ['$1'].
Statement -> DataStructure ';' Statement : ['$1' | '$3'].

DataStructure -> ListDeclaration : '$1'.
DataStructure -> ListDefinition : '$1'.
DataStructure -> MapDeclaration : '$1'.
DataStructure -> MapDefinition : '$1'.

SimpleStatement -> VariableDeclaration : '$1'.
SimpleStatement -> VariableDefinition : '$1'.

CompoundStatement -> IfStatement : {if_statement, list_to_tuple('$1')}.
CompoundStatement -> SwitchStatement : {switch_statement, '$1'}.
CompoundStatement -> ForeachStatement : {foreach_statement, '$1'}.
CompoundStatement -> FunctionDefinition : '$1'.

ListDeclaration -> Id ':' Type '<' Type '>' : {decl_list, '$1', '$3', '$5'}.
ListDefinition -> Id ':' Type '<' Type '>' '=' '[' ']' : {def_list, '$1', '$3', '$5', 'empty'}.
ListDefinition -> Id ':' Type '<' Type '>' '=' '[' ListValues ']' : {def_list, '$1', '$3', '$5', list_to_tuple('$9')}.

MapDeclaration -> Id ':' Type '<' Type ',' Type '>' : {decl_map, '$1', '$3', '$5', '$7'}.
MapDefinition -> Id ':' Type '<' Type ',' Type '>' '=' '%{' MapValues '}' : {def_map, '$1', '$3', '$5', '$7', list_to_tuple('$11')}.

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

ForeachStatement -> 'foreach' '(' Value 'as' Id ')' '{' Statement '}' : {'$3', {'$5'}, list_to_tuple('$8')}.
ForeachStatement -> 'foreach' '(' Value 'as' Id '=>' Id ')' '{' Statement '}' : {'$3', {'$5', '$7'}, list_to_tuple('$10')}.

FunctionDefinition -> 'func' Id '(' FunctionParameters ')' '{' Statement '}' : {func_definition, '$2', list_to_tuple('$4'), list_to_tuple('$7')}.

FunctionCall -> Id '(' ')' : {func_call, '$1'}.
FunctionCall -> Id '(' FunctionArguments ')' : {func_call, '$1', list_to_tuple('$3')}.
FunctionCall -> Type '.' Id '(' FunctionArguments ')' : {func_call, '$1', '$3', list_to_tuple('$5')}.

FunctionParameters -> VariableDeclaration : ['$1'].
FunctionParameters -> VariableDeclaration ',' FunctionParameters : ['$1' | '$3'].
FunctionParameters -> ListDeclaration : ['$1'].
FunctionParameters -> ListDeclaration ',' FunctionParameters : ['$1' | '$3'].
FunctionParameters -> MapDeclaration : ['$1'].
FunctionParameters -> MapDeclaration ',' FunctionParameters : ['$1' | '$3'].

FunctionArguments -> Expression : ['$1'].
FunctionArguments -> Expression ',' FunctionArguments : ['$1' | '$3'].

Condition -> Expression : '$1'.
Condition -> Expression OpCondition Condition : {'$1', '$2', '$3'}.

Expression -> Value : '$1'.
Expression -> '!' Value : {'$1', '$2'}.
Expression -> Expression OpCompare Expression : {'$1', '$2', '$3'}.
Expression -> Expression Op Expression : {'$1', '$2', '$3'}.
Expression -> '(' Expression ')' : '$2'.
Expression -> '!' '(' Expression ')' : {'$1', '$3'}.
Expression -> '(' Expression ')' Op Expression : {'$2', '$4', '$5'}.
Expression -> '!' '(' Expression ')' Op Expression : {'$3', '$5', '$6'}.

Id -> id : {id, get_value('$1')}.
Type -> type : {type, get_value('$1')}.

Tuple -> '{' '}' : 'empty'.
Tuple -> '{' TupleValues '}' : '$2'.

TupleValues -> Expression : ['$1'].
TupleValues -> Expression ',' TupleValues: ['$1' | '$3'].

List -> '[' ']' : 'empty'.
List -> '[' ListValues ']' : '$2'.

ListValues -> Expression : ['$1'].
ListValues -> Expression ',' ListValues: ['$1' | '$3'].

Map -> '%{' '}' : 'empty'.
Map -> '%{' MapValues '}' : list_to_tuple('$2').

MapValues -> Expression '=>' Expression : [{'$1', '$3'}].
MapValues -> Expression '=>' Expression ',' MapValues : [{'$1', '$3'} | '$5'].

Value -> Id : '$1'.
Value -> FunctionCall : '$1'.
Value -> List : {list, '$1'}.
Value -> Tuple : {tuple, '$1'}.
Value -> Map : {map, '$1'}.
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
Op -> '%' : '$1'.
Op -> '=' : '$1'.
Op -> '++': '$1'.
Op -> '--': '$1'.

Erlang code.

get_value({_, _, Value}) -> Value.
