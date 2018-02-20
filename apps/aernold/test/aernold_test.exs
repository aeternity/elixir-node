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

end
