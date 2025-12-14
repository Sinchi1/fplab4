defmodule Lab4.Xml do
  @moduledoc false

  require Record

  # Records come from exml include files.
  Record.defrecord(:xmlel, Record.extract(:xmlel, from_lib: "exml/include/exml.hrl"))
  Record.defrecord(:xmlcdata, Record.extract(:xmlcdata, from_lib: "exml/include/exml.hrl"))

  def parse(bin) when is_binary(bin) do
    :exml.parse(bin)
  end

  def to_binary(term) do
    :exml.to_binary(term)
  end

  ## Elements

  # Pseudo-XMPP stream header, sent once per direction
  def stream_start(username) do
    xmlel(
      name: b("stream"),
      attrs: [{b("user"), b(username)}, {b("version"), b("1.0")}],
      children: []
    )
  end

  def handshake(username, key) do
    xmlel(
      name: b("handshake"),
      attrs: [{b("user"), b(username)}, {b("key"), b(key)}],
      children: []
    )
  end

  def ok(username) do
    xmlel(
      name: b("ok"),
      attrs: [{b("user"), b(username)}],
      children: []
    )
  end

  def error(reason) do
    xmlel(
      name: b("error"),
      attrs: [{b("reason"), b(reason)}],
      children: []
    )
  end

  def message(from, to, body) do
    xmlel(
      name: b("message"),
      attrs: [{b("from"), b(from)}, {b("to"), b(to)}, {b("type"), b("chat")}],
      children: [
        xmlel(
          name: b("body"),
          attrs: [],
          children: [xmlcdata(content: b(body))]
        )
      ]
    )
  end

  def ping do
    xmlel(
      name: b("ping"),
      attrs: [],
      children: []
    )
  end

  def pong do
    xmlel(
      name: b("pong"),
      attrs: [],
      children: []
    )
  end

  ## Classification

  def classify(doc) do
    cond do
      match?(xmlel(name: <<"stream">>), doc) ->
        {:stream, get_attr(doc, "user")}

      match?(xmlel(name: <<"handshake">>), doc) ->
        {:handshake, get_attr(doc, "user"), get_attr(doc, "key")}

      match?(xmlel(name: <<"ok">>), doc) ->
        {:ok, get_attr(doc, "user")}

      match?(xmlel(name: <<"error">>), doc) ->
        {:error, get_attr(doc, "reason")}

      match?(xmlel(name: <<"message">>), doc) ->
        from = get_attr(doc, "from")
        to = get_attr(doc, "to")
        body = get_body(doc)
        {:message, from, to, body}

      match?(xmlel(name: <<"ping">>), doc) ->
        {:ping}

      match?(xmlel(name: <<"pong">>), doc) ->
        {:pong}

      true ->
        {:unknown, doc}
    end
  end

  ## Helpers

  defp get_attr(doc, key) do
    attrs = xmlel(doc, :attrs)

    case Enum.find(attrs, fn {k, _v} -> k == b(key) end) do
      {_, v} -> to_string(v)
      nil -> nil
    end
  end

  defp get_body(doc) do
    children = xmlel(doc, :children)

    case Enum.find(children, fn ch -> match?(xmlel(name: <<"body">>), ch) end) do
      nil ->
        ""

      body_el ->
        inner = xmlel(body_el, :children)

        case Enum.find(inner, fn x -> match?(xmlcdata(), x) end) do
          nil -> ""
          cdata -> to_string(xmlcdata(cdata, :content))
        end
    end
  end

  defp b(x) when is_binary(x), do: x
  defp b(x) when is_list(x), do: :unicode.characters_to_binary(x)
  defp b(x), do: x |> to_string() |> :unicode.characters_to_binary()
end
