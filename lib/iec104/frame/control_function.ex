defmodule IEC104.Frame.ControlFunction do
  @type t() :: %__MODULE__{
          function:
            :start_data_transfer_activation
            | :start_data_transfer_confirmation
            | :test_frame_activation
            | :test_frame_confirmation
        }

  defstruct [:function]

  def encode(%__MODULE__{function: function}) do
    # TODO:
    # Test Frame Activation DONE
    # Test Frame Confirmation DONE
    # Stop Data Transfer Activation
    # Stop Data Transfer Confirmation
    # Start Data Transfer Activation DONE
    # Start Data Transfer Confirmation DONE
    control_flag_1 =
      case function do
        :start_data_transfer_activation -> <<0b00000111>>
        :start_data_transfer_confirmation -> <<0b00001011>>
        :test_frame_activation -> <<0b01000011>>
        :test_frame_confirmation -> <<0b10000011>>
      end

    control_flag_1 <> <<0, 0, 0>>
  end

  def decode(<<control_flag_1::bytes-size(1), _rest::bitstring>>) do
    function =
      case control_flag_1 do
        <<0b00000111>> -> %__MODULE__{function: :start_data_transfer_activation}
        <<0b00001011>> -> %__MODULE__{function: :start_data_transfer_confirmation}
        <<0b01000011>> -> %__MODULE__{function: :test_frame_activation}
        <<0b10000011>> -> %__MODULE__{function: :test_frame_confirmation}
      end

    {:ok, function}
  end
end
