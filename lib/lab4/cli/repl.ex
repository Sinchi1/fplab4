defmodule Lab4.CLI.Repl do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    username = Keyword.fetch!(opts, :username)
    st = %{username: username, history: [], last_peer: nil, active_peer: nil}

    repl_pid = self()
    gl = Process.group_leader()

    Task.start_link(fn ->
      Process.group_leader(self(), gl)

      IO.stream(:stdio, :line)
      |> Enum.each(fn line ->
        send(repl_pid, {:line, String.trim(line)})
      end)

      send(repl_pid, {:line, "/quit"})
    end)

    IO.puts(help_text())
    prompt(username)
    {:ok, st}
  end

  @impl true
  def handle_info({:line, ""}, st) do
    prompt(st.username)
    {:noreply, st}
  end

  @impl true
  def handle_info({:line, line}, st) do
    {line, st} = maybe_expand_history(line, st)
    st = push_history(line, st)

    st =
      case parse_command(line) do
        {:help} ->
          IO.puts(help_text())
          st

        {:history} ->
          print_history(st.history)
          st

        {:peers} ->
          peers = Lab4.Router.peers()
          print_peers(peers)
          st

        {:msg, peer, text} ->
          send_to_peer(peer, text)
          %{st | last_peer: peer, active_peer: st.active_peer || peer}

        {:send_default, text} ->
          case resolve_default_peer(st) do
            {:ok, peer} ->
              send_to_peer(peer, text)
              %{st | last_peer: peer, active_peer: st.active_peer || peer}

            {:error, reason} ->
              IO.puts(reason)
              st
          end

        {:nick, new_username} ->
          :ok = Lab4.Router.change_nick(new_username)
          IO.puts("Nick changed to #{new_username}")
          %{st | username: new_username}

        {:use, peer} ->
          IO.puts("Active peer: #{peer}")
          %{st | active_peer: peer}

        {:quit} ->
          IO.puts("Bye.")
          System.halt(0)

        {:unknown, _} ->
          IO.puts("Unknown command. Type /help")
          st
      end

    prompt(st.username)
    {:noreply, st}
  end


  @impl true
  def handle_info({:incoming, from, body}, st) do
    IO.puts("\n#{from}: #{body}")

    st = %{st | last_peer: from, active_peer: st.active_peer || from}

    prompt(st.username)
    {:noreply, st}
  end

  @impl true
  def handle_info({:peer_up, peer}, st) do
    IO.puts("\n[peer up] #{peer}")
    prompt(st.username)
    {:noreply, st}
  end

  @impl true
  def handle_info({:peer_down, peer}, st) do
    IO.puts("\n[peer down] #{peer}")
    prompt(st.username)
    {:noreply, st}
  end

  defp parse_command("/help"), do: {:help}
  defp parse_command("/history"), do: {:history}
  defp parse_command("/peers"), do: {:peers}
  defp parse_command("/quit"), do: {:quit}

  defp parse_command(line) do
    cond do
      String.starts_with?(line, "/msg ") ->
        rest = String.trim_leading(line, "/msg ")

        case String.split(rest, " ", parts: 2) do
          [peer, text] -> {:msg, peer, text}
          _ -> {:unknown, line}
        end

      String.starts_with?(line, "/nick ") ->
        new = String.trim_leading(line, "/nick ") |> String.trim()

        if new == "" do
          {:unknown, line}
        else
          {:nick, new}
        end

      String.starts_with?(line, "/use ") ->
        peer = String.trim_leading(line, "/use ") |> String.trim()

        if peer == "" do
          {:unknown, line}
        else
          {:use, peer}
        end

      String.starts_with?(line, "/") ->
        {:unknown, line}

      true ->
        {:send_default, line}
    end
  end

  defp send_to_peer(peer, text) do
    case Lab4.Router.send_msg(peer, text) do
      :ok -> :ok
      {:error, reason} -> IO.puts("Send error: #{inspect(reason)}")
    end
  end

  defp resolve_default_peer(st) do
    cond do
      st.active_peer != nil ->
        {:ok, st.active_peer}

      st.last_peer != nil ->
        {:ok, st.last_peer}

      true ->
        peers = Lab4.Router.peers()

        case peers do
          [{peer, _pid}] ->
            {:ok, peer}

          [] ->
            {:error, "No peers connected. Use /peers."}

          _many ->
            {:error, "Multiple peers. Use /use <peer> or /msg <peer> <text>."}
        end
    end
  end

  defp push_history(line, st) do
    history =
      case st.history do
        [^line | _] -> st.history
        _ -> [line | st.history]
      end

    %{st | history: Enum.take(history, 50)}
  end

  defp maybe_expand_history("!" <> n, st) do
    case Integer.parse(n) do
      {idx, ""} ->
        list = Enum.reverse(st.history)

        if idx >= 1 and idx <= length(list) do
          expanded = Enum.at(list, idx - 1)
          IO.puts(expanded)
          {expanded, st}
        else
          {"", st}
        end

      _ ->
        {"", st}
    end
  end

  defp maybe_expand_history(line, st), do: {line, st}

  defp print_history(history) do
    list = Enum.reverse(history)

    list
    |> Enum.with_index(1)
    |> Enum.each(fn {cmd, i} -> IO.puts("#{i}: #{cmd}") end)

    IO.puts("Use !N to repeat.")
  end

  defp print_peers(peers) do
    if peers == [] do
      IO.puts("(no peers)")
    else
      Enum.each(peers, fn {peer, _pid} -> IO.puts(peer) end)
    end
  end

  defp prompt(username) do
    IO.write("#{username}> ")
  end

  defp help_text do
    """
    Commands:
      /help
      /peers
      /msg <peer_username> <text>
      /nick <new_username>
      /use <peer_username>   (set active peer)
      /history
      !<n>   (repeat command)
      /quit

    Plain text without leading '/' is sent to the active peer.
    """
  end
end
