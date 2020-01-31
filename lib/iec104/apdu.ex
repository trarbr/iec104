defmodule IEC104.APDU do
  alias IEC104.APDU.{ControlFunction, InformationTransfer, SupervisoryFunction}

  defstruct [:apci]

  @start_byte 0x68

  def encode(%{apci: %ControlFunction{} = apci}) do
    apci = ControlFunction.encode(apci)
    {:ok, <<@start_byte, 4, apci::bytes>>}
  end

  def encode(%{apci: %SupervisoryFunction{} = apci}) do
    apci = SupervisoryFunction.encode(apci)
    {:ok, <<@start_byte, 4, apci::bytes>>}
  end

  def encode(%{apci: %InformationTransfer{} = apci}) do
    apci = InformationTransfer.encode(apci)
    {:ok, <<@start_byte, 4, apci::bytes>>}
  end

  def decode(<<@start_byte, _length, control_flags::bytes-size(4), rest::bitstring>>) do
    apci = decode_apci(control_flags)
    {:ok, %__MODULE__{apci: apci}, rest}
  end

  defp decode_apci(<<_::7, 0::1, _rest::bitstring>> = control_flags) do
    InformationTransfer.decode(control_flags)
  end

  defp decode_apci(<<_::6, 0::1, 1::1, _rest::bitstring>> = control_flags) do
    SupervisoryFunction.decode(control_flags)
  end

  defp decode_apci(<<_::6, 1::1, 1::1, _rest::bitstring>> = control_flags) do
    ControlFunction.decode(control_flags)
  end
end
