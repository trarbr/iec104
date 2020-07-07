defmodule IEC104.Helpers do
  @moduledoc false

  def boolean(value) do
    case value do
      0 -> false
      1 -> true
      false -> 0
      true -> 1
    end
  end
end
