defmodule Lab4.Net.Frame do
  @moduledoc """
  Very small binary framing:
  [uint32_be length][payload bytes...]

  This avoids ambiguity when reading XML from raw TCP streams.
  """

  @spec encode(binary()) :: binary()
  def encode(payload) when is_binary(payload) do
    <<byte_size(payload)::unsigned-big-32, payload::binary>>
  end

  @spec decode(binary()) :: {[binary()], binary()}
  def decode(buffer) when is_binary(buffer) do
    do_decode(buffer, [])
  end

  defp do_decode(<<len::unsigned-big-32, rest::binary>>, acc) when byte_size(rest) >= len do
    <<payload::binary-size(len), tail::binary>> = rest
    do_decode(tail, [payload | acc])
  end

  defp do_decode(buffer, acc) do
    {Enum.reverse(acc), buffer}
  end
end
