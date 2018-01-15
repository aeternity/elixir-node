defmodule AernoldParserTest do
  use ExUnit.Case
  doctest Aernold

  test "variable declaration" do
    code =
      "Contract test {
         test:Int;
       }"

    assert Aernold.parse_string(code) ==
      {:contract, {:contract, 1}, {:id, 1, 'test'},
        {:decl_var, {:id, 'test'}, {:type, 2, 'Int'}}
      }
  end

  test "variable definition" do
    code =
      "Contract test {
         test:Int = 5;
       }"

    assert Aernold.parse_string(code) ==
      {:contract, {:contract, 1}, {:id, 1, 'test'},
        {:def_var, {:id, 'test'}, {:type, 2, 'Int'}, {:int, 5}}
      }
  end

  test "multiple simple statements" do
    code =
      "Contract test {
         test:Int = 5;
         c:Address = 0x04711AC9E3;
       }"

    assert Aernold.parse_string(code) ==
      {:contract, {:contract, 1}, {:id, 1, 'test'},
        {
          {:def_var, {:id, 'test'}, {:type, 2, 'Int'}, {:int, 5}},
          {:def_var, {:id, 'c'}, {:type, 3, 'Address'}, {:hex, '04711AC9E3'}}
        }
      }
  end

  test "if statement" do
    code =
      "Contract test {
         if(a == b) {
           test:Int = 5;
         }
       }"

    assert Aernold.parse_string(code) ==
      {:contract, {:contract, 1}, {:id, 1, 'test'},
        {:if_statement, {{:id, 'a'}, {:==, 2}, {:id, 'b'}},
          {:def_var, {:id, 'test'}, {:type, 3, 'Int'}, {:int, 5}}
        }
      }
  end

  test "if else statement" do
    code =
      "Contract test {
         test:Int;
         if(a == b) {
           test = 10;
         } else {
           test = 5;
         }
       }"

    assert Aernold.parse_string(code) ==
      {:contract, {:contract, 1}, {:id, 1, 'test'},
        {
          {:decl_var, {:id, 'test'}, {:type, 2, 'Int'}},
          {:if_statement, {{:id, 'a'}, {:==, 3}, {:id, 'b'}},
            {{:id, 'test'}, {:=, 4}, {:int, 10}},
          {:else_statement,
            {{:id, 'test'}, {:=, 6}, {:int, 5}}
          }
          }
        }
       }
  end

  test "if else if statement" do
    code =
      "Contract test {
         test:Int;
         if(a == b) {
           test = 5;
         } else if(a != b) {
           test = 10;
         }
       }"

    assert Aernold.parse_string(code) ==
      {:contract, {:contract, 1}, {:id, 1, 'test'},
        {
          {:decl_var, {:id, 'test'}, {:type, 2, 'Int'}},
          {:if_statement, {{:id, 'a'}, {:==, 3}, {:id, 'b'}},
            {{:id, 'test'}, {:=, 4}, {:int, 5}},
          {:if_statement, {{:id, 'a'}, {:!=, 5}, {:id, 'b'}},
            {{:id, 'test'}, {:=, 6}, {:int, 10}}
          }
          }
        }
      }
  end

  test "function definition" do
    code =
      "Contract test {
         func foo(a:Int, key:String) {
           test:Int = a + get_balance(key);
         }
       }"

    assert Aernold.parse_string(code) ==
      {:contract, {:contract, 1}, {:id, 1, 'test'},
        {:func_definition, {:id, 'foo'},
            {:func_params, {:decl_var, {:id, 'a'}, {:type, 2, 'Int'}},
            {:func_params, {:decl_var, {:id, 'key'}, {:type, 2, 'String'}}}},
          {:def_var, {:id, 'test'}, {:type, 3, 'Int'}, {{:id, 'a'}, {:+, 3},
          {:func_call, {:id, 'get_balance'}, {:func_args, {:id, 'key'}}}}}
        }
      }
  end

  test "function call" do
    code =
      "Contract test {
         foo(a);
         bar(a, b);
       }"

    assert Aernold.parse_string(code) ==
      {:contract, {:contract, 1}, {:id, 1, 'test'},
       {
        {:func_call, {:id, 'foo'},
          {:func_args, {:id, 'a'}}
        },
        {:func_call, {:id, 'bar'},
          {:func_args, {:id, 'a'},
          {:func_args, {:id, 'b'}}}
        }
       }
      }
  end

  test "expressions" do
    code =
      "Contract test {
         a = b + (c + d);
       }"

    assert Aernold.parse_string(code) ==
      {:contract, {:contract, 1}, {:id, 1, 'test'},
        {
          {:id, 'a'}, {:=, 2},{{:id, 'b'}, {:+, 2}, {{:id, 'c'}, {:+, 2}, {:id, 'd'}}}
        }
      }
  end

end
