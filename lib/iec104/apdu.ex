defmodule IEC104.APDU do
  alias IEC104.APDU.ControlFunction

  defstruct [:apci]

  @start_byte 0x68

  def encode(%{apci: %ControlFunction{} = apci}) do
    apci = ControlFunction.encode(apci)
    {:ok, <<@start_byte, byte_size(apci)>> <> apci}
  end

  def decode(<<@start_byte, _length, control_flags::bytes-size(4), rest::bitstring>>) do
    apci = decode_apci(control_flags)

    {:ok, %__MODULE__{apci: apci}, rest}
  end

  defp decode_apci(<<_::6, 1::1, 1::1, _rest::binary>> = control_flags) do
    ControlFunction.decode(control_flags)
  end
end
