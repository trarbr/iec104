defmodule IEC104.InformationElement.CP56Time2a do
  @moduledoc """
  Seven octet binary time.
  """

  alias IEC104.Helpers

  @typedoc """
  TODO: Explanation of all the different fields, how year is encoded in just 7 bits etc
  """
  @type t() :: %__MODULE__{
          year: integer(),
          month: integer(),
          day_of_month: integer(),
          hour: integer(),
          minute: integer(),
          millisecond: integer(),
          day_of_week: integer(),
          daylight_savings_time?: boolean(),
          invalid?: boolean()
        }

  defstruct [
    :year,
    :month,
    :day_of_month,
    :hour,
    :minute,
    :millisecond,
    :day_of_week,
    :daylight_savings_time?,
    :invalid?
  ]

  def new(datetime, invalid? \\ false) do
    %__MODULE__{
      year: last_two_digits_of_year(datetime),
      month: datetime.month,
      day_of_month: datetime.day,
      hour: datetime.hour,
      minute: datetime.minute,
      millisecond: millisecond(datetime),
      day_of_week: day_of_week(datetime),
      daylight_savings_time?: daylight_savings_time?(datetime),
      invalid?: invalid?
    }
  end

  defp last_two_digits_of_year(%DateTime{} = datetime) do
    last_two_digits_of_year(datetime.year)
  end

  defp last_two_digits_of_year(year) when is_integer(year) do
    rem(year, 100)
  end

  defp millisecond(%{second: second, microsecond: {microseconds, _precision}} = _datetime) do
    milliseconds =
      (microseconds / 1000)
      |> Float.round()
      |> trunc()

    second * 1000 + milliseconds
  end

  defp day_of_week(datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.day_of_week()
  end

  defp daylight_savings_time?(datetime) do
    datetime.std_offset != 0
  end

  # Note that CP56Time2a does not store the century of the date. Therefore you have to pass the earliest possible year of
  # the CP56Time2a instance. Say the year stored by CP56Time2a is 10. From this information alone it is not possible to tell
  # whether the real year is 1910 or 2010 or 2110. If you pass 1970 as the start of century, then this function will
  # know that the year of the given date lies between 1970 and 2069 and can therefore calculate that the correct date
  # is 2010.
  def to_datetime(cp56_time2a, starting_year \\ 1970, timezone \\ "Etc/UTC") do
    NaiveDateTime.new(
      year(cp56_time2a, starting_year),
      cp56_time2a.month,
      cp56_time2a.day_of_month,
      cp56_time2a.hour,
      cp56_time2a.minute,
      second(cp56_time2a),
      microsecond(cp56_time2a)
    )
    |> case do
      {:ok, naive_datetime} -> DateTime.from_naive(naive_datetime, timezone)
      error -> error
    end
  end

  defp year(cp56_time2a, starting_year) do
    century(cp56_time2a, starting_year) * 100 + cp56_time2a.year
  end

  defp century(cp56_time2a, starting_year) do
    if cp56_time2a.year <= last_two_digits_of_year(starting_year) do
      div(starting_year + 100, 100)
    else
      div(starting_year, 100)
    end
  end

  defp second(cp56_time2a) do
    div(cp56_time2a.millisecond, 1000)
  end

  defp microsecond(cp56_time2a) do
    {rem(cp56_time2a.millisecond, 1000), 3}
  end

  def decode(
        <<millisecond::16-little, invalid?::1, _reserved1::1, minute::6, daylight_savings_time::1,
          _reserved2::2, hour::5, day_of_week::3, day_of_month::5, _reserved3::4, month::4,
          _reserved4::1, year::7>>
      ) do
    %__MODULE__{
      invalid?: Helpers.boolean(invalid?),
      millisecond: millisecond,
      minute: minute,
      daylight_savings_time?: Helpers.boolean(daylight_savings_time),
      hour: hour,
      day_of_week: day_of_week,
      day_of_month: day_of_month,
      month: month,
      year: year
    }
  end

  def encode(cp56_time2a) do
    <<cp56_time2a.millisecond::16-little, Helpers.boolean(cp56_time2a.invalid?)::1, 0::1,
      cp56_time2a.minute::6, Helpers.boolean(cp56_time2a.daylight_savings_time?)::1, 0::2,
      cp56_time2a.hour::5, cp56_time2a.day_of_week::3, cp56_time2a.day_of_month::5, 0::4,
      cp56_time2a.month::4, 0::1, cp56_time2a.year::7>>
  end

  def length() do
    7
  end
end
