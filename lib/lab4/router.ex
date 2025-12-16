defmodule Lab4.Router do
  use GenServer

  @type state :: %{
          username: String.t() | nil,
          psk: String.t() | nil,
          listener: pid() | nil,
          ui_pid: pid() | nil,
          sessions: MapSet.t(pid())
        }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end


  def attach_ui(pid) when is_pid(pid), do: GenServer.call(__MODULE__, {:attach_ui, pid})

  def configure_identity(username, psk) do
    GenServer.call(__MODULE__, {:configure_identity, username, psk})
  end

  def change_nick(new_username) do
    GenServer.call(__MODULE__, {:change_nick, new_username})
  end

  def listen(port) when is_integer(port) do
    GenServer.call(__MODULE__, {:listen, port})
  end

  def connect(host, port) when is_binary(host) and is_integer(port) do
    GenServer.call(__MODULE__, {:connect, host, port})
  end

  def peers do
    Registry.select(Lab4.PeerRegistry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  end

  def send_msg(peer_username, text) do
    GenServer.call(__MODULE__, {:send_msg, peer_username, text})
  end

  def identity do
    GenServer.call(__MODULE__, :identity)
  end


  def register_session(pid) do
    GenServer.cast(__MODULE__, {:register_session, pid})
  end

  def unregister_session(pid) do
    GenServer.cast(__MODULE__, {:unregister_session, pid})
  end

  def register_peer(peer_username, session_pid) do
    Registry.register(Lab4.PeerRegistry, peer_username, session_pid)
    notify_ui({:peer_up, peer_username})
    :ok
  end

  def unregister_peer(peer_username) do
    Registry.unregister(Lab4.PeerRegistry, peer_username)
    notify_ui({:peer_down, peer_username})
    :ok
  end

  def incoming_message(from, body) do
    notify_ui({:incoming, from, body})
    :ok
  end

  defp notify_ui(msg) do
    case GenServer.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:notify_ui, msg})
    end
  end

  ## GenServer

  @impl true
  def init(_args) do
    {:ok, %{username: nil, psk: nil, listener: nil, ui_pid: nil, sessions: MapSet.new()}}
  end

  @impl true
  def handle_call({:attach_ui, pid}, _from, st) do
    {:reply, :ok, %{st | ui_pid: pid}}
  end

  @impl true
  def handle_call({:configure_identity, username, psk}, _from, st) do
    {:reply, :ok, %{st | username: username, psk: psk}}
  end

  @impl true
  def handle_call(:identity, _from, st) do
    {:reply, {st.username, st.psk}, st}
  end

  @impl true
  def handle_call({:change_nick, new_username}, _from, st) do
    Enum.each(st.sessions, fn pid ->
      GenServer.cast(pid, {:set_username, new_username})
    end)

    {:reply, :ok, %{st | username: new_username}}
  end

  @impl true
  def handle_call({:listen, port}, _from, st) do
    if st.username == nil or st.psk == nil do
      {:reply, {:error, :identity_not_set}, st}
    else
      spec = {Lab4.Net.Listener, [port: port, username: st.username, psk: st.psk]}

      case DynamicSupervisor.start_child(Lab4.RuntimeSupervisor, spec) do
        {:ok, pid} ->
          {:reply, {:ok, pid}, %{st | listener: pid}}

        {:error, {:already_started, pid}} ->
          {:reply, {:ok, pid}, %{st | listener: pid}}

        {:error, reason} ->
          {:reply, {:error, reason}, st}
      end
    end
  end

  @impl true
  def handle_call({:connect, host, port}, _from, st) do
    if st.username == nil or st.psk == nil do
      {:reply, {:error, :identity_not_set}, st}
    else
      spec =
        {Lab4.Net.Session,
         [
           role: :client,
           host: host,
           port: port,
           username: st.username,
           psk: st.psk
         ]}

      case DynamicSupervisor.start_child(Lab4.RuntimeSupervisor, spec) do
        {:ok, pid} -> {:reply, {:ok, pid}, st}
        {:error, reason} -> {:reply, {:error, reason}, st}
      end
    end
  end


@impl true
def handle_call({:send_msg, peer_username, text}, _from, st) do
  case Registry.lookup(Lab4.PeerRegistry, peer_username) do
    [{_owner_pid, session_pid} | _] ->
      res = GenServer.call(session_pid, {:send_chat, peer_username, text})
      {:reply, res, st}

    [] ->
      {:reply, {:error, :unknown_peer}, st}
  end
end



  @impl true
  def handle_cast({:register_session, pid}, st) do
    {:noreply, %{st | sessions: MapSet.put(st.sessions, pid)}}
  end

  @impl true
  def handle_cast({:unregister_session, pid}, st) do
    {:noreply, %{st | sessions: MapSet.delete(st.sessions, pid)}}
  end

  @impl true
  def handle_cast({:notify_ui, msg}, st) do
    if is_pid(st.ui_pid) do
      send(st.ui_pid, msg)
    end

    {:noreply, st}
  end
end
