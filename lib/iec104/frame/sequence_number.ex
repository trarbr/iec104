defmodule IEC104.Frame.SequenceNumber do
  def encode(number) do
    <<msb::8, lsb::7>> = <<number::15>>
    <<lsb::7, 0::1, msb::8>>
  end

  def decode(<<lsb::7, 0::1, msb::8>>) do
    <<number::15>> = <<msb::8, lsb::7>>
    number
  end

  def increment(number) do
    case number do
      number when number == 32767 -> 0
      number -> number + 1
    end
  end

  def diff(small, large) do
    # If `small` is actually larger than `large`,
    # that is assumed to be because of overflow.
    # In this case we add 2^15 to the diff, to
    # ensure the diff is positive.
    case large - small do
      diff when diff >= 0 -> diff
      diff -> diff + 32768
    end
  end
end
