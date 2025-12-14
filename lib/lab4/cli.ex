defmodule Lab4.CLI do
  @moduledoc false

  def main(argv) do
    {:ok, _} = Application.ensure_all_started(:lab4)

    case argv do
      ["serve" | rest] ->
        serve(rest)

      ["connect" | rest] ->
        connect(rest)

      _ ->
        usage()
    end
  end

  defp serve(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [username: :string, port: :integer, key: :string],
        aliases: [u: :username, p: :port, k: :key]
      )

    username = opts[:username] || "user"
    port = opts[:port] || 5555
    psk = opts[:key] || Lab4.PSK.generate_base64url_32()

    :ok = Lab4.Router.configure_identity(username, psk)
    {:ok, _} = Lab4.Router.listen(port)

    IO.puts("Serving as #{username} on port #{port}")
    IO.puts("PSK: #{psk}")

    start_repl(username)
  end

  defp connect(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [username: :string, host: :string, port: :integer, key: :string],
        aliases: [u: :username, h: :host, p: :port, k: :key]
      )

    username = opts[:username] || "user"
    host = opts[:host] || "127.0.0.1"
    port = opts[:port] || 5555
    psk = opts[:key] || ""

    :ok = Lab4.Router.configure_identity(username, psk)

    case Lab4.Router.connect(host, port) do
      {:ok, _pid} ->
        IO.puts("Connected to #{host}:#{port} as #{username}")
        start_repl(username)

      {:error, reason} ->
        IO.puts("Connect error: #{inspect(reason)}")
        System.halt(2)
    end
  end

  defp start_repl(username) do
    {:ok, repl} = Lab4.CLI.Repl.start_link(username: username)
    :ok = Lab4.Router.attach_ui(repl)
    Process.sleep(:infinity)
  end

  defp usage do
    IO.puts("""
    lab4 serve   --username NAME [--port 5555] [--key PSK]
    lab4 connect --username NAME --host HOST [--port 5555] --key PSK
    """)
  end
end
