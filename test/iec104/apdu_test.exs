defmodule IEC104.APDUTest do
  use ExUnit.Case

  alias IEC104.APDU
  alias IEC104.APDU.{ControlFunction, SupervisoryFunction}

  describe "unnumbered control functions (U-format)" do
    test "startdt act" do
      encoded = <<0x68, 0x04, 0x07, 0x00, 0x00, 0x00>>

      decoded = %APDU{
        apci: %ControlFunction{
          function: :start_data_transfer_activation
        }
      }

      assert {:ok, decoded, <<>>} == IEC104.APDU.decode(encoded)
      assert {:ok, encoded} == IEC104.APDU.encode(decoded)
    end

    test "startdt con" do
      encoded = <<0x68, 0x04, 0x0B, 0x00, 0x00, 0x00>>

      decoded = %APDU{
        apci: %ControlFunction{
          function: :start_data_transfer_confirmation
        }
      }

      assert {:ok, decoded, <<>>} == IEC104.APDU.decode(encoded)
      assert {:ok, encoded} == IEC104.APDU.encode(decoded)
    end
  end

  describe "numbered supervisory functions (S-format)" do
    test "received sequence number" do
      encoded = <<0x68, 0x04, 0x01, 0x00, 0x14, 0x75>>

      decoded = %APDU{
        apci: %SupervisoryFunction{
          received_sequence_number: 14986
        }
      }

      assert {:ok, decoded, <<>>} == IEC104.APDU.decode(encoded)
      assert {:ok, encoded} == IEC104.APDU.encode(decoded)
    end
  end
end
