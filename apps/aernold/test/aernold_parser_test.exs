defmodule AernoldParserTest do
  use ExUnit.Case
  doctest Aernold

  test "variable_declaration_test" do
    assert Aernold.parse_string("Contract test{test:Int;}") ==
              {:contract, {:contract, 1}, {:id, 1, 'test'},
                {:decl_var, {:id, 'test'}, {:type, 1, 'Int'}}}
  end

  test "variable_definition_test" do
    assert Aernold.parse_string("Contract test{test:Int=5;}") ==
              {:contract, {:contract, 1}, {:id, 1, 'test'},
                {:def_var, {:id, 'test'}, {:type, 1, 'Int'}, {:int, 5}}}
  end

  test "multiple_simple_statements_test" do
    assert Aernold.parse_string("Contract test{test:Int=5;c:Address = 0x04711AC9E3;}") ==
              {:contract, {:contract, 1}, {:id, 1, 'test'},
                {{:def_var, {:id, 'test'}, {:type, 1, 'Int'}, {:int, 5}},
                {:def_var, {:id, 'c'}, {:type, 1, 'Address'}, {:hex, '04711AC9E3'}}}}
  end

  test "if_statement_test" do
    assert Aernold.parse_string("Contract test{if(a==b){test:Int=5;}}") ==
              {:contract, {:contract, 1}, {:id, 1, 'test'},
                {:if_statement, {{:id, 'a'}, {:==, 1}, {:id, 'b'}},
                  {:def_var, {:id, 'test'}, {:type, 1, 'Int'}, {:int, 5}}}}
  end

  test "if_else_statement_test" do
    assert Aernold.parse_string("Contract test{if(a==b){test:Int=10;}else{test:Int=5;}}") ==
              {:contract, {:contract, 1}, {:id, 1, 'test'},
                {:if_statement, {{:id, 'a'}, {:==, 1}, {:id, 'b'}},
                  {:def_var, {:id, 'test'}, {:type, 1, 'Int'}, {:int, 10}},
                    {:else_statement, {:def_var, {:id, 'test'}, {:type, 1, 'Int'}, {:int, 5}}}}}
  end

  test "else_if_statement_test" do
    assert Aernold.parse_string("Contract test{if(a==b){test:Int=5;}else if(a!=b){test:Int=10;}}") ==
            {:contract, {:contract, 1}, {:id, 1, 'test'},
              {:if_statement, {{:id, 'a'}, {:==, 1}, {:id, 'b'}},
                {:def_var, {:id, 'test'}, {:type, 1, 'Int'}, {:int, 5}},
              {:if_statement, {{:id, 'a'}, {:!=, 1}, {:id, 'b'}},
                {:def_var, {:id, 'test'}, {:type, 1, 'Int'}, {:int, 10}}}}}
  end

  test "function_definition_test" do
    assert Aernold.parse_string("Contract test{func foo(a:Int, key:String){test:Int=a+get_balance(key);}}") ==
          {:contract, {:contract, 1}, {:id, 1, 'test'},
           {:func_definition, {:id, 'foo'},
            {:func_params, {:decl_var, {:id, 'a'}, {:type, 1, 'Int'}},
             {:func_params, {:decl_var, {:id, 'key'}, {:type, 1, 'String'}}}},
            {:def_var, {:id, 'test'}, {:type, 1, 'Int'},
             {{:id, 'a'}, {:+, 1},
              {:func_call, {:id, 'get_balance'}, {:func_args, {:id, 'key'}}}}}}}
  end

  test "function_call_test" do
    assert Aernold.parse_string("Contract test{foo(a);bar(a,b);}") ==
          {:contract, {:contract, 1}, {:id, 1, 'test'},
            {{:func_call, {:id, 'foo'}, {:func_args, {:id, 'a'}}},
            {:func_call, {:id, 'bar'},
              {:func_args, {:id, 'a'}, {:func_args, {:id, 'b'}}}}}}
  end

  test "expressions_test" do
    assert Aernold.parse_string("Contract test{a=b+(c+d);}") ==
          {:contract, {:contract, 1}, {:id, 1, 'test'},
            {{:id, 'a'}, {:=, 1},
              {{:id, 'b'}, {:+, 1}, {{:id, 'c'}, {:+, 1}, {:id, 'd'}}}}}
  end

end
