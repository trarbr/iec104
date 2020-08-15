defmodule IEC104.FrameTest do
  use ExUnit.Case, async: true

  alias IEC104.Frame
  alias IEC104.Frame.{ControlFunction, InformationTransfer, SupervisoryFunction}
  alias IEC104.{InformationElement, InformationObject, Telegram}

  describe "incomplete frames" do
    test "returns an error if the frame is incomplete" do
      encoded = <<0x68, 0x04, 0x07, 0x00, 0x00>>

      assert {:error, :in_frame} == Frame.decode(encoded)
    end
  end

  describe "unnumbered control functions (U-format)" do
    test "startdt act" do
      encoded = <<0x68, 0x04, 0x07, 0x00, 0x00, 0x00>>

      decoded = %ControlFunction{function: :start_data_transfer_activation}

      assert {:ok, decoded, <<>>} == Frame.decode(encoded)
      assert {:ok, encoded} == Frame.encode(decoded)
    end

    test "startdt con" do
      encoded = <<0x68, 0x04, 0x0B, 0x00, 0x00, 0x00>>

      decoded = %ControlFunction{function: :start_data_transfer_confirmation}

      assert {:ok, decoded, <<>>} == Frame.decode(encoded)
      assert {:ok, encoded} == Frame.encode(decoded)
    end
  end

  describe "numbered supervisory functions (S-format)" do
    test "received sequence number" do
      encoded = <<0x68, 0x04, 0x01, 0x00, 0x14, 0x75>>

      decoded = %SupervisoryFunction{received_sequence_number: 14986}

      assert {:ok, decoded, <<>>} == Frame.decode(encoded)
      assert {:ok, encoded} == Frame.encode(decoded)
    end
  end

  describe "information transfer (I-format)" do
    test "telegram with one information object" do
      encoded =
        <<0x68, 0x19, 0xBE, 0x01, 0x00, 0x00, 0x24, 0x01, 0x03, 0x00, 0x91, 0x01, 0x04, 0x00,
          0x00, 0xBC, 0xF4, 0x47, 0x42, 0x00, 0x98, 0x3A, 0x2D, 0x8E, 0x42, 0x06, 0x14>>

      decoded = %InformationTransfer{
        sent_sequence_number: 223,
        received_sequence_number: 0,
        telegram: %Telegram{
          type: InformationObject.M_ME_TF_1,
          cause_of_transmission: :spontaneous,
          negative_confirmation?: false,
          test?: false,
          originator_address: 0,
          common_address: 401,
          information_objects: %{
            4 =>
              {49.98899841308594, qds(),
               %InformationElement.CP56Time2a{
                 millisecond: 15_000,
                 minute: 45,
                 invalid?: false,
                 hour: 14,
                 daylight_savings_time?: true,
                 day_of_month: 2,
                 day_of_week: 2,
                 month: 6,
                 year: 20
               }}
          }
        }
      }

      assert {:ok, decoded, <<>>} == Frame.decode(encoded)
      assert {:ok, encoded} == Frame.encode(decoded)
    end

    test "telegram with 7 information objects encoded as map" do
      encoded =
        <<0x68, 0x34, 0x5A, 0x14, 0x7C, 0x00, 0x0B, 0x07, 0x03, 0x00, 0x0C, 0x00, 0x0E, 0x30,
          0x00, 0x75, 0x00, 0x00, 0x0F, 0x30, 0x00, 0x0F, 0x0A, 0x00, 0x10, 0x30, 0x00, 0xBE,
          0x09, 0x00, 0x11, 0x30, 0x00, 0x90, 0x09, 0x00, 0x28, 0x30, 0x00, 0x25, 0x09, 0x00,
          0x29, 0x30, 0x00, 0x75, 0x00, 0x00, 0x2E, 0x30, 0x00, 0xAE, 0x05, 0x00>>

      decoded = %InformationTransfer{
        received_sequence_number: 62,
        sent_sequence_number: 2605,
        telegram: %Telegram{
          type: InformationObject.M_ME_NB_1,
          cause_of_transmission: :spontaneous,
          negative_confirmation?: false,
          test?: false,
          originator_address: 0,
          common_address: 12,
          information_objects: %{
            12304 => {2494, qds()},
            12305 => {2448, qds()},
            12302 => {117, qds()},
            12328 => {2341, qds()},
            12329 => {117, qds()},
            12303 => {2575, qds()},
            12334 => {1454, qds()}
          }
        }
      }

      assert {:ok, decoded, <<>>} == Frame.decode(encoded)
      assert {:ok, encoded} == Frame.encode(decoded)
    end

    test "telegram with 7 information objects encoded as sequence" do
      encoded =
        <<0x68, 0x22, 0x5A, 0x14, 0x7C, 0x00, 0x0B, 0x87, 0x03, 0x00, 0x0C, 0x00, 0x01, 0x00,
          0x00, 0xBE, 0x09, 0x00, 0x90, 0x09, 0x00, 0x75, 0x00, 0x00, 0x25, 0x09, 0x00, 0x75,
          0x00, 0x00, 0x0F, 0x0A, 0x00, 0xAE, 0x05, 0x00>>

      decoded = %InformationTransfer{
        received_sequence_number: 62,
        sent_sequence_number: 2605,
        telegram: %Telegram{
          type: InformationObject.M_ME_NB_1,
          cause_of_transmission: :spontaneous,
          negative_confirmation?: false,
          test?: false,
          originator_address: 0,
          common_address: 12,
          information_objects:
            {1,
             [
               {2494, qds()},
               {2448, qds()},
               {117, qds()},
               {2341, qds()},
               {117, qds()},
               {2575, qds()},
               {1454, qds()}
             ]}
        }
      }

      assert {:ok, decoded, <<>>} == Frame.decode(encoded)
      assert {:ok, encoded} == Frame.encode(decoded)
    end
  end

  defp qds() do
    %InformationElement.QDS{
      blocked?: false,
      invalid?: false,
      overflow?: false,
      substituted?: false,
      topical?: false
    }
  end
end
