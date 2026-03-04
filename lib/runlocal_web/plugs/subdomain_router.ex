defmodule RunlocalWeb.Plugs.SubdomainRouter do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    base_domain = Application.get_env(:runlocal, :base_domain, "localhost")

    case extract_subdomain(conn.host, base_domain) do
      nil ->
        conn

      subdomain ->
        if websocket_upgrade?(conn) do
          upgrade_websocket(conn, subdomain)
        else
          RunlocalWeb.TunnelController.proxy(conn, subdomain)
        end
    end
  end

  defp websocket_upgrade?(conn) do
    conn
    |> get_req_header("upgrade")
    |> Enum.any?(&(String.downcase(&1) == "websocket"))
  end

  defp upgrade_websocket(conn, subdomain) do
    case Runlocal.Registry.lookup(subdomain) do
      nil ->
        conn
        |> send_resp(404, "Tunnel not found")
        |> halt()

      %{channel_pid: channel_pid} ->
        if not Runlocal.RateLimiter.allow?(subdomain) do
          conn
          |> send_resp(429, "Too many requests")
          |> halt()
        else
          ws_id = :crypto.strong_rand_bytes(16) |> Base.hex_encode32(case: :lower, padding: false)

          request_data = %{
            "path" => conn.request_path,
            "query_string" => conn.query_string,
            "headers" => Enum.map(conn.req_headers, fn {k, v} -> [k, v] end)
          }

          state = %{
            channel_pid: channel_pid,
            ws_id: ws_id,
            request_data: request_data
          }

          conn
          |> WebSockAdapter.upgrade(RunlocalWeb.WsProxy, state, timeout: :infinity)
          |> halt()
        end
    end
  end

  defp extract_subdomain(host, base_domain) do
    # Strip port from host
    host = host |> String.split(":") |> List.first()

    cond do
      # localhost development: fuzzy-tiger.localhost
      base_domain == "localhost" && host != "localhost" && String.ends_with?(host, ".localhost") ->
        host |> String.replace_suffix(".localhost", "")

      # Production: fuzzy-tiger.runlocal.eu
      base_domain != "localhost" && host != base_domain && String.ends_with?(host, ".#{base_domain}") ->
        host |> String.replace_suffix(".#{base_domain}", "")

      true ->
        nil
    end
  end
end
