defmodule IEC104.Telegram.ObjectMap do
  @moduledoc false
  def length(type, number_of_objects) do
    # TODO: The number 3 here depends on the configured address length (could be 2)
    (3 + type.element_set_length()) * number_of_objects
  end

  def number_of_items(information_objects) do
    map_size(information_objects)
  end

  def decode(type, data) do
    decode(type, data, %{})
  end

  defp decode(_type, <<>>, information_objects) do
    information_objects
  end

  defp decode(type, data, information_objects) do
    length = type.element_set_length()
    <<address::24-little, element_set::bytes-size(length), rest::bitstring>> = data
    element_set = type.decode_element_set(element_set)
    information_objects = Map.put(information_objects, address, element_set)
    decode(type, rest, information_objects)
  end

  def encode(type, data) do
    Enum.map(data, fn {address, element_set} ->
      element_set = type.encode_element_set(element_set)
      [<<address::24-little>>, element_set]
    end)
  end
end
