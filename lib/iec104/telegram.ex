defmodule IEC104.Telegram do
  @moduledoc """
  Telegrams are used for transporting information between controlling and
  controlled stations.
  """

  alias IEC104.Telegram.{ObjectMap, ObjectSequence, Type}
  alias IEC104.Helpers

  defstruct [
    :type,
    :sequence?,
    :test?,
    :negative_confirmation?,
    :cause_of_transmission,
    :originator_address,
    :common_address,
    :information_objects
  ]

  def new(type, cause_of_transmission, common_address, information_objects, opts) do
    %__MODULE__{
      type: type,
      sequence?: Keyword.get(opts, :sequence?, false),
      test?: Keyword.get(opts, :test?, false),
      negative_confirmation?: Keyword.get(opts, :negative_confirmation?, false),
      cause_of_transmission: cause_of_transmission,
      originator_address: Keyword.get(opts, :originator_address, 0),
      common_address: common_address,
      information_objects: information_objects
    }
  end

  def decode(
        <<type, structure_qualifier::1, number_of_items::7, test?::1, negative_confirmation?::1,
          cause_of_transmission::6, originator_address::8, common_address::16-little,
          rest::bitstring>>
      ) do
    type = Type.lookup(type)
    object_container = if structure_qualifier == 0, do: ObjectMap, else: ObjectSequence
    information_objects_length = object_container.length(type, number_of_items)

    # I already check this length in Frame.ex, since that has the length of the telegram in bytes
    # Of course, this is a semantic length check - does the data type length actually match that of the frame?
    if information_objects_length >= byte_size(rest) do
      <<information_objects::bytes-size(information_objects_length), rest::bitstring>> = rest
      information_objects = object_container.decode(type, information_objects)

      {:ok,
       %__MODULE__{
         type: type,
         sequence?: structure_qualifier == 1,
         test?: Helpers.boolean(test?),
         negative_confirmation?: Helpers.boolean(negative_confirmation?),
         cause_of_transmission: cause_of_transmission,
         originator_address: originator_address,
         common_address: common_address,
         information_objects: information_objects
       }, rest}
    end
  end

  def encode(telegram) do
    structure_qualifier = if telegram.sequence?, do: 1, else: 0
    object_container = if telegram.sequence?, do: ObjectSequence, else: ObjectMap
    number_of_items = object_container.number_of_items(telegram.information_objects)
    information_objects = object_container.encode(telegram.type, telegram.information_objects)

    [
      <<Type.lookup(telegram.type), structure_qualifier::1, number_of_items::7,
        Helpers.boolean(telegram.test?)::1, Helpers.boolean(telegram.negative_confirmation?)::1,
        telegram.cause_of_transmission::6, telegram.originator_address::8,
        telegram.common_address::16-little>>,
      information_objects
    ]
  end
end
