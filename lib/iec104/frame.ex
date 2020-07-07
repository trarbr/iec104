defmodule IEC104.Frame do
  alias IEC104.Frame.{ControlFunction, InformationTransfer, SupervisoryFunction}
  alias IEC104.Telegram

  defstruct [:apci, :telegram]

  @start_byte 0x68

  def encode(%{apci: %ControlFunction{} = apci}) do
    apci = ControlFunction.encode(apci)
    {:ok, <<@start_byte, 4, apci::bytes>>}
  end

  def encode(%{apci: %SupervisoryFunction{} = apci}) do
    apci = SupervisoryFunction.encode(apci)
    {:ok, <<@start_byte, 4, apci::bytes>>}
  end

  def encode(%{apci: %InformationTransfer{} = apci} = frame) do
    apci = InformationTransfer.encode(apci)

    telegram =
      frame.telegram
      |> Telegram.encode()
      |> IO.iodata_to_binary()

    length = 4 + byte_size(telegram)
    {:ok, <<@start_byte, length, apci::bytes, telegram::bytes>>}
  end

  def decode(<<@start_byte, length, control_flags::bytes-size(4), rest::bitstring>>)
      when byte_size(rest) >= length - 4 do
    apci = decode_apci(control_flags)

    telegram_size = length - 4
    <<telegram::bytes-size(telegram_size), rest::bitstring>> = rest

    telegram =
      case apci do
        %InformationTransfer{} ->
          {:ok, telegram, _rest} = Telegram.decode(telegram)
          telegram

        _ ->
          nil
      end

    {:ok, %__MODULE__{apci: apci, telegram: telegram}, rest}
  end

  # TODO: handle decode when packet too small

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
