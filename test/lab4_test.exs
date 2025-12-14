defmodule Lab4Test do
  use ExUnit.Case
  doctest Lab4

  test "greets the world" do
    assert Lab4.hello() == :world
  end
end
