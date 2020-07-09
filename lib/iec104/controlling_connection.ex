defmodule IEC104.ControllingConnection do
  require Logger

  alias IEC104.Frame
  alias IEC104.Frame.ControlFunction

  @behaviour :gen_statem

  defstruct [:host, :port, :handler, :connect_timeout, :connect_backoff, :socket]

  @options_schema [
    host: [
      type: :any,
      doc: "inet:socket_address() | inet:hostname()",
      default: 'localhost'
    ],
    port: [
      type: :pos_integer,
      doc: "a port number",
      default: 2404
    ],
    handler: [
      type: :pid,
      doc: "default: self()"
    ],
    connect_timeout: [
      type: :pos_integer,
      doc: "How long to wait before timing out a connection attempt",
      default: 5000
    ],
    connect_backoff: [
      type: :pos_integer,
      doc: "How long to wait before retrying connect",
      default: 5000
    ]
  ]

  def start_link(args, opts \\ []) do
    args
    |> Keyword.put_new(:handler, self())
    |> NimbleOptions.validate(@options_schema)
    |> case do
      {:ok, args} -> :gen_statem.start_link(__MODULE__, args, opts)
      error -> error
    end
  end

  def start_data_transfer(conn) do
    :gen_statem.call(conn, :start_data_transfer)
  end

  @impl :gen_statem
  def callback_mode(), do: :state_functions

  @impl :gen_statem
  def init(args) do
    data = %__MODULE__{
      host: Keyword.fetch!(args, :host),
      port: Keyword.fetch!(args, :port),
      handler: Keyword.fetch!(args, :handler),
      connect_timeout: Keyword.fetch!(args, :connect_timeout),
      connect_backoff: Keyword.fetch!(args, :connect_backoff)
    }

    actions = [{:next_event, :internal, :connect}]

    {:ok, :disconnected, data, actions}
  end

  @doc false
  def disconnected(event_type, :connect, %__MODULE__{socket: nil} = data)
      when event_type in [:internal, :state_timeout] do
    case :gen_tcp.connect(data.host, data.port, [:binary], data.connect_timeout) do
      {:ok, socket} ->
        _ = notify_handler(data, :connected)
        {:next_state, :connected, %{data | socket: socket}}

      error ->
        Logger.info("could not connect: #{inspect(error)}")

        {:keep_state_and_data, [{:state_timeout, data.connect_backoff, :connect}]}
    end
  end

  @doc false
  def connected(:info, {:tcp_closed, _port}, data) do
    {:next_state, :disconnected, %{data | socket: nil}}
  end

  def connected(:info, {:tcp, _port, frame}, data) do
    case Frame.decode(frame) do
      {:ok, %Frame{apci: %ControlFunction{function: :start_data_transfer_confirmation}}, _rest} ->
        # TODO: Transfer to new state?
        :keep_state_and_data

      {:ok, %Frame{apci: %ControlFunction{function: :test_frame_activation}}, _rest} ->
        %Frame{apci: %ControlFunction{function: :test_frame_confirmation}}
        |> send_frame(data)

        :keep_state_and_data
    end
  end

  def connected({:call, from}, :start_data_transfer, data) do
    %Frame{apci: %ControlFunction{function: :start_data_transfer_activation}}
    |> send_frame(data)

    {:keep_state_and_data, [{:reply, from, :ok}]}
  end

  defp send_frame(frame, data) do
    {:ok, frame} = Frame.encode(frame)

    :ok = :gen_tcp.send(data.socket, frame)
  end

  defp notify_handler(data, state) do
    send(data.handler, {__MODULE__, state})
  end
end
