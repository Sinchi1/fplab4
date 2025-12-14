defmodule Lab4.Net.Session do
  @moduledoc false
  use GenServer
  require Logger

  alias Lab4.Net.Frame
  alias Lab4.Xml

  @ping_interval 30_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    role = Keyword.fetch!(opts, :role)
    username = Keyword.fetch!(opts, :username)
    psk = Keyword.fetch!(opts, :psk)

    now = System.monotonic_time(:millisecond)

    case role do
      :client ->
        host = Keyword.fetch!(opts, :host)
        port = Keyword.fetch!(opts, :port)

        tcp_opts = [:binary, active: false, packet: :raw, nodelay: true]

        with {:ok, sock} <- :gen_tcp.connect(String.to_charlist(host), port, tcp_opts, 5_000) do
          :ok = :inet.setopts(sock, active: :once)
          st = base_state(role, sock, username, psk, now)
          Lab4.Router.register_session(self())
          send(self(), :send_stream)
          send(self(), :send_handshake)
          Process.send_after(self(), :tick, @ping_interval)
          {:ok, st}
        else
          {:error, reason} -> {:stop, reason}
        end

      :server ->
        sock = Keyword.fetch!(opts, :socket)
        :ok = :inet.setopts(sock, active: :once)
        st = base_state(role, sock, username, psk, now)
        Lab4.Router.register_session(self())
        Process.send_after(self(), :tick, @ping_interval)
        {:ok, st}
    end
  end

  defp base_state(role, sock, username, psk, now) do
    %{
      role: role,
      sock: sock,
      username: username,
      psk: psk,
      authed?: false,
      peer_username: nil,
      buffer: <<>>,
      last_rx: now
    }
  end

  ## GenServer callbacks

  @impl true
  def handle_info(:send_stream, st) do
    frame =
      st.username
      |> Xml.stream_start()
      |> Xml.to_binary()

    :ok = :gen_tcp.send(st.sock, Frame.encode(frame))
    {:noreply, st}
  end

  @impl true
  def handle_info(:send_handshake, st) do
    hs = Xml.handshake(st.username, st.psk) |> Xml.to_binary()
    :ok = :gen_tcp.send(st.sock, Frame.encode(hs))
    {:noreply, st}
  end

  @impl true
  def handle_info({:tcp, _sock, data}, st) do
    st = %{st | buffer: st.buffer <> data}
    {frames, rest} = Frame.decode(st.buffer)
    st = %{st | buffer: rest}

    st =
      Enum.reduce(frames, st, fn frame, acc ->
        handle_frame(frame, acc)
      end)

    :ok = :inet.setopts(st.sock, active: :once)
    {:noreply, st}
  end

  @impl true
  def handle_info({:tcp_closed, _sock}, st) do
    if st.peer_username, do: Lab4.Router.unregister_peer(st.peer_username)
    Lab4.Router.unregister_session(self())
    {:stop, :normal, st}
  end

  @impl true
  def handle_info({:tcp_error, _sock, reason}, st) do
    if st.peer_username, do: Lab4.Router.unregister_peer(st.peer_username)
    Lab4.Router.unregister_session(self())
    {:stop, reason, st}
  end

  @impl true
  def handle_info(:tick, st) do
    now = System.monotonic_time(:millisecond)

    st =
      if st.authed? and now - st.last_rx >= @ping_interval do
        ping = Xml.ping() |> Xml.to_binary()
        :ok = :gen_tcp.send(st.sock, Frame.encode(ping))
        st
      else
        st
      end

    Process.send_after(self(), :tick, @ping_interval)
    {:noreply, st}
  end

  @impl true
  def handle_call({:send_chat, to_peer, text}, _from, st) do
    if st.authed? do
      from = st.username
      msg = Xml.message(from, to_peer, text) |> Xml.to_binary()
      res = :gen_tcp.send(st.sock, Frame.encode(msg))
      {:reply, res, st}
    else
      {:reply, {:error, :not_authenticated}, st}
    end
  end

  @impl true
  def handle_cast({:set_username, new_username}, st) do
    {:noreply, %{st | username: new_username}}
  end

  ## Internal

  defp handle_frame(frame, st) do
    case Xml.parse(frame) do
      {:ok, doc} ->
        case Xml.classify(doc) do
          {:stream, peer_user} ->
            Logger.debug("Stream header from #{inspect(peer_user)}")
            touch(st)

          {:handshake, peer_user, key} ->
            st = touch(st)
            handle_handshake(peer_user, key, st)

          {:ok, peer_user} ->
            st = touch(st)
            handle_ok(peer_user, st)

          {:error, reason} ->
            Logger.warning("Peer error: #{inspect(reason)}")
            touch(st)

          {:message, from, _to, body} ->
            Lab4.Router.incoming_message(from, body)
            touch(st)

          {:ping} ->
            pong = Xml.pong() |> Xml.to_binary()
            :ok = :gen_tcp.send(st.sock, Frame.encode(pong))
            touch(st)

          {:pong} ->
            touch(st)

          {:unknown, _} ->
            st
        end

      {:error, reason} ->
        Logger.warning("Bad XML frame: #{inspect(reason)}")
        st
    end
  end

  defp handle_handshake(peer_user, key, st) do
    cond do
      st.authed? ->
        st

      key != st.psk ->
        err = Xml.error("bad-key") |> Xml.to_binary()
        _ = :gen_tcp.send(st.sock, Frame.encode(err))
        _ = :gen_tcp.close(st.sock)
        st

      true ->
        ok = Xml.ok(st.username) |> Xml.to_binary()
        :ok = :gen_tcp.send(st.sock, Frame.encode(ok))
        Lab4.Router.register_peer(peer_user, self())
        %{st | authed?: true, peer_username: peer_user}
    end
  end

  defp handle_ok(peer_user, st) do
    if st.authed? do
      st
    else
      Lab4.Router.register_peer(peer_user, self())
      %{st | authed?: true, peer_username: peer_user}
    end
  end

  defp touch(st) do
    %{st | last_rx: System.monotonic_time(:millisecond)}
  end
end
