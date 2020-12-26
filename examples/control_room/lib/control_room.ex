defmodule ControlRoom do
  @moduledoc """
  The handler process for the ControllingConnection.
  """

  use GenServer

  require Logger

  alias IEC104.{ControllingConnection, Telegram}
  alias IEC104.InformationObject.M_ME_TF_1
  alias IEC104.InformationElement.{CP56Time2a, R32, QDS}

  defstruct conn: nil

  def start_link(args, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  def send_telegram_sync(server \\ __MODULE__) do
    telegram =
      M_ME_TF_1.new_telegram(101, :spontaneous, %{
        1 => {R32.new(1.0), QDS.new(), CP56Time2a.new(DateTime.utc_now())}
      })

    GenServer.call(server, {:send_telegram_sync, telegram})
  end

  @impl GenServer
  def init(args) do
    {:ok, conn} = ControllingConnection.start_link(args)
    {:ok, %__MODULE__{conn: conn}}
  end

  @impl GenServer
  def handle_call({:send_telegram_sync, telegram}, _from, state) do
    {:ok, sequence_number} = ControllingConnection.send_telegram(state.conn, telegram)

    # Note that this check can be overly naive in some situations, as you are
    # not always guaranteed to receive a receipt for every message. If the
    # receiver does not immediately acknowledge the telegram, several telegrams
    # may be sent before the reciver sends an acknowledgement, and you will
    # only receive an :telegram_receipt message for the last telegram to be
    # acknowledged.
    receive do
      {ControllingConnection, :telegram_receipt, ^sequence_number} ->
        {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_info({ControllingConnection, :state, :connected}, state) do
    :ok = ControllingConnection.start_data_transfer(state.conn)
    Logger.info("state=connected")
    {:noreply, state}
  end

  def handle_info({ControllingConnection, :state, :data_transfer}, state) do
    Logger.info("state=data_transfer")
    {:noreply, state}
  end

  def handle_info({ControllingConnection, :state, :disconnected}, state) do
    Logger.info("state=disconnected")
    {:noreply, state}
  end

  def handle_info({ControllingConnection, :telegram, telegram}, state) do
    telegram
    |> format_telegram()
    |> Logger.info()

    {:noreply, state}
  end

  defp format_telegram(telegram) do
    objects =
      Telegram.information_objects(telegram)
      |> Enum.map(&format_object/1)
      |> Enum.join("\n")

    """
    ========================
    Common address: #{telegram.common_address}
    Originator address: #{telegram.originator_address}
    Cause of transmission: #{telegram.cause_of_transmission}
    Information object type: #{telegram.type}
    """ <> objects <> "\n========================"
  end

  defp format_object({address, values}) do
    values =
      values
      |> Tuple.to_list()
      |> Enum.map(&format_value/1)
      |> Enum.join("\n")

    "Information object address: #{address}\n" <> values
  end

  defp format_value(value) do
    case value do
      %QDS{} = qds ->
        "Quality descriptor: blocked? #{qds.blocked?}, invalid?: #{qds.invalid?}, overflow?: #{
          qds.overflow?
        }, substituted?: #{qds.substituted?}, topical?: #{qds.topical?}"

      %CP56Time2a{} = cp56_time2a ->
        case CP56Time2a.to_datetime(cp56_time2a) do
          {:ok, ts} -> "CP56Time2a: #{ts}"
          _error -> "invalid datetime"
        end

      _ ->
        "Value: #{inspect(value)}"
    end
  end
end
