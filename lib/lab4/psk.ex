defmodule Lab4.PSK do
  @spec generate_base64url_32() :: String.t()
  def generate_base64url_32 do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
