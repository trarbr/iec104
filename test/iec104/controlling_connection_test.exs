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

      assert {:ok, socket} = :gen_tcp.accept(context.listen_socket)
      assert_receive {ControllingConnection, :connected}
    end

    test "keeps trying if it fails to connect", context do
      :ok = :gen_tcp.close(context.listen_socket)

      start_and_wait = fn ->
        ControllingConnection.start_link(port: context.listen_port, connect_backoff: 10)
        Process.sleep(250)
      end

      assert capture_log(start_and_wait) =~ "could not connect"

      {:ok, listen_socket} = :gen_tcp.listen(context.listen_port, [:binary])

      assert {:ok, socket} = :gen_tcp.accept(listen_socket)
      assert_receive {ControllingConnection, :connected}
    end
  end

  describe "connected" do
    setup [:server_socket]

    test "transitions to data transfer on confirmation", context do
      context = connect(context)
      ControllingConnection.start_data_transfer(context.conn)

      assert {:ok, frame} = :gen_tcp.recv(context.socket, 0)

      assert {:ok, %ControlFunction{function: :start_data_transfer_activation}, ""} ==
               Frame.decode(frame)

      %ControlFunction{function: :start_data_transfer_confirmation}
      |> send_frame(context.socket)

      assert_receive {ControllingConnection, :data_transfer}
    end

    test "disconnects if test frame confirmation is not received", context do
      context = connect(context, response_timeout: 1)
      ControllingConnection.start_data_transfer(context.conn)

      {:ok, _start_data_transfer_activation_frame} = :gen_tcp.recv(context.socket, 0)

      assert {:error, :closed} = :gen_tcp.recv(context.socket, 0)
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
        |> connect(sequence_synchronization_timeout: 1)
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
        |> connect(sequence_synchronization_timeout: 100)
        |> data_transfer()

      last_sent_sequence_number =
        Enum.reduce(0..2, 1, fn n, _acc ->
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

    test "performs sequence synchronization when sequence synchronization threshold is reached",
         context do
      threshold = 8

      context =
        context
        |> connect(sequence_synchronization_threshold: threshold)
        |> data_transfer()

      Enum.each(0..(threshold - 1), fn n ->
        %InformationTransfer{
          received_sequence_number: 0,
          sent_sequence_number: n,
          telegram: telegram()
        }
        |> send_frame(context.socket)
      end)

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

    test "disconnects if test frame confirmation is not received", context do
      context =
        context
        |> connect(response_timeout: 1, data_transfer_idle_timeout: 50)
        |> data_transfer()

      {:ok, _test_frame_activation} = :gen_tcp.recv(context.socket, 0)

      assert {:error, :closed} = :gen_tcp.recv(context.socket, 0)
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
    ControllingConnection.start_data_transfer(context.conn)
    {:ok, frame} = :gen_tcp.recv(context.socket, 0)

    {:ok, %ControlFunction{function: :start_data_transfer_activation}, ""} = Frame.decode(frame)

    %ControlFunction{function: :start_data_transfer_confirmation}
    |> send_frame(context.socket)

    context
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
