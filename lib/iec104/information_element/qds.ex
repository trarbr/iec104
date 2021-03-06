defmodule IEC104.InformationElement.QDS do
  @moduledoc """
  Quality descriptor.
  """

  alias IEC104.Helpers

  @type t() :: %__MODULE__{
          invalid?: boolean(),
          not_topical?: boolean(),
          substituted?: boolean(),
          blocked?: boolean(),
          overflow?: boolean()
        }

  defstruct [
    :invalid?,
    :not_topical?,
    :substituted?,
    :blocked?,
    :overflow?
  ]

  def new(opts \\ []) do
    %__MODULE__{
      invalid?: Keyword.get(opts, :invalid?, false),
      not_topical?: Keyword.get(opts, :not_topical?, false),
      substituted?: Keyword.get(opts, :substituted?, false),
      blocked?: Keyword.get(opts, :blocked?, false),
      overflow?: Keyword.get(opts, :overflow?, false)
    }
  end

  def decode(<<invalid?::1, topical?::1, substituted?::1, blocked?::1, _::3, overflow?::1>>) do
    %__MODULE__{
      invalid?: Helpers.boolean(invalid?),
      not_topical?: Helpers.boolean(topical?),
      substituted?: Helpers.boolean(substituted?),
      blocked?: Helpers.boolean(blocked?),
      overflow?: Helpers.boolean(overflow?)
    }
  end

  def encode(quality_descriptor) do
    <<Helpers.boolean(quality_descriptor.invalid?)::1,
      Helpers.boolean(quality_descriptor.not_topical?)::1,
      Helpers.boolean(quality_descriptor.substituted?)::1,
      Helpers.boolean(quality_descriptor.blocked?)::1, 0::3,
      Helpers.boolean(quality_descriptor.overflow?)::1>>
  end

  def length() do
    1
  end
end
