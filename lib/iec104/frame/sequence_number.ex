defmodule IEC104.Frame.SequenceNumber do
  def encode(number) do
    <<msb::8, lsb::7>> = <<number::15>>
    <<lsb::7, 0::1, msb::8>>
  end

  def decode(<<lsb::7, 0::1, msb::8>>) do
    <<number::15>> = <<msb::8, lsb::7>>
    number
  end
end
