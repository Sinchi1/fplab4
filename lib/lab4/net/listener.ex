defmodule Lab4.Net.Listener do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    port = Keyword.fetch!(opts, :port)
    username = Keyword.fetch!(opts, :username)
    psk = Keyword.fetch!(opts, :psk)

    tcp_opts = [
      :binary,
      active: false,
      packet: :raw,
      reuseaddr: true,
      nodelay: true,
      backlog: 128
    ]

    case :gen_tcp.listen(port, tcp_opts) do
      {:ok, lsock} ->
        Logger.info("Listening on 0.0.0.0:#{port}")
        state = %{lsock: lsock, username: username, psk: psk}
        send(self(), :accept)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:accept, st) do
    case :gen_tcp.accept(st.lsock) do
      {:ok, sock} ->
        spec =
          {Lab4.Net.Session,
           [
             role: :server,
             socket: sock,
             username: st.username,
             psk: st.psk
           ]}

        case DynamicSupervisor.start_child(Lab4.RuntimeSupervisor, spec) do
          {:ok, sess_pid} ->
            :ok = :gen_tcp.controlling_process(sock, sess_pid)

          {:error, reason} ->
            Logger.error("Failed to start session: #{inspect(reason)}")
            :gen_tcp.close(sock)
        end

        send(self(), :accept)
        {:noreply, st}

      {:error, reason} ->
        {:stop, reason, st}
    end
  end
end
