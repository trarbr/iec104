defmodule IEC104.InformationObject.M_ME_TF_1 do
  alias IEC104.InformationElement.{CP56Time2a, QDS, R32}
  alias IEC104.{InformationObject, Telegram}

  use InformationObject,
    element_types: [
      R32,
      QDS,
      CP56Time2a
    ]

  @valid_causes_of_transmission [
    :background_scan,
    :spontaneous,
    :request,
    :return_info_remote,
    :return_info_local,
    :interrogated_by_station,
    :interrogated_by_group_1,
    :interrogated_by_group_2,
    :interrogated_by_group_3,
    :interrogated_by_group_4,
    :interrogated_by_group_5,
    :interrogated_by_group_6,
    :interrogated_by_group_7,
    :interrogated_by_group_8,
    :interrogated_by_group_9,
    :interrogated_by_group_10,
    :interrogated_by_group_11,
    :interrogated_by_group_12,
    :interrogated_by_group_13,
    :interrogated_by_group_14,
    :interrogated_by_group_15,
    :interrogated_by_group_16
  ]

  @spec new_telegram(
          Telegram.common_address(),
          Telegram.cause_of_transmission(),
          Telegram.information_object_container({R32.t(), QDS.t(), CP56Time2a.t()}),
          Telegram.opts()
        ) ::
          Telegram.t()
  def new_telegram(common_address, cause_of_transmission, information_objects, opts \\ [])
      when cause_of_transmission in @valid_causes_of_transmission do
    Telegram.new(
      __MODULE__,
      cause_of_transmission,
      common_address,
      information_objects,
      opts
    )
  end
end
