defmodule OmaTest do
  use ExUnit.Case
  doctest Oma

  test "greets the world" do
    assert Oma.hello() == :world
  end
end
