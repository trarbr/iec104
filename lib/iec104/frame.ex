defmodule IEC104.Frame do
  alias IEC104.Frame.{ControlFunction, InformationTransfer, SupervisoryFunction}

  @type t() :: ControlFunction.t() | InformationTransfer.t() | SupervisoryFunction.t()

  @start_byte 0x68

  def encode(%InformationTransfer{} = apdu) do
    frame = InformationTransfer.encode(apdu)
    {:ok, <<@start_byte, byte_size(frame), frame::bytes>>}
  end

  def encode(%SupervisoryFunction{} = apci) do
    apci = SupervisoryFunction.encode(apci)
    {:ok, <<@start_byte, 4, apci::bytes>>}
  end

  def encode(%ControlFunction{} = apci) do
    apci = ControlFunction.encode(apci)
    {:ok, <<@start_byte, 4, apci::bytes>>}
  end

  @spec decode(bitstring()) :: {:ok, IEC104.Frame.t(), bitstring} | {:error, :in_frame}
  def decode(<<@start_byte, length, control_flags::bytes-size(4), rest::bitstring>>)
      when byte_size(rest) >= length - 4 do
    case control_flags do
      <<_::7, 0::1, _rest::bitstring>> ->
        telegram_size = length - 4
        <<telegram::bytes-size(telegram_size), rest::bitstring>> = rest
        {:ok, frame} = InformationTransfer.decode(control_flags, telegram)
        {:ok, frame, rest}

      <<_::6, 0::1, 1::1, _rest::bitstring>> ->
        {:ok, frame} = SupervisoryFunction.decode(control_flags)
        {:ok, frame, rest}

      <<_::6, 1::1, 1::1, _rest::bitstring>> ->
        {:ok, frame} = ControlFunction.decode(control_flags)
        {:ok, frame, rest}
    end
  end

  def decode(_bytes) do
    {:error, :in_frame}
  end
end
