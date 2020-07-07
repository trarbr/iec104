defmodule IEC104.Telegram.Type do
  # TODO: consider if this should be a top-level module (like InformationElement)
  def lookup(type) do
    case type do
      11 -> __MODULE__.M_ME_NB_1
      __MODULE__.M_ME_NB_1 -> 11
      36 -> __MODULE__.M_ME_TF_1
      __MODULE__.M_ME_TF_1 -> 36
    end
  end

  @doc false
  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [element_types: Keyword.fetch!(opts, :element_types)] do
      @element_types element_types

      def decode_elements(elements) do
        IEC104.Telegram.Type.decode(elements, @element_types, [])
      end

      def encode_elements(elements) do
        IEC104.Telegram.Type.encode(Tuple.to_list(elements), @element_types, [])
      end

      def length() do
        IEC104.Telegram.Type.length(@element_types)
      end
    end
  end

  @doc false
  def decode(<<>>, [], acc) do
    acc
    |> Enum.reverse()
    |> List.to_tuple()
  end

  def decode(data, element_types, acc) do
    [element_type | element_types] = element_types
    element_size = element_type.length()
    <<element::bytes-size(element_size), rest::bitstring>> = data
    decoded_element = element_type.decode(element)
    decode(rest, element_types, [decoded_element | acc])
  end

  @doc false
  def encode([], [], acc) do
    Enum.reverse(acc)
  end

  def encode(elements, element_types, acc) do
    [element | elements] = elements
    [element_type | element_types] = element_types
    encoded_element = element_type.encode(element)
    encode(elements, element_types, [encoded_element | acc])
  end

  @doc false
  def length(element_types) do
    Enum.reduce(element_types, 0, fn et, acc -> acc + et.length() end)
  end
end
