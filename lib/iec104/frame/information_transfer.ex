defmodule IEC104.Frame.InformationTransfer do
  alias IEC104.Frame.SequenceNumber
  alias IEC104.Telegram

  @type t() :: %__MODULE__{
          sent_sequence_number: integer(),
          received_sequence_number: integer(),
          telegram: Telegram.t()
        }
  defstruct [:sent_sequence_number, :received_sequence_number, :telegram]

  def encode(%__MODULE__{} = frame) do
    telegram =
      frame.telegram
      |> Telegram.encode()
      |> IO.iodata_to_binary()

    <<SequenceNumber.encode(frame.sent_sequence_number)::bytes-size(2),
      SequenceNumber.encode(frame.received_sequence_number)::bytes-size(2), telegram::bytes>>
  end

  def decode(<<_::7, 0::1, _rest::bitstring>> = control_flags, telegram) do
    <<sent::bytes-size(2), received::bytes-size(2)>> = control_flags
    {:ok, telegram} = Telegram.decode(telegram)

    {:ok,
     %__MODULE__{
       sent_sequence_number: SequenceNumber.decode(sent),
       received_sequence_number: SequenceNumber.decode(received),
       telegram: telegram
     }}
  end
end
