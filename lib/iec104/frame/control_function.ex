defmodule IEC104.Frame.ControlFunction do
  defstruct [:function]

  def encode(%{function: function}) do
    # TODO:
    # Test Frame Activation
    # Test Frame Confirmation
    # Stop Data Transfer Activation
    # Stop Data Transfer Confirmation
    # Start Data Transfer Activation DONE
    # Start Data Transfer Confirmation DONE
    # Check if test frames are ever used?
    # 104apci.type == 3 and 104apci.utype == 0x11 in wireshark
    control_flag_1 =
      case function do
        :start_data_transfer_activation -> <<0b00000111>>
        :start_data_transfer_confirmation -> <<0b00001011>>
      end

    control_flag_1 <> <<0, 0, 0>>
  end

  def decode(<<control_flag_1::bytes-size(1), _rest::bitstring>>) do
    case control_flag_1 do
      <<0b00000111>> -> %__MODULE__{function: :start_data_transfer_activation}
      <<0b00001011>> -> %__MODULE__{function: :start_data_transfer_confirmation}
    end
  end
end
