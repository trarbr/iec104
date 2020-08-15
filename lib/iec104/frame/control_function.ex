defmodule IEC104.Frame.ControlFunction do
  @type t() :: %__MODULE__{
          function:
            :start_data_transfer_activation
            | :start_data_transfer_confirmation
            | :stop_data_transfer_activation
            | :stop_data_transfer_confirmation
            | :test_frame_activation
            | :test_frame_confirmation
        }

  defstruct [:function]

  %{
    start_data_transfer_activation: <<0b00000111>>,
    start_data_transfer_confirmation: <<0b00001011>>,
    stop_data_transfer_activation: <<0b00010011>>,
    stop_data_transfer_confirmation: <<0b00100011>>,
    test_frame_activation: <<0b01000011>>,
    test_frame_confirmation: <<0b10000011>>
  }
  |> Enum.map(fn {function, control_flag_1} -> {function, <<control_flag_1::bytes, 0, 0, 0>>} end)
  |> Enum.each(fn {function, bytes} ->
    def encode(%__MODULE__{function: unquote(function)}), do: unquote(bytes)
    def decode(unquote(bytes)), do: %__MODULE__{function: unquote(function)}
  end)
end
