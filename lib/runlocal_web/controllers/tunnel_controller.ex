defmodule RunlocalWeb.TunnelController do
  import Plug.Conn

  @timeout_ms 30_000
  @hop_by_hop_headers ~w(transfer-encoding connection keep-alive te trailers upgrade proxy-authenticate proxy-authorization)

  def proxy(conn, subdomain) do
    case Runlocal.Registry.lookup(subdomain) do
      nil ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "Tunnel not found: #{subdomain}")
        |> halt()

      %{channel_pid: channel_pid} ->
        request_id = generate_request_id()
        {:ok, body, conn} = read_body(conn)

        request_data = %{
          "method" => conn.method,
          "path" => conn.request_path,
          "query_string" => conn.query_string,
          "headers" => Enum.map(conn.req_headers, fn {k, v} -> [k, v] end),
          "body" => body
        }

        send(channel_pid, {:http_request, request_id, request_data, self()})

        receive do
          {:tunnel_response, ^request_id, response} ->
            status = response["status"] || 502
            headers = response["headers"] || []
            resp_body = response["body"] || ""

            conn =
              headers
              |> Enum.reject(fn [key, _] -> key in @hop_by_hop_headers end)
              |> Enum.reduce(conn, fn [key, value], acc ->
                put_resp_header(acc, key, value)
              end)

            conn
            |> send_resp(status, resp_body)
            |> halt()
        after
          @timeout_ms ->
            conn
            |> put_resp_content_type("text/plain")
            |> send_resp(504, "Gateway timeout: tunnel client did not respond")
            |> halt()
        end
    end
  end

  defp generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.hex_encode32(case: :lower, padding: false)
  end
end
