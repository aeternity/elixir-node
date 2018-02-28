defmodule AernoldTest do
  use ExUnit.Case
  doctest Aernold

  test "simple recursion - nth fibonacci number" do
    code = "
      Contract test(n:Int) {

        func nth_fibonacci_number(n:Int) {
          if(n <= 1) {
           n;
          } else {
           nth_fibonacci_number(n - 1) + nth_fibonacci_number(n - 2);
          }
        }

        nth_fibonacci_number(n);

      }(10);
    "

    # 10th fibonacci number is 55
    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == 55
  end

  test "list declaration and definition" do
    code = "
      Contract test(){
        list:List<Int>;
        list = [1,2];
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == [1, 2]
  end

  test "list concat" do
    code = "
      Contract test(){
        list:List<Int>;
        list = [1, 2] ++ [3, 4];
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == [1, 2, 3, 4]
  end

  test "list remove first occurrence" do
    code = "
      Contract test(){
        list:List<Int>;
        list = [1, 2, 3, 4, 1, 2] -- [1, 2];
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == [3, 4, 1, 2]
  end

  test "list elem" do
    code = "
      Contract test(){
        list:List<Int> = [1,2];
        List.at(list, 0);
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == 1
  end

  test "list size" do
    code = "
      Contract test(){
        list:List<Int> = [1,2];
        List.size(list);
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == 2
  end

  test "insert_at list" do
    code = "
      Contract test(){
        list:List<Int> = [1, 2];
        list = List.insert_at(list, 2, 3);
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == [1, 2, 3]
  end

  test "reversе list" do
    code = "
      Contract test(){
        list:List<Int> = [1, 2, 3];
        list = List.reverse(list);
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == [3, 2, 1]
  end

  test "delete_at list" do
    code = "
      Contract test(){
        list:List<Int> = [1, 2, 3];
        list = List.delete_at(list, 0);
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == [2, 3]
  end

  test "sort list" do
    code = "
      Contract test(){
        list:List<Int> = [3, 2, 1];
        list = List.sort(list);
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == [1, 2, 3]
  end

  test "tuple declaration and definition" do
    code = "
      Contract test(){
        tuple:Tuple;
        tuple = {1, \"string\"};
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == {1, "string"}
  end

  test "tuple elem" do
    code = "
      Contract test(){
        tuple:Tuple = {1, \"string\", 3};
        Tuple.elem(tuple, 1);
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == "string"
  end

  test "tuple size" do
    code = "
      Contract test(){
        tuple:Tuple = {1, \"string\", 3};
        Tuple.size(tuple);
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == 3
  end

  test "insert_at tuple" do
    code = "
      Contract test(){
        c:Char = 'c';
        tuple:Tuple = {\"string\", [1, 2]};
        tuple = Tuple.insert_at(tuple, 2, c);
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == {"string", [1, 2], 'c'}
  end

  test "delete_at tuple" do
    code = "
      Contract test(){
        c:Char = 'c';
        tuple:Tuple = {\"string\", [1, 2], 'c'};
        tuple = Tuple.delete_at(tuple, 0);
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == {[1, 2], 'c'}
  end

  test "append tuple" do
    code = "
      Contract test(){
        c:Char = 'c';
        tuple:Tuple = {\"string\", [1, 2], 'c'};
        tuple = Tuple.append(tuple, 4);
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == {"string", [1, 2], 'c', 4}
  end

  test "map declaration and definition" do
    code = "
      Contract test(){
        map:Map<Int, String>;
        map = %{
          1 => \"one\",
          2 => \"two\"
        };
      }();
    "

    {returned_value, _scope} = Aernold.parse_string(code)

    assert returned_value == %{"1" => "one", "2" => "two"}
  end
end
