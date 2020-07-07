defmodule IEC104.Telegram.ObjectMap do
  def length(type, number_of_objects) do
    # TODO: The number 3 here depends on the configured address length (could be 2)
    (3 + type.length()) * number_of_objects
  end

  def number_of_items(information_objects) do
    length(information_objects)
  end

  def decode(type, information_objects) do
    decode(type, information_objects, [])
  end

  defp decode(_type, <<>>, acc) do
    Enum.reverse(acc)
  end

  defp decode(type, information_objects, acc) do
    length = type.length()
    <<address::24-little, elements::bytes-size(length), rest::bitstring>> = information_objects
    elements = type.decode_elements(elements)
    object = {address, [elements]}
    decode(type, rest, [object | acc])
  end

  def encode(type, information_objects) do
    Enum.map(information_objects, fn {address, [elements]} ->
      elements = type.encode_elements(elements)
      [<<address::24-little>>, elements]
    end)
  end
end
