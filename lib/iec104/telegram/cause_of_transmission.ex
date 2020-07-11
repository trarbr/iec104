defmodule IEC104.Telegram.CauseOfTransmission do
  @type t() :: atom()

  @spec by_name(t()) :: integer()
  def by_name(name)

  @spec by_id(integer()) :: t()
  def by_id(id)

  %{
    periodic: 1,
    background_scan: 2,
    spontaneous: 3,
    initialized: 4,
    request: 5,
    activation: 6,
    activation_con: 7,
    deactivation: 8,
    deactivation_con: 9,
    activation_termination: 10,
    return_info_remote: 11,
    return_info_local: 12,
    file_transfer: 13,
    interrogated_by_station: 20,
    interrogated_by_group_1: 21,
    interrogated_by_group_2: 22,
    interrogated_by_group_3: 23,
    interrogated_by_group_4: 24,
    interrogated_by_group_5: 25,
    interrogated_by_group_6: 26,
    interrogated_by_group_7: 27,
    interrogated_by_group_8: 28,
    interrogated_by_group_9: 29,
    interrogated_by_group_10: 30,
    interrogated_by_group_11: 31,
    interrogated_by_group_12: 32,
    interrogated_by_group_13: 33,
    interrogated_by_group_14: 34,
    interrogated_by_group_15: 35,
    interrogated_by_group_16: 36,
    requested_by_general_counter: 37,
    requested_by_group_1_counter: 38,
    requested_by_group_2_counter: 39,
    requested_by_group_3_counter: 40,
    requested_by_group_4_counter: 41,
    unknown_type_id: 44,
    unknown_cause_of_transmission: 45,
    unknown_common_address_of_asdu: 46,
    unknown_information_object_address: 47
  }
  |> Enum.each(fn {name, id} ->
    def by_name(unquote(name)), do: unquote(id)
    def by_id(unquote(id)), do: unquote(name)
  end)
end
