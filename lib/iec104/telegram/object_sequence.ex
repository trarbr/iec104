defmodule IEC104.Telegram.ObjectSequence do
  @moduledoc false
  def length(type, number_of_element_sets) do
    # TODO: The number 3 here depends on the configured address length (could be 2)
    3 + type.element_set_length() * number_of_element_sets
  end

  def number_of_items({_address, element_sets} = _information_objects) do
    length(element_sets)
  end

  def decode(type, data) do
    decode(type, data, nil)
  end

  defp decode(_type, <<>>, {address, element_sets}) do
    {address, Enum.reverse(element_sets)}
  end

  defp decode(type, data, nil) do
    <<address::24-little, rest::bitstring>> = data
    decode(type, rest, {address, []})
  end

  defp decode(type, data, {address, element_sets}) do
    length = type.element_set_length()
    <<element_set::bytes-size(length), rest::bitstring>> = data
    element_set = type.decode_element_set(element_set)
    object = {address, [element_set | element_sets]}
    decode(type, rest, object)
  end

  def encode(type, {address, element_sets}) do
    element_sets =
      Enum.map(element_sets, fn element_set ->
        type.encode_element_set(element_set)
      end)

    [<<address::24-little>>, element_sets]
  end
end
