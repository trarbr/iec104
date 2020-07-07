defmodule IEC104.Telegram.Type.M_ME_TF_1 do
  alias IEC104.InformationElement.{CP56Time2a, QDS, R32}

  use IEC104.Telegram.Type,
    element_types: [
      R32,
      QDS,
      CP56Time2a
    ]

  @type t :: {R32.t(), QDS.t(), CP56Time2a.t()}
end
