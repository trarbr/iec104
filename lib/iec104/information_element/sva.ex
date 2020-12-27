defmodule IEC104.InformationElement.SVA do
  @moduledoc """
  Scaled value. 16 bit signed integer, in the range of -32_768 to 32_767.
  """

  @type t() :: integer()

  @max 32_767
  @min -32_768

  @spec new(integer()) :: t()
  def new(number) when is_integer(number) and number >= @min and number <= @max do
    number
  end

  def decode(<<number::16-little>>) do
    number
  end

  def encode(number) do
    <<number::16-little>>
  end

  def length() do
    2
  end
end
