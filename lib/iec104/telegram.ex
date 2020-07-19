defmodule IEC104.Telegram do
  @moduledoc """
  Telegrams are used for transporting information between controlling and
  controlled stations.
  """

  alias IEC104.Telegram.{CauseOfTransmission, ObjectMap, ObjectSequence}
  alias IEC104.{InformationObject, Helpers}

  @type opts() :: [
          test?: boolean(),
          negative_confirmation?: boolean(),
          originator_address: integer()
        ]

  @type common_address() :: integer()
  @type originator_address() :: integer()

  @type information_object_map(element_set) :: %{InformationObject.address() => element_set}
  @type information_object_sequence(element_set) ::
          {InformationObject.address(), [element_set, ...]}
  @type information_object_container(element_set) ::
          information_object_map(element_set) | information_object_sequence(element_set)

  @type t() :: %__MODULE__{
          type: InformationObject.type(),
          test?: boolean(),
          negative_confirmation?: boolean(),
          cause_of_transmission: CauseOfTransmission.t(),
          originator_address: originator_address(),
          common_address: common_address(),
          information_objects: information_object_container(InformationObject.element_set())
        }

  defstruct [
    :type,
    :test?,
    :negative_confirmation?,
    :cause_of_transmission,
    :originator_address,
    :common_address,
    :information_objects
  ]

  @spec new(
          InformationObject.type(),
          CauseOfTransmission.t(),
          common_address(),
          information_object_container(InformationObject.element_set()),
          opts()
        ) :: t()
  def new(type, cause_of_transmission, common_address, information_objects, opts) do
    %__MODULE__{
      type: type,
      test?: Keyword.get(opts, :test?, false),
      negative_confirmation?: Keyword.get(opts, :negative_confirmation?, false),
      cause_of_transmission: cause_of_transmission,
      originator_address: Keyword.get(opts, :originator_address, 0),
      common_address: common_address,
      information_objects: information_objects
    }
  end

  @spec information_objects(t()) :: information_object_map(InformationObject.element_set())
  def information_objects(telegram) do
    case telegram.information_objects do
      %{} = information_objects ->
        information_objects

      {address, element_sets} ->
        element_sets
        |> Enum.with_index()
        |> Enum.map(fn {element_set, index} -> {address + index, element_set} end)
        |> Map.new()
    end
  end

  @spec sequence?(t()) :: boolean()
  def sequence?(%__MODULE__{} = telegram) do
    sequence?(telegram.information_objects)
  end

  # TODO: Not sure if this makes dialyzer unhappy
  def sequence?(information_objects) do
    case information_objects do
      %{} -> false
      {_address, _element_sets} -> true
    end
  end

  @doc false
  def decode(
        <<type, structure_qualifier::1, number_of_items::7, test?::1, negative_confirmation?::1,
          cause_of_transmission::6, originator_address::8, common_address::16-little,
          information_objects::bitstring>>
      ) do
    type = InformationObject.by_id(type)
    object_container = if structure_qualifier == 0, do: ObjectMap, else: ObjectSequence
    information_objects_length = object_container.length(type, number_of_items)

    # I already check this length in Frame.ex, since that has the length of the telegram in bytes
    # Of course, this is a semantic length check - does the data type length actually match that of the frame?
    if information_objects_length == byte_size(information_objects) do
      <<information_objects::bytes-size(information_objects_length)>> = information_objects
      information_objects = object_container.decode(type, information_objects)

      {:ok,
       %__MODULE__{
         type: type,
         test?: Helpers.boolean(test?),
         negative_confirmation?: Helpers.boolean(negative_confirmation?),
         cause_of_transmission: CauseOfTransmission.by_id(cause_of_transmission),
         originator_address: originator_address,
         common_address: common_address,
         information_objects: information_objects
       }}
    end
  end

  @doc false
  def encode(telegram) do
    sequence? = sequence?(telegram.information_objects)
    object_container = if sequence?, do: ObjectSequence, else: ObjectMap
    number_of_items = object_container.number_of_items(telegram.information_objects)
    information_objects = object_container.encode(telegram.type, telegram.information_objects)

    [
      <<InformationObject.by_name(telegram.type), Helpers.boolean(sequence?)::1,
        number_of_items::7, Helpers.boolean(telegram.test?)::1,
        Helpers.boolean(telegram.negative_confirmation?)::1,
        CauseOfTransmission.by_name(telegram.cause_of_transmission)::6,
        telegram.originator_address::8, telegram.common_address::16-little>>,
      information_objects
    ]
  end
end
