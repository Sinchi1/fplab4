defmodule Lab4.Xml do
  @moduledoc false

  @doc """
  Minimal XML helper used by the app. Returns/accepts binaries.

  This intentionally avoids any NIFs and uses simple regex-based parsing
  because the protocol is tiny and well-known.
  """

  @spec parse(binary()) :: {:ok, binary()} | {:error, any()}
  def parse(bin) when is_binary(bin), do: {:ok, bin}
  def parse(_), do: {:error, :not_binary}

  @spec to_binary(binary()) :: binary()
  def to_binary(bin) when is_binary(bin), do: bin

  ## Elements - return binary strings
  def stream_start(username) when is_binary(username) do
    "<stream user=\"#{escape(username)}\" version=\"1.0\"/>"
  end

  def handshake(username, key) when is_binary(username) and is_binary(key) do
    "<handshake user=\"#{escape(username)}\" key=\"#{escape(key)}\"/>"
  end

  def ok(username) when is_binary(username) do
    "<ok user=\"#{escape(username)}\"/>"
  end

  def error(reason) when is_binary(reason) do
    "<error reason=\"#{escape(reason)}\"/>"
  end

  def message(from, to, body)
      when is_binary(from) and is_binary(to) and is_binary(body) do
    "<message from=\"#{escape(from)}\" to=\"#{escape(to)}\" type=\"chat\"><body>#{escape_cdata(body)}</body></message>"
  end

  def ping, do: "<ping/>"
  def pong, do: "<pong/>"

  ## Classification - analyze raw binary and return same tuples as original code
  def classify(bin) when is_binary(bin) do
    cond do
      Regex.match?(~r/^<stream(\s|>)/, bin) ->
        {:stream, get_attr(bin, "user")}

      Regex.match?(~r/^<handshake(\s|>)/, bin) ->
        {:handshake, get_attr(bin, "user"), get_attr(bin, "key")}

      Regex.match?(~r/^<ok(\s|>)/, bin) ->
        {:ok, get_attr(bin, "user")}

      Regex.match?(~r/^<error(\s|>)/, bin) ->
        {:error, get_attr(bin, "reason")}

      Regex.match?(~r/^<message(\s|>)/, bin) ->
        from = get_attr(bin, "from")
        to = get_attr(bin, "to")
        body = get_body(bin)
        {:message, from, to, body}

      Regex.match?(~r/^<ping(\s|>)/, bin) ->
        {:ping}

      Regex.match?(~r/^<pong(\s|>)/, bin) ->
        {:pong}

      true ->
        {:unknown, bin}
    end
  end

  ## Helpers

  defp get_attr(bin, key) do
    # простая регулярка для attr="value"
    case Regex.run(~r/#{key}="([^"]*)"/, bin) do
      [_, v] -> v
      _ -> nil
    end
  end

  defp get_body(bin) do
    # захватываем содержимое между <body>...</body>, s-флаг для многострочности
    case Regex.run(~r|<body>(.*?)</body>|s, bin) do
      [_, content] -> unescape_cdata(content)
      _ -> ""
    end
  end

  defp escape(s) when is_binary(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  # для текста внутри body мы тоже экранируем минимально
  defp escape_cdata(s) when is_binary(s), do: escape(s)

  defp unescape_cdata(s) when is_binary(s) do
    s
    |> String.replace("&quot;", "\"")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
  end
end
