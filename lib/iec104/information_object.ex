defmodule IEC104.InformationObject do
  # This should be one of the InformationObject submodules, e.g. IEC104.InformationObject.M_ME_TF_1.t().
  # Could be compiled from the list of modules using InformationObject?
  @type type() :: module()

  # This should be either: nil, a module-atom or a tuple containing module-atoms.
  # Could be compiled from the list of modules using InformationObject?
  @type element_set() :: term()

  @type address() :: integer()

  @spec by_name(type()) :: integer()
  def by_name(name)
  @spec by_id(integer()) :: type()
  def by_id(id)

  %{
    __MODULE__.M_ME_NB_1 => 11,
    __MODULE__.M_ME_TF_1 => 36
  }
  |> Enum.each(fn {name, id} ->
    def by_name(unquote(name)), do: unquote(id)
    def by_id(unquote(id)), do: unquote(name)
  end)

  @doc false
  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [element_types: Keyword.fetch!(opts, :element_types)] do
      @element_types element_types

      @doc false
      def decode_element_set(element_set) do
        IEC104.InformationObject.decode(element_set, @element_types, [])
      end

      @doc false
      def encode_element_set(element_set) do
        # TODO: Handle cases where the element_set is not a tuple
        IEC104.InformationObject.encode(Tuple.to_list(element_set), @element_types, [])
      end

      @doc false
      def element_set_length() do
        IEC104.InformationObject.length(@element_types)
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
