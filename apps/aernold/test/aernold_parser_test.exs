defmodule AernoldParserTest do
  use ExUnit.Case
  doctest Aernold

  test "variable declaration" do
    code =
      'Contract test() {
         test:Int;
       }();'

    {:ok, tokens, _} = :aernold_lexer.string(code)
    {:ok, ast} = :aernold_parser.parse(tokens)

    assert ast ==
      {{:contract, 1}, {:id, 'test'}, [], [],
        {
          {:decl_var, {:id, 'test'}, {:type, 'Int'}}
        }
      }
  end

  test "variable definition" do
    code =
      'Contract test() {
         test:Int = 5;
       }();'

    {:ok, tokens, _} = :aernold_lexer.string(code)
    {:ok, ast} = :aernold_parser.parse(tokens)

    assert ast ==
      {{:contract, 1}, {:id, 'test'}, [], [],
        {
          {:def_var, {:id, 'test'}, {:type, 'Int'}, {:int, 5}}
        }
      }
  end

  test "multiple simple statements" do
    code =
      'Contract test() {
         test:Int = 5;
         c:Address = 0x04711AC9E3;
       }();'

    {:ok, tokens, _} = :aernold_lexer.string(code)
    {:ok, ast} = :aernold_parser.parse(tokens)

    assert ast ==
      {{:contract, 1}, {:id, 'test'}, [], [],
        {
          {:def_var, {:id, 'test'}, {:type, 'Int'}, {:int, 5}},
          {:def_var, {:id, 'c'}, {:type, 'Address'}, {:hex, '04711AC9E3'}}
        }
      }
  end

  test "if statement" do
    code =
      'Contract test() {
         if(a == b) {
           test:Int = 5;
         }
       }();'

    {:ok, tokens, _} = :aernold_lexer.string(code)
    {:ok, ast} = :aernold_parser.parse(tokens)

    assert ast ==
      {{:contract, 1}, {:id, 'test'}, [], [],
        {
          {:if_statement, {
            {{{:id, 'a'}, {:==, 2}, {:id, 'b'}},
              {
                {:def_var, {:id, 'test'}, {:type, 'Int'}, {:int, 5}}
              }
            }
          }
        }
      }}
  end

  test "if else statement" do
    code =
      'Contract test() {
         test:Int;
         if(a == b) {
           test = 10;
         } else {
           test = 5;
         }
       }();'

    {:ok, tokens, _} = :aernold_lexer.string(code)
    {:ok, ast} = :aernold_parser.parse(tokens)

    assert ast ==
      {{:contract, 1}, {:id, 'test'}, [], [],
        {
          {:decl_var, {:id, 'test'}, {:type, 'Int'}},
          {:if_statement, {
            {{{:id, 'a'}, {:==, 3}, {:id, 'b'}}, {
              {{:id, 'test'}, {:=, 4}, {:int, 10}}
            }},
            {{:bool, true}, {
              {{:id, 'test'}, {:=, 6}, {:int, 5}}
            }}
          }}
        }}
  end

  test "if else if statement" do
    code =
      'Contract test() {
         test:Int;
         if(a == b) {
           test = 5;
         } else if(a != b) {
           test = 10;
         }
       }();'

    {:ok, tokens, _} = :aernold_lexer.string(code)
    {:ok, ast} = :aernold_parser.parse(tokens)

    assert ast ==
      {{:contract, 1}, {:id, 'test'}, [], [], {
        {:decl_var, {:id, 'test'}, {:type, 'Int'}},
        {:if_statement, {
          {{{:id, 'a'}, {:==, 3}, {:id, 'b'}}, {
            {{:id, 'test'}, {:=, 4}, {:int, 5}}
          }},
          {{{:id, 'a'}, {:!=, 5}, {:id, 'b'}}, {
            {{:id, 'test'}, {:=, 6}, {:int, 10}}
          }}
        }}
      }}
  end

  test "function definition" do
    code =
      'Contract test() {
         func foo(a:Int, key:String) {
           test:Int = a + get_balance(key);
         }
       }();'

    {:ok, tokens, _} = :aernold_lexer.string(code)
    {:ok, ast} = :aernold_parser.parse(tokens)

    assert ast ==
      {{:contract, 1}, {:id, 'test'}, [], [], {
        {:func_definition, {:id, 'foo'},
          {{:decl_var, {:id, 'a'}, {:type, 'Int'}}, {:decl_var, {:id, 'key'}, {:type, 'String'}}}, {
            {:def_var, {:id, 'test'}, {:type, 'Int'},
              {{:id, 'a'}, {:+, 3}, {:func_call, {:id, 'get_balance'}, {{:id, 'key'}}}}
            }
          }
        }
      }}
  end

  test "function call" do
    code =
      'Contract test() {
         foo(a);
         bar(a, b);
       }();'

    {:ok, tokens, _} = :aernold_lexer.string(code)
    {:ok, ast} = :aernold_parser.parse(tokens)

    assert ast ==
      {{:contract, 1}, {:id, 'test'}, [], [], {
        {:func_call, {:id, 'foo'}, {{:id, 'a'}}},
        {:func_call, {:id, 'bar'}, {{:id, 'a'}, {:id, 'b'}}}
      }}
  end

  test "expressions" do
    code =
      'Contract test() {
         a = b + (c + d);
       }();'

    {:ok, tokens, _} = :aernold_lexer.string(code)
    {:ok, ast} = :aernold_parser.parse(tokens)

    assert ast ==
      {{:contract, 1}, {:id, 'test'}, [], [], {
        {{:id, 'a'}, {:=, 2}, {
          {:id, 'b'}, {:+, 2}, {
            {:id, 'c'}, {:+, 2}, {:id, 'd'}
          }
        }}
      }}
  end

end
