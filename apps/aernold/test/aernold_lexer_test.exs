defmodule AernoldLexerTest do

  use ExUnit.Case

  test "variable declaration" do
    code =
      'Contract test {
         test:Int;
       }'

    assert :aernold_lexer.string(code) ==
      {:ok, [
              {:contract, 1}, {:id, 1, 'test'}, {:"{", 1},
              {:id, 2, 'test'}, {:":", 2}, {:type, 2, 'Int'}, {:";", 2},
              {:"}", 3}
            ], 3}
  end

  test "variable definition" do
    code =
      'Contract test {
         test:Int = 5;
       }'

    assert :aernold_lexer.string(code) ==
      {:ok, [
              {:contract, 1}, {:id, 1, 'test'}, {:"{", 1},
              {:id, 2, 'test'}, {:":", 2}, {:type, 2, 'Int'}, {:=, 2}, {:int, 2, 5}, {:";", 2},
              {:"}", 3}
            ], 3}

  end

  test "multiple simple statements" do
    code =
      'Contract test {
         test:Int = 5;
         c:Address = 0x0x04711AC9E3;
       }'

    assert :aernold_lexer.string(code) ==
      {:ok, [
              {:contract, 1}, {:id, 1, 'test'}, {:"{", 1},
              {:id, 2, 'test'}, {:":", 2}, {:type, 2, 'Int'}, {:=, 2}, {:int, 2, 5}, {:";", 2},
              {:id, 3, 'c'}, {:":", 3}, {:type, 3, 'Address'}, {:=, 3}, {:hex, 3, '0'},
                {:id, 3, 'x04711AC9E3'}, {:";", 3},
              {:"}", 4}
            ], 4}
  end

  test "if statement" do
    code =
      'Contract test {
         if(a == b) {
           test:Int = 5;
         }
       }'

    assert :aernold_lexer.string(code) ==
      {:ok, [
              {:contract, 1}, {:id, 1, 'test'}, {:"{", 1},
              {:if, 2}, {:"(", 2}, {:id, 2, 'a'}, {:==, 2}, {:id, 2, 'b'},
                {:")", 2}, {:"{", 2},
              {:id, 3, 'test'}, {:":", 3}, {:type, 3, 'Int'}, {:=, 3},
                {:int, 3, 5}, {:";", 3},
              {:"}", 4},
              {:"}", 5}
            ], 5}
  end

  test "if else statement" do
    code =
      'Contract test {
         test:Int;
         if(a == b) {
           test = 10;
         } else {
           test = 5;
         }
       }'

    assert :aernold_lexer.string(code) ==
      {:ok, [
              {:contract, 1}, {:id, 1, 'test'}, {:"{", 1},
              {:id, 2, 'test'}, {:":", 2}, {:type, 2, 'Int'}, {:";", 2},
              {:if, 3}, {:"(", 3}, {:id, 3, 'a'}, {:==, 3},
                {:id, 3, 'b'}, {:")", 3}, {:"{", 3},
              {:id, 4, 'test'}, {:=, 4}, {:int, 4, 10},{:";", 4},
              {:"}", 5}, {:else, 5}, {:"{", 5},
              {:id, 6, 'test'}, {:=, 6}, {:int, 6, 5}, {:";", 6},
              {:"}", 7},
              {:"}", 8}
            ], 8}
  end

  test "if else if statement" do
    code =
      'Contract test {
         test:Int;
         if(a == b) {
           test = 5;
         } else if(a != b) {
           test = 10;
         }
       }'

    assert :aernold_lexer.string(code) ==
      {:ok, [
              {:contract, 1}, {:id, 1, 'test'}, {:"{", 1},
              {:id, 2, 'test'}, {:":", 2}, {:type, 2, 'Int'}, {:";", 2},
              {:if, 3}, {:"(", 3}, {:id, 3, 'a'}, {:==, 3},
                {:id, 3, 'b'}, {:")", 3}, {:"{", 3},
              {:id, 4, 'test'}, {:=, 4}, {:int, 4, 5}, {:";", 4},
              {:"}", 5}, {:else, 5}, {:if, 5}, {:"(", 5}, {:id, 5, 'a'},
                {:!=, 5}, {:id, 5, 'b'}, {:")", 5}, {:"{", 5},
              {:id, 6, 'test'}, {:=, 6}, {:int, 6, 10}, {:";", 6},
              {:"}", 7},
              {:"}", 8}
            ], 8}
  end

  test "function definition" do
    code =
      'Contract test {
         func foo(a:Int, key:String) {
           test:Int = a + get_balance(key);
         }
       }'

    assert :aernold_lexer.string(code) ==
      {:ok, [
              {:contract, 1}, {:id, 1, 'test'}, {:"{", 1},
              {:func, 2}, {:id, 2, 'foo'}, {:"(", 2}, {:id, 2, 'a'}, {:":", 2},
                {:type, 2, 'Int'}, {:",", 2}, {:id, 2, 'key'}, {:":", 2},
                {:type, 2, 'String'}, {:")", 2}, {:"{", 2},
              {:id, 3, 'test'}, {:":", 3}, {:type, 3, 'Int'}, {:=, 3}, {:id, 3, 'a'}, {:+, 3},
                {:id, 3, 'get_balance'}, {:"(", 3}, {:id, 3, 'key'}, {:")", 3}, {:";", 3},
              {:"}", 4},
              {:"}", 5}
            ], 5}
  end

  test "function call" do
    code =
      'Contract test {
         foo(a);
         bar(a, b);
       }'

    assert :aernold_lexer.string(code) ==
      {:ok, [
              {:contract, 1}, {:id, 1, 'test'}, {:"{", 1},
              {:id, 2, 'foo'}, {:"(", 2}, {:id, 2, 'a'}, {:")", 2}, {:";", 2},
              {:id, 3, 'bar'}, {:"(", 3}, {:id, 3, 'a'}, {:",", 3},
                {:id, 3, 'b'}, {:")", 3}, {:";", 3},
              {:"}", 4}
            ], 4}
  end

  test "expressions_test" do
    code =
      'Contract test {
         a = b + (c + d);
       }'

    assert :aernold_lexer.string(code) ==
      {:ok, [
              {:contract, 1}, {:id, 1, 'test'}, {:"{", 1},
              {:id, 2, 'a'}, {:=, 2}, {:id, 2, 'b'}, {:+, 2}, {:"(", 2},
                {:id, 2, 'c'}, {:+, 2}, {:id, 2, 'd'},
                {:")", 2}, {:";", 2},
              {:"}", 3}
            ], 3}
  end

end
