defmodule IEC104.ControllingConnection do
  require Logger

  alias IEC104.Frame
  alias IEC104.Frame.{ControlFunction, InformationTransfer, SequenceNumber, SupervisoryFunction}

  @behaviour :gen_statem

  defstruct [
    :host,
    :port,
    :handler,
    :connect_timeout,
    :connect_backoff,
    :response_timeout,
    :send_telegram_receipt_timeout,
    :send_telegram_receipt_threshold,
    :data_transfer_idle_timeout,
    :buffer,
    :socket,
    :telegrams_received,
    :telegrams_receipted,
    :telegram_receipt_scheduled?,
    :telegrams_sent,
    :telegrams_delivered
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
    send_telegram_receipt_timeout: [
      type: :pos_integer,
      doc: """
      The maximum time to wait (in milliseconds) before sending an receipt for
      received telegrams. This timeout is called t2 by the standard. Minimum
      is 1000 ms, maximum is 255_000 ms.
      """,
      default: 10_000
    ],
    send_telegram_receipt_threshold: [
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

  def stop_data_transfer(conn) do
    :gen_statem.call(conn, :stop_data_transfer)
  end

  def send_telegram(conn, telegram) do
    :gen_statem.call(conn, {:send_telegram, telegram})
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
      send_telegram_receipt_timeout: Keyword.fetch!(args, :send_telegram_receipt_timeout),
      send_telegram_receipt_threshold: Keyword.fetch!(args, :send_telegram_receipt_threshold),
      data_transfer_idle_timeout: Keyword.fetch!(args, :data_transfer_idle_timeout),
      buffer: <<>>,
      telegrams_received: 0,
      telegrams_receipted: 0,
      telegram_receipt_scheduled?: false,
      telegrams_sent: 0,
      telegrams_delivered: 0
    }

    actions = [{:next_event, :internal, :connect}]

    {:ok, :disconnected, data, actions}
  end

  @doc false
  def disconnected(event_type, :connect, %__MODULE__{socket: nil} = data)
      when event_type in [:internal, :state_timeout] do
    case :gen_tcp.connect(data.host, data.port, [:binary], data.connect_timeout) do
      {:ok, socket} ->
        _ = notify_handler(data, :state, :connected)
        {:next_state, :connected, %{data | socket: socket}}

      {:error, :timeout} ->
        # If the connection attempt times out we attempt to reconnect immediately.
        Logger.info("could not connect: timeout")
        {:keep_state_and_data, [{:next_event, :internal, :connect}]}

      error ->
        Logger.info("could not connect: #{inspect(error)}")
        {:keep_state_and_data, [{:state_timeout, data.connect_backoff, :connect}]}
    end
  end

  @doc false
  def connected({:call, from}, :start_data_transfer, data) do
    %ControlFunction{function: :start_data_transfer_activation}
    |> send_frame(data)
    |> case do
      :ok ->
        {:keep_state_and_data,
         [{:reply, from, :ok}, {:state_timeout, data.response_timeout, :response}]}

      _error ->
        {data, actions} = disconnect({data, []})
        {:next_state, :disconnected, data, actions}
    end
  end

  def connected(:info, {:tcp_closed, socket}, data) when data.socket == socket do
    {data, actions} = disconnect({data, []})
    {:next_state, :disconnected, data, actions}
  end

  def connected(:info, {:tcp_closed, _socket}, _data) do
    :keep_state_and_data
  end

  def connected(:info, {:tcp, _socket, frame}, data) do
    {:keep_state, %{data | buffer: data.buffer <> frame},
     [{:next_event, :internal, :handle_frame}]}
  end

  def connected(:internal, :handle_frame, data) do
    data.buffer
    |> Frame.decode()
    |> case do
      {:ok, %ControlFunction{function: :start_data_transfer_confirmation}, rest} ->
        _ = notify_handler(data, :state, :data_transfer)

        {data, actions} =
          {%{data | buffer: rest}, []}
          |> data_transfer_idle_timeout()
          |> handle_next_frame()

        {:next_state, :data_transfer, data, actions}

      {:error, :in_frame} ->
        :keep_state_and_data
    end
  end

  def connected(:state_timeout, :response, data) do
    {data, actions} = disconnect({data, []})
    {:next_state, :disconnected, data, actions}
  end

  @doc false
  def data_transfer({:call, from}, {:send_telegram, telegram}, data) do
    %InformationTransfer{
      sent_sequence_number: data.telegrams_sent,
      received_sequence_number: data.telegrams_received,
      telegram: telegram
    }
    |> send_frame(data)
    |> case do
      :ok ->
        {:keep_state,
         %{
           data
           | telegrams_receipted: data.telegrams_received,
             telegram_receipt_scheduled?: false,
             telegrams_sent: SequenceNumber.increment(data.telegrams_sent)
         },
         [
           {:reply, from, {:ok, SequenceNumber.increment(data.telegrams_sent)}},
           {{:timeout, :send_telegram_receipt}, :cancel},
           {:state_timeout, data.response_timeout, :response}
         ]}

      _error ->
        {data, actions} = disconnect({data, []})
        {:next_state, :disconnected, data, actions}
    end
  end

  def data_transfer({:call, from}, :stop_data_transfer, data) do
    %ControlFunction{function: :stop_data_transfer_activation}
    |> send_frame(data)
    |> case do
      :ok ->
        {:keep_state_and_data,
         [{:reply, from, :ok}, {:state_timeout, data.response_timeout, :response}]}

      _error ->
        {data, actions} = disconnect({data, []})
        {:next_state, :disconnected, data, actions}
    end
  end

  def data_transfer(:info, {:tcp_closed, socket}, data) when data.socket == socket do
    {data, actions} =
      {data, []}
      |> reset_data_transfer()
      |> disconnect()

    {:next_state, :disconnected, data, actions}
  end

  def data_transfer(:info, {:tcp_closed, _socket}, _data) do
    :keep_state_and_data
  end

  def data_transfer(:info, {:tcp, _socket, frame}, data) do
    {:keep_state, %{data | buffer: data.buffer <> frame},
     [{:next_event, :internal, :handle_frame}]}
  end

  def data_transfer(:internal, :handle_frame, data) do
    data.buffer
    |> Frame.decode()
    |> case do
      {:ok, %InformationTransfer{} = frame, rest} ->
        if valid_received_sequence_number?(data, frame.received_sequence_number) and
             valid_sent_sequence_number?(data, frame.sent_sequence_number) do
          _ = notify_handler(data, :telegram, frame.telegram)

          {data, actions} =
            {%{
               data
               | buffer: rest,
                 telegrams_received: SequenceNumber.increment(data.telegrams_received)
             }, []}
            |> handle_telegram_receipt(frame.received_sequence_number)
            |> data_transfer_idle_timeout()
            |> maybe_schedule_telegram_receipt()
            |> handle_next_frame()

          {:keep_state, data, actions}
        else
          {data, actions} =
            {data, []}
            |> reset_data_transfer()
            |> disconnect()

          {:next_state, :disconnected, data, actions}
        end

      {:ok, %SupervisoryFunction{} = frame, rest} ->
        if valid_received_sequence_number?(data, frame.received_sequence_number) do
          {data, actions} =
            {%{data | buffer: rest}, []}
            |> handle_telegram_receipt(frame.received_sequence_number)
            |> data_transfer_idle_timeout()
            |> handle_next_frame()

          {:keep_state, data, actions}
        else
          {data, actions} =
            {data, []}
            |> reset_data_transfer()
            |> disconnect()

          {:next_state, :disconnected, data, actions}
        end

      {:ok, %ControlFunction{function: :test_frame_activation}, rest} ->
        %ControlFunction{function: :test_frame_confirmation}
        |> send_frame(data)
        |> case do
          :ok ->
            {data, actions} =
              {%{data | buffer: rest}, []}
              |> data_transfer_idle_timeout()
              |> handle_next_frame()

            {:keep_state, data, actions}

          _error ->
            {data, actions} = disconnect({data, []})
            {:next_state, :disconnected, data, actions}
        end

      {:ok, %ControlFunction{function: :test_frame_confirmation}, rest} ->
        {data, actions} =
          {%{data | buffer: rest}, [{{:timeout, :test_frame_confirmation}, :cancel}]}
          |> data_transfer_idle_timeout()
          |> handle_next_frame()

        {:keep_state, data, actions}

      {:ok, %ControlFunction{function: :stop_data_transfer_confirmation}, rest} ->
        _ = notify_handler(data, :state, :connected)

        {data, actions} =
          {%{data | buffer: rest}, []}
          |> reset_data_transfer()
          |> handle_next_frame()

        {:next_state, :connected, data, actions}

      {:error, :in_frame} ->
        :keep_state_and_data
    end
  end

  def data_transfer(:internal, :send_telegram_receipt, data) do
    send_telegram_receipt(data)
  end

  def data_transfer({:timeout, :send_telegram_receipt}, :data_transfer, data) do
    send_telegram_receipt(data)
  end

  def data_transfer({:timeout, :idle}, :data_transfer, data) do
    %ControlFunction{function: :test_frame_activation}
    |> send_frame(data)
    |> case do
      :ok ->
        {:keep_state_and_data,
         [{{:timeout, :test_frame_confirmation}, data.response_timeout, :data_transfer}]}

      _error ->
        {data, actions} = disconnect({data, []})
        {:next_state, :disconnected, data, actions}
    end
  end

  def data_transfer(:state_timeout, :response, data) do
    {data, actions} =
      {data, []}
      |> reset_data_transfer()
      |> disconnect()

    {:next_state, :disconnected, data, actions}
  end

  def data_transfer({:timeout, :test_frame_confirmation}, :data_transfer, data) do
    {data, actions} =
      {data, []}
      |> reset_data_transfer()
      |> disconnect()

    {:next_state, :disconnected, data, actions}
  end

  defp handle_telegram_receipt({data, actions}, received_sequence_number)
       when data.telegrams_delivered == received_sequence_number do
    {data, actions}
  end

  defp handle_telegram_receipt({data, actions}, received_sequence_number) do
    _ = notify_handler(data, :telegram_receipt, received_sequence_number)

    if data.telegrams_sent == received_sequence_number do
      {%{data | telegrams_delivered: received_sequence_number},
       actions ++ [{:state_timeout, :cancel}]}
    else
      {%{data | telegrams_delivered: received_sequence_number},
       actions ++ [{:state_timeout, data.response_timeout, :response}]}
    end
  end

  defp data_transfer_idle_timeout({data, actions}) do
    {data, actions ++ [{{:timeout, :idle}, data.data_transfer_idle_timeout, :data_transfer}]}
  end

  defp maybe_schedule_telegram_receipt({data, actions}) do
    cond do
      send_telegram_receipt_threshold_reached?(data) ->
        {data, actions ++ [{:next_event, :internal, :send_telegram_receipt}]}

      not data.telegram_receipt_scheduled? ->
        {%{data | telegram_receipt_scheduled?: true},
         actions ++
           [
             {{:timeout, :send_telegram_receipt}, data.send_telegram_receipt_timeout,
              :data_transfer}
           ]}

      true ->
        {data, actions}
    end
  end

  defp reset_data_transfer({data, actions}) do
    {%{data | telegrams_received: 0, telegrams_receipted: 0, telegram_receipt_scheduled?: false},
     actions ++
       [
         {{:timeout, :send_telegram_receipt}, :cancel},
         {{:timeout, :idle}, :cancel},
         {{:timeout, :test_frame_confirmation}, :cancel}
       ]}
  end

  defp disconnect({data, actions}) do
    :ok = :gen_tcp.close(data.socket)
    _ = notify_handler(data, :state, :disconnected)

    {%{data | socket: nil, buffer: <<>>},
     actions ++ [{:state_timeout, data.connect_backoff, :connect}]}
  end

  defp send_telegram_receipt(data) do
    %SupervisoryFunction{received_sequence_number: data.telegrams_received}
    |> send_frame(data)
    |> case do
      :ok ->
        {:keep_state,
         %{
           data
           | telegram_receipt_scheduled?: false,
             telegrams_receipted: data.telegrams_received
         },
         [
           {{:timeout, :send_telegram_receipt}, :cancel}
         ]}

      _error ->
        {data, actions} = disconnect({data, []})
        {:next_state, :disconnected, data, actions}
    end
  end

  defp send_frame(frame, data) do
    {:ok, frame} = Frame.encode(frame)
    :gen_tcp.send(data.socket, frame)
  end

  defp notify_handler(data, type, message) do
    send(data.handler, {__MODULE__, type, message})
  end

  defp send_telegram_receipt_threshold_reached?(data) do
    SequenceNumber.diff(data.telegrams_receipted, data.telegrams_received) >
      data.send_telegram_receipt_threshold
  end

  defp valid_sent_sequence_number?(data, sent_sequence_number) do
    data.telegrams_received == sent_sequence_number
  end

  defp valid_received_sequence_number?(data, received_sequence_number) do
    allowed_range = SequenceNumber.diff(data.telegrams_delivered, data.telegrams_sent)

    newly_acknowledged_telegrams =
      SequenceNumber.diff(data.telegrams_delivered, received_sequence_number)

    remaining_telegrams = SequenceNumber.diff(received_sequence_number, data.telegrams_sent)

    data.telegrams_sent == received_sequence_number or
      (allowed_range >= newly_acknowledged_telegrams and allowed_range > remaining_telegrams)
  end

  defp handle_next_frame({data, actions}) do
    if data.buffer == <<>> do
      {data, actions}
    else
      {data, actions ++ [{:next_event, :internal, :handle_frame}]}
    end
  end
end
