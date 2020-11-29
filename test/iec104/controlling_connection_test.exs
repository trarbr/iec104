defmodule IEC104.ControllingConnectionTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias IEC104.{ControllingConnection, Frame, Telegram, InformationObject}
  alias IEC104.Frame.{ControlFunction, InformationTransfer, SupervisoryFunction}
  alias IEC104.InformationElement.QDS

  describe "connecting" do
    setup :server_socket

    test "attempts to connect when started", context do
      {:ok, _pid} = ControllingConnection.start_link(port: context.listen_port)

      assert {:ok, _socket} = :gen_tcp.accept(context.listen_socket)
      assert_receive {ControllingConnection, :connected}
    end

    test "keeps trying if it fails to connect", context do
      :ok = :gen_tcp.close(context.listen_socket)

      start_and_wait = fn ->
        ControllingConnection.start_link(port: context.listen_port, connect_backoff: 10)
        Process.sleep(1000)
      end

      assert capture_log(start_and_wait) =~ "could not connect"

      {:ok, listen_socket} = :gen_tcp.listen(context.listen_port, [:binary])

      assert {:ok, _socket} = :gen_tcp.accept(listen_socket)
      assert_receive {ControllingConnection, :connected}
    end
  end

  describe "connected" do
    setup [:server_socket]

    test "transitions to data transfer on confirmation", context do
      context = connect(context)
      assert :ok = ControllingConnection.start_data_transfer(context.conn)

      assert {:ok, frame} = :gen_tcp.recv(context.socket, 0)

      assert {:ok, %ControlFunction{function: :start_data_transfer_activation}, ""} ==
               Frame.decode(frame)

      %ControlFunction{function: :start_data_transfer_confirmation}
      |> send_frame(context.socket)

      assert_receive {ControllingConnection, :data_transfer}
    end

    test "disconnects if test frame confirmation is not received", context do
      context = connect(context, response_timeout: 1)
      assert :ok = ControllingConnection.start_data_transfer(context.conn)

      {:ok, _start_data_transfer_activation_frame} = :gen_tcp.recv(context.socket, 0)

      assert {:error, :closed} = :gen_tcp.recv(context.socket, 0)
    end

    test "reconnects if connection is closed", context do
      context = connect(context, connect_backoff: 10)

      :ok = :gen_tcp.close(context.socket)

      assert_receive {ControllingConnection, :disconnected}
      assert_receive {ControllingConnection, :connected}
    end
  end

  describe "data_transfer" do
    setup [:server_socket]

    test "responds to test frames", context do
      context = context |> connect() |> data_transfer()

      %ControlFunction{function: :test_frame_activation}
      |> send_frame(context.socket)

      assert {:ok, frame} = :gen_tcp.recv(context.socket, 0)

      assert {:ok, %ControlFunction{function: :test_frame_confirmation}, ""} ==
               Frame.decode(frame)
    end

    test "sends test frames when nothing happens", context do
      context =
        context
        |> connect(data_transfer_idle_timeout: 1)
        |> data_transfer()

      assert {:ok, frame} = :gen_tcp.recv(context.socket, 0)

      assert {:ok, %ControlFunction{function: :test_frame_activation}, ""} ==
               Frame.decode(frame)
    end

    test "disconnects if test frame confirmation is not received", context do
      context =
        context
        |> connect(response_timeout: 50, data_transfer_idle_timeout: 1)
        |> data_transfer()

      {:ok, _test_frame_activation} = :gen_tcp.recv(context.socket, 0)

      assert_receive {ControllingConnection, :disconnected}
      assert {:error, :closed} = :gen_tcp.recv(context.socket, 0)
    end

    test "notifies handler when it receives a telegram", context do
      context = context |> connect() |> data_transfer()

      %InformationTransfer{
        received_sequence_number: 0,
        sent_sequence_number: 0,
        telegram: telegram()
      }
      |> send_frame(context.socket)

      assert_receive {ControllingConnection, %IEC104.Telegram{} = telegram}
      assert telegram() == telegram
    end

    test "sends supervisory frame on sequence synchronization timeout", context do
      context =
        context
        |> connect(send_telegram_receipt_timeout: 1)
        |> data_transfer()

      Enum.each(0..:rand.uniform(10), fn n ->
        %InformationTransfer{
          received_sequence_number: 0,
          sent_sequence_number: n,
          telegram: telegram()
        }
        |> send_frame(context.socket)

        assert {:ok, frame} = :gen_tcp.recv(context.socket, 0)

        assert {:ok, %SupervisoryFunction{received_sequence_number: n + 1}, ""} ==
                 Frame.decode(frame)
      end)
    end

    test "performs sequence synchronization correctly for a batch of telegrams", context do
      context =
        context
        |> connect(send_telegram_receipt_timeout: 100)
        |> data_transfer()

      # This goes to a maximum of 8 telegrams, to avoid crossing the
      # send_telegram_receipt_threshold
      last_sent_sequence_number =
        Enum.reduce(0..:rand.uniform(8), 0, fn n, _acc ->
          %InformationTransfer{
            received_sequence_number: 0,
            sent_sequence_number: n,
            telegram: telegram()
          }
          |> send_frame(context.socket)

          n
        end)

      assert {:ok, frame} = :gen_tcp.recv(context.socket, 0)

      assert {:ok, %SupervisoryFunction{received_sequence_number: last_sent_sequence_number + 1},
              ""} ==
               Frame.decode(frame)
    end

    test "disconnects when information transfer contains wrong sent_sequence_number", context do
      context = context |> connect() |> data_transfer()

      %InformationTransfer{
        received_sequence_number: 0,
        sent_sequence_number: 1,
        telegram: telegram()
      }
      |> send_frame(context.socket)

      assert_receive {ControllingConnection, :disconnected}
      assert {:error, :closed} = :gen_tcp.recv(context.socket, 0)
    end

    test "performs sequence synchronization when sequence synchronization threshold is reached",
         context do
      threshold = :rand.uniform(20)

      context =
        context
        |> connect(send_telegram_receipt_threshold: threshold)
        |> data_transfer()

      Enum.each(0..(threshold - 1), fn n ->
        %InformationTransfer{
          received_sequence_number: 0,
          sent_sequence_number: n,
          telegram: telegram()
        }
        |> send_frame(context.socket)
      end)

      # Ensure that no message is sent before the threshold is reached
      assert {:error, :timeout} = :gen_tcp.recv(context.socket, 0, 100)

      %InformationTransfer{
        received_sequence_number: 0,
        sent_sequence_number: threshold,
        telegram: telegram()
      }
      |> send_frame(context.socket)

      assert {:ok, frame} = :gen_tcp.recv(context.socket, 0, 100)

      assert {:ok, %SupervisoryFunction{received_sequence_number: threshold + 1}, ""} ==
               Frame.decode(frame)
    end

    test "can send a telegram", context do
      context = context |> connect() |> data_transfer()

      expected = %InformationTransfer{
        received_sequence_number: 0,
        sent_sequence_number: 0,
        telegram: telegram()
      }

      ControllingConnection.send_telegram(context.conn, expected.telegram)

      assert {:ok, frame} = :gen_tcp.recv(context.socket, 0)
      assert {:ok, expected, <<>>} == Frame.decode(frame)
    end

    test "increments sequence numbers correctly when sending telegrams", context do
      context = context |> connect() |> data_transfer()

      Enum.each(0..9, fn n ->
        assert {:ok, sequence_number} =
                 ControllingConnection.send_telegram(context.conn, telegram())

        assert sequence_number == n + 1
        assert {:ok, frame} = :gen_tcp.recv(context.socket, 0)

        assert {:ok, %InformationTransfer{sent_sequence_number: ^n}, <<>>} = Frame.decode(frame)
      end)
    end

    test "sends an updated received_sequence_number when sending a telegram", context do
      context = context |> connect() |> data_transfer()

      # This goes to a maximum of 8 telegrams, to avoid crossing the
      # send_telegram_receipt_threshold
      last_sent_sequence_number =
        Enum.reduce(0..:rand.uniform(7), 0, fn n, _acc ->
          %InformationTransfer{
            received_sequence_number: 0,
            sent_sequence_number: n,
            telegram: telegram()
          }
          |> send_frame(context.socket)

          n
        end)

      Process.sleep(50)

      {:ok, _sequence_number} = ControllingConnection.send_telegram(context.conn, telegram())

      {:ok, frame} = :gen_tcp.recv(context.socket, 0)

      assert {:ok, %InformationTransfer{received_sequence_number: received_sequence_number}, _} =
               Frame.decode(frame)

      assert received_sequence_number == last_sent_sequence_number + 1
    end

    test "notifies handler when acknowledgement of information transfer is received",
         context do
      context = context |> connect() |> data_transfer()

      {:ok, sequence_number} = ControllingConnection.send_telegram(context.conn, telegram())

      %SupervisoryFunction{received_sequence_number: sequence_number}
      |> send_frame(context.socket)

      assert_receive {ControllingConnection, ^sequence_number}
    end

    test "does not notify handler when wrong received_sequence_number is received", context do
      context = context |> connect() |> data_transfer()

      wrong_sequence_number = -:rand.uniform(10)

      %SupervisoryFunction{received_sequence_number: wrong_sequence_number}
      |> send_frame(context.socket)

      refute_receive {ControllingConnection, ^wrong_sequence_number}
    end

    test "disconnects when wrong received_sequence_number is received", context do
      context = context |> connect() |> data_transfer()

      wrong_sequence_number = :rand.uniform(10)

      %SupervisoryFunction{received_sequence_number: wrong_sequence_number}
      |> send_frame(context.socket)

      assert_receive {ControllingConnection, :disconnected}
      assert {:error, :closed} = :gen_tcp.recv(context.socket, 0)
    end

    test "disconnects when no acknowledgement of information transfer is received", context do
      context = context |> connect(response_timeout: 1) |> data_transfer()

      {:ok, _sequence_number} = ControllingConnection.send_telegram(context.conn, telegram())
      {:ok, _frame} = :gen_tcp.recv(context.socket, 0)

      assert_receive {ControllingConnection, :disconnected}
      assert {:error, :closed} = :gen_tcp.recv(context.socket, 0)
    end

    test "information transfer can be used to acknowledge information transfer", context do
      context = context |> connect() |> data_transfer()

      {:ok, sequence_number} = ControllingConnection.send_telegram(context.conn, telegram())

      %InformationTransfer{
        received_sequence_number: sequence_number,
        sent_sequence_number: 0,
        telegram: telegram()
      }
      |> send_frame(context.socket)

      assert_receive {ControllingConnection, ^sequence_number}
    end

    test "transitions to connected when data transfer is stopped", context do
      context = context |> connect() |> data_transfer()
      ControllingConnection.stop_data_transfer(context.conn)

      assert {:ok, frame} = :gen_tcp.recv(context.socket, 0)

      assert {:ok, %ControlFunction{function: :stop_data_transfer_activation}, ""} ==
               Frame.decode(frame)

      %ControlFunction{function: :stop_data_transfer_confirmation}
      |> send_frame(context.socket)

      assert_receive {ControllingConnection, :connected}
    end

    test "reconnects if connection is closed", context do
      context = context |> connect(connect_backoff: 10) |> data_transfer()

      :ok = :gen_tcp.close(context.socket)

      assert_receive {ControllingConnection, :disconnected}
      assert_receive {ControllingConnection, :connected}
    end
  end

  defp server_socket(context) do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, {:active, false}])
    {:ok, listen_port} = :inet.port(listen_socket)

    Map.merge(context, %{listen_socket: listen_socket, listen_port: listen_port})
  end

  defp connect(context, connection_args \\ []) do
    {:ok, conn} = ControllingConnection.start_link(connection_args ++ [port: context.listen_port])
    {:ok, socket} = :gen_tcp.accept(context.listen_socket)

    receive do
      {ControllingConnection, :connected} ->
        Map.merge(context, %{conn: conn, socket: socket})
    end
  end

  defp data_transfer(context) do
    :ok = ControllingConnection.start_data_transfer(context.conn)
    {:ok, frame} = :gen_tcp.recv(context.socket, 0)

    {:ok, %ControlFunction{function: :start_data_transfer_activation}, ""} = Frame.decode(frame)

    %ControlFunction{function: :start_data_transfer_confirmation}
    |> send_frame(context.socket)

    receive do
      {ControllingConnection, :data_transfer} -> context
    end
  end

  defp send_frame(frame, socket) do
    {:ok, frame} = Frame.encode(frame)
    :ok = :gen_tcp.send(socket, frame)
  end

  defp telegram() do
    %Telegram{
      type: InformationObject.M_ME_NB_1,
      cause_of_transmission: :spontaneous,
      negative_confirmation?: false,
      test?: false,
      originator_address: 0,
      common_address: 12,
      information_objects: %{12304 => {2494, QDS.new()}}
    }
  end
end
