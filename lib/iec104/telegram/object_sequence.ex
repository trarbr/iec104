defmodule IEC104.Telegram.ObjectSequence do
  def length(type, number_of_elements) do
    # TODO: The number 3 here depends on the configured address length (could be 2)
    3 + type.length() * number_of_elements
  end

  def number_of_items([{_address, elements}] = _information_objects) do
    length(elements)
  end

  def decode(type, information_objects) do
    decode(type, information_objects, nil)
  end

  defp decode(_type, <<>>, {address, elements}) do
    [{address, Enum.reverse(elements)}]
  end

  defp decode(type, data, nil) do
    <<address::24-little, rest::bitstring>> = data
    decode(type, rest, {address, []})
  end

  defp decode(type, data, {address, elements_acc}) do
    length = type.length()
    <<elements::bytes-size(length), rest::bitstring>> = data
    elements = type.decode_elements(elements)
    object = {address, [elements | elements_acc]}
    decode(type, rest, object)
  end

  def encode(type, [{address, elements}]) do
    elements =
      Enum.map(elements, fn elements ->
        type.encode_elements(elements)
      end)

    [<<address::24-little>>, elements]
  end
end
