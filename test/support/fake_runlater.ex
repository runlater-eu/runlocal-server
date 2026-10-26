defmodule RunlocalWeb.FakeRunlater do
  @moduledoc """
  Stands in for runlater's `/api/v1/verify-tunnel` so :runlater mode can be
  exercised in tests. Every key is accepted for the configured org.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(%{method: "POST", path_info: ["api", "v1", "verify-tunnel"]} = conn, opts) do
    body =
      Jason.encode!(%{
        "valid" => true,
        "org_slug" => Keyword.fetch!(opts, :org_slug),
        "tier" => Keyword.get(opts, :tier, "free")
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  def call(conn, _opts), do: send_resp(conn, 404, "")
end
