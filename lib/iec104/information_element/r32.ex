defmodule IEC104.InformationElement.R32 do
  @moduledoc """
  Short floating point number (IEEE STD 754).
  """

  @type t() :: float()

  @max (2 - :math.pow(2, -23)) * :math.pow(2, 127)
  @min -@max

  @spec new(float()) :: t()
  def new(number) when number >= @min and number <= @max do
    number
  end

  def decode(<<number::32-float-little>>) do
    number
  end

  def encode(number) do
    <<number::32-float-little>>
  end

  def length() do
    4
  end
end
