defmodule IEC104.Frame.SupervisoryFunction do
  alias IEC104.Frame.SequenceNumber

  @type t() :: %__MODULE__{
          received_sequence_number: integer()
        }

  defstruct [:received_sequence_number]

  def encode(%{received_sequence_number: number}) do
    <<0::6, 0::1, 1::1, 0::8, SequenceNumber.encode(number)::bytes-size(2)>>
  end

  def decode(<<_::7, 1::1, _::8, number::bytes-size(2)>>) do
    {:ok,
     %__MODULE__{
       received_sequence_number: SequenceNumber.decode(number)
     }}
  end
end
