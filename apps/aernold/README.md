Implementing prototype parser and lexer for a smart contract language

WIP: Implementing an elixir interpreter for the language.

## Example:

```
Contract contract_name() {

  func sum(first:Int, second:Int){
    first+second;
  }

  a:Int = 5;
  c:Hex = 0x04711AC9E3D5EA12D948A41F8661C498CC5DF93B85C1E91172E571B312EB56AAD2046845456FA416F3DF5D04954AD6E6C6A8FF13A11DA574542B56F58DEFF052E4;
  b:Int = account_balance(c);

 foo(a, b);

}();
```
Example might change in the course of development, so can the syntax

### Time frame: 20.12.2017 - 20.01.2018 (Parser and lexer done in the most part)
### Interpreter: WIP

## What we achieved:
We used the erlang tools leex and yecc to make the lexer and the parser. The rules defined in the lexer are used to create **TokensChars**, which are then given to the parser that creates a grammar based on the rules defined in it.

#### The Lexer:
The lexer recognizes digits, letters(upper, lower case), operators, keywords(Contract, if, else, func, true, false), types(bool, int, id, type, hex)

#### The Parser:
We created a simple grammar that can be expanded if needed. The syntax is:

### Interpreter
To use the interpreter you can either call `Aernold.parse_string(contract)` or `Aernold.parse_file(file)`

1. Every implementation must start with **Contract** followed by the contract name:

    ```
    Contract example {
      content of the contract
    }
    ```

2. Every contract contains **Statement**, these statements can be:

  - **SimpleStatement** - that is *VariableDeclaration* or *VariableDefinition*

    ```
      example:Int;
      example1:Int = 5;
    ```

  - **CompoundStatemnt** - that is *IfStatement* or *FunctionDefinition*

    ```
      if(a==b){
        test = 5;
      }

      multiply(first:Int, second:Int){
        result = first * second;
      }
    ```

  - **Expression** - that is every expression with some sort of operator *OP* or *Value*

    ```
      test = 5;
      a = test * 5 - (10 - test);
    ```

3. The type of values we support are *int*, *bool*, *hex*, *char*, *string*

    ```
      num:Int = 5;
      test:Bool = true;
      key:Hex = 0x04711AC9E3;
      c:Char = 'c';
      word:String = "word";
    ```

4. Data Structures

  **List**

 List are homogeneous data structures. You can bound lists to a variable as well as use them as is in functions are locally.

  ```
    list:List<Int>;
    list:List<Int>  = [1, 2];
    [1, 2];
    insert_at([1,2], 0, 2);
  ```

  Built-in functions for lists:

  - Returns the value at given index in a list:

    `List.at(list, index);`

  - Returns the size of a given list:

    `List.size(list);`

  - Inserts an element at a given index :

    `List.insert_at(list, index, value);`

  - Deletes an element at a given index:

    `List.delete_at(list, index);`

  - Reverse a list:

    `List.reverse(list);`

  **Tuple**

  Tuple are data structures with fixed number of elements and a tuple can
  contain elements of different types.

  ```
    tuple:Tuple;
    tuple:Tuple = {1, true, "String", 'char'};
    {1, true, "String", 'char'};
    insert_at({1, 2}, 0, 2);

  ```

  Built-in functions for tuples:

  - Returns the value at given index in a tuple:

    `Tuple.elem(tuple, index);`

  - Returns the size of a given tuple:

    `Tuple.size(tuple);`

  - Inserts an element at a given index:

    `Tuple.insert_at(tuple, index, value);`

  - Deletes an element at a given index:

    `Tuple.delete_at(tuple, index);`

  - Appends a value at the end of a tuple:

  - `Tuple.append(tuple, value);`

  **Map**

  Map is a key-value data structure

  ```

    map:Map<Int, String>;
    map:Map = %{1 => "one", 2 => "two"};
    %{true => "yes", false => "no"};

  ```

  Built-in functions for maps:

  - Returns the value of a specific key:

    `Tuple.get(map, key);`

  - Inserts a given key-value pair into the map:

    `Map.put(map, key, value);`

  - Deletes the entry in a map for a specific key:

    `Map.delete(map, key);`  

  **Built-in functions**

  - Returns the integer value of tokens that an account has:

    `account_balance(hex_address);`

  More are going to be added, soon.
