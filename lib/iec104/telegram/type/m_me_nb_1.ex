defmodule IEC104.Telegram.Type.M_ME_NB_1 do
  alias IEC104.InformationElement.{QDS, SVA}

  use IEC104.Telegram.Type,
    element_types: [
      SVA,
      QDS
    ]

  @type t :: {SVA.t(), QDS.t()}
end
