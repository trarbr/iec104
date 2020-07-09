defmodule IEC104.ControllingConnectionTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias IEC104.{ControllingConnection, Frame}
  alias IEC104.Frame.ControlFunction

  describe "connecting" do
    setup :server_socket

    test "attempts to connect when started", context do
      {:ok, _pid} = ControllingConnection.start_link(port: context.port)

      assert {:ok, socket} = :gen_tcp.accept(context.socket)
      assert_receive {ControllingConnection, :connected}
    end

    test "keeps trying if it fails to connect", context do
      :ok = :gen_tcp.close(context.socket)

      start_and_wait = fn ->
        ControllingConnection.start_link(port: context.port, connect_backoff: 10)
        Process.sleep(100)
      end

      assert capture_log(start_and_wait) =~ "could not connect"

      {:ok, socket} = :gen_tcp.listen(context.port, [:binary])

      assert {:ok, socket} = :gen_tcp.accept(socket)
      assert_receive {ControllingConnection, :connected}
    end
  end

  describe "connected" do
    setup :server_socket

    test "responds to test frames", context do
      {:ok, _pid} = ControllingConnection.start_link(port: context.port)
      {:ok, socket} = :gen_tcp.accept(context.socket)

      %Frame{apci: %ControlFunction{function: :test_frame_activation}}
      |> send_frame(socket)

      assert {:ok, frame} = :gen_tcp.recv(socket, 0)

      assert {:ok, %Frame{apci: %ControlFunction{function: :test_frame_confirmation}}, ""} ==
               Frame.decode(frame)
    end

    @tag :not_implemented
    test "sends test frames when nothing happens" do
      assert false
    end

    @tag :not_implemented
    test "sends supervisory frames when it receives a telegram, with the correct sequence numbers" do
      assert false
    end

    @tag :not_implemented
    test "can send a telegram" do
      assert false
    end
  end

  defp server_socket(context) do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, {:active, false}])
    {:ok, port} = :inet.port(socket)

    Map.merge(context, %{socket: socket, port: port})
  end

  defp send_frame(frame, socket) do
    {:ok, frame} = Frame.encode(frame)
    :ok = :gen_tcp.send(socket, frame)
  end
end
