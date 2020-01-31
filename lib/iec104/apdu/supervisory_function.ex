defmodule IEC104.APDU.SupervisoryFunction do
  defstruct [:received_sequence_number]

  def encode(%{received_sequence_number: number}) do
    <<msb::8, lsb::7>> = <<number::15>>
    <<0::6, 0::1, 1::1, 0::8, lsb::7, 0::1, msb::8>>
  end

  def decode(<<_::7, 1::1, _::8, lsb::7, 0::1, msb::8>>) do
    <<number::15>> = <<msb::8, lsb::7>>

    %__MODULE__{
      received_sequence_number: number
    }
  end
end
