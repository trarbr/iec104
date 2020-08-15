defmodule IEC104.ControllingConnection do
  require Logger

  alias IEC104.Frame
  alias IEC104.Frame.{ControlFunction, InformationTransfer, SupervisoryFunction}

  @behaviour :gen_statem

  defstruct [
    :host,
    :port,
    :handler,
    :connect_timeout,
    :connect_backoff,
    :response_timeout,
    :sequence_synchronization_timeout,
    :sequence_synchronization_threshold,
    :data_transfer_idle_timeout,
    :buffer,
    :socket,
    :received_sequence_number,
    :acknowledged_received_sequence_number,
    :sequence_synchronization_timer_running?
  ]

  @options_schema [
    host: [
      type: :any,
      doc: "The IP address or hostname to connect to.",
      default: 'localhost'
    ],
    port: [
      type: :pos_integer,
      doc: "The port number to connect to.",
      default: 2404
    ],
    handler: [
      type: :pid,
      doc: """
      The PID of the handler process for the connection. The connection
      process will notify the handler process on connection events, such as
      disconnects. Default: self().
      """
    ],
    connect_timeout: [
      type: :pos_integer,
      doc: "How long to wait before timing out a connection attempt.",
      default: 5000
    ],
    connect_backoff: [
      type: :pos_integer,
      doc: "How long to wait before attempting to re-establish a connection.",
      default: 5000
    ],
    response_timeout: [
      type: :pos_integer,
      doc: """
      The maximum time to wait (in milliseconds) for a response from the
      controlled station before actively closing the connection. This timeout
      is called `t1` by the standard. Minimum is 1000 ms, maximum is 255_000
      ms.
      """,
      default: 15_000
    ],
    sequence_synchronization_timeout: [
      type: :pos_integer,
      doc: """
      The maximum time to wait (in milliseconds) before sending a receipt for
      received telegrams. This timeout is called t2 by the standard. Minimum
      is 1000 ms, maximum is 255_000 ms.
      """,
      default: 10_000
    ],
    sequence_synchronization_threshold: [
      type: :pos_integer,
      doc: """
      The maximum number of telegrams that can be received before sending a
      receipt.
      """,
      default: 8
    ],
    data_transfer_idle_timeout: [
      type: :pos_integer,
      doc: """
      The maximum time (in milliseconds) that the connection may be idle
      before sending a test frame. This timeout is called t3 by the standard.
      Minimum is 1000 ms, maximum is 172_800_000 ms (48h).
      """,
      default: 20_000
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
      connect_backoff: Keyword.fetch!(args, :connect_backoff),
      response_timeout: Keyword.fetch!(args, :response_timeout),
      sequence_synchronization_timeout: Keyword.fetch!(args, :sequence_synchronization_timeout),
      sequence_synchronization_threshold:
        Keyword.fetch!(args, :sequence_synchronization_threshold),
      data_transfer_idle_timeout: Keyword.fetch!(args, :data_transfer_idle_timeout),
      buffer: <<>>,
      received_sequence_number: 0,
      acknowledged_received_sequence_number: 0,
      sequence_synchronization_timer_running?: false
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
        {:keep_state_and_data, [{:next_event, :internal, :connect}]}
    end
  end

  @doc false
  def connected(:info, {:tcp_closed, _port}, data) do
    {:next_state, :disconnected, %{data | socket: nil},
     [{:state_timeout, data.connect_backoff, :connect}]}
  end

  def connected(:info, {:tcp, _port, frame}, data) do
    {:keep_state, %{data | buffer: data.buffer <> frame},
     [{:next_event, :internal, :handle_frame}]}
  end

  def connected(:internal, :handle_frame, data) do
    data.buffer
    |> Frame.decode()
    |> case do
      {:ok, %ControlFunction{function: :start_data_transfer_confirmation}, rest} ->
        _ = notify_handler(data, :data_transfer)

        {data, actions} =
          {%{data | buffer: rest}, []}
          |> data_transfer_idle_timeout()
          |> handle_frame()

        {:next_state, :data_transfer, data, actions}

      {:error, :in_frame} ->
        :keep_state_and_data
    end
  end

  def connected({:call, from}, :start_data_transfer, data) do
    %ControlFunction{function: :start_data_transfer_activation}
    |> send_frame(data)

    {:keep_state_and_data,
     [{:reply, from, :ok}, {:state_timeout, data.response_timeout, :response}]}
  end

  def connected(:state_timeout, :response, data) do
    :ok = :gen_tcp.close(data.socket)

    {:next_state, :disconnected, %{data | socket: nil},
     [{:state_timeout, data.connect_backoff, :connect}]}
  end

  def data_transfer(:info, {:tcp_closed, _port}, data) do
    {:next_state, :disconnected, %{data | socket: nil},
     [{:state_timeout, data.connect_backoff, :connect}]}
  end

  def data_transfer(:info, {:tcp, _port, frame}, data) do
    {:keep_state, %{data | buffer: data.buffer <> frame},
     [{:next_event, :internal, :handle_frame}]}
  end

  def data_transfer(:internal, :handle_frame, data) do
    data.buffer
    |> Frame.decode()
    |> case do
      {:ok, %ControlFunction{function: :test_frame_activation}, rest} ->
        %ControlFunction{function: :test_frame_confirmation}
        |> send_frame(data)

        {data, actions} =
          {%{data | buffer: rest}, []}
          |> data_transfer_idle_timeout()
          |> handle_frame()

        {:keep_state, data, actions}

      {:ok, %ControlFunction{function: :test_frame_confirmation}, rest} ->
        {data, actions} =
          {%{data | buffer: rest}, [{:state_timeout, :cancel}]}
          |> data_transfer_idle_timeout()
          |> handle_frame()

        {:keep_state, data, actions}

      {:ok, %InformationTransfer{} = frame, rest} ->
        _ = notify_handler(data, frame.telegram)

        # TODO: Might have to cancel the state_timeout here, if the sequence counter matches expected
        {data, actions} =
          {%{data | buffer: rest, received_sequence_number: frame.sent_sequence_number}, []}
          |> data_transfer_idle_timeout()
          |> sequence_synchronization()
          |> handle_frame()

        {:keep_state, data, actions}

      {:error, :in_frame} ->
        :keep_state_and_data
    end
  end

  def data_transfer(:internal, :sequence_synchronization, data) do
    send_supervisory_function(data)
  end

  def data_transfer({:timeout, :sequence_synchronization}, :data_transfer, data) do
    send_supervisory_function(data)
  end

  def data_transfer({:timeout, :idle}, :data_transfer, data) do
    %ControlFunction{function: :test_frame_activation}
    |> send_frame(data)

    {:keep_state_and_data, [{:state_timeout, data.response_timeout, :response}]}
  end

  def data_transfer(:state_timeout, :response, data) do
    :ok = :gen_tcp.close(data.socket)

    {:next_state, :disconnected, %{data | socket: nil},
     [{:state_timeout, data.connect_backoff, :connect}]}
  end

  defp send_supervisory_function(data) do
    %SupervisoryFunction{
      received_sequence_number: data.received_sequence_number + 1
    }
    |> send_frame(data)

    {:keep_state,
     %{
       data
       | sequence_synchronization_timer_running?: false,
         acknowledged_received_sequence_number: data.received_sequence_number + 1
     }}
  end

  defp send_frame(frame, data) do
    {:ok, frame} = Frame.encode(frame)
    :ok = :gen_tcp.send(data.socket, frame)
  end

  defp notify_handler(data, state) do
    send(data.handler, {__MODULE__, state})
  end

  defp data_transfer_idle_timeout({data, actions}) do
    {data, actions ++ [{{:timeout, :idle}, data.data_transfer_idle_timeout, :data_transfer}]}
  end

  defp sequence_synchronization({data, actions}) do
    cond do
      sequence_synchronization_threshold_reached?(data) ->
        {data, actions ++ [{:next_event, :internal, :sequence_synchronization}]}

      not data.sequence_synchronization_timer_running? ->
        {%{data | sequence_synchronization_timer_running?: true},
         actions ++
           [
             {{:timeout, :sequence_synchronization}, data.sequence_synchronization_timeout,
              :data_transfer}
           ]}

      true ->
        {data, actions}
    end
  end

  defp sequence_synchronization_threshold_reached?(data) do
    abs(data.acknowledged_received_sequence_number - data.received_sequence_number) >=
      data.sequence_synchronization_threshold
  end

  defp handle_frame({data, actions}) do
    if data.buffer == <<>> do
      {data, actions}
    else
      {data, actions ++ [{:next_event, :internal, :handle_frame}]}
    end
  end
end
