defmodule RunlocalWeb.TunnelController do
  import Plug.Conn
  require Logger

  @timeout_ms 30_000
  @max_request_size 10_000_000
  @hop_by_hop_headers ~w(transfer-encoding connection keep-alive te trailers upgrade proxy-authenticate proxy-authorization)

  def proxy(conn, subdomain) do
    case Runlocal.Registry.lookup(subdomain) do
      nil ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "Tunnel not found: #{subdomain}")
        |> halt()

      %{channel_pid: channel_pid} ->
        cond do
          not Runlocal.RateLimiter.allow?(subdomain) ->
            conn
            |> put_resp_content_type("text/plain")
            |> send_resp(429, "Too Many Requests")
            |> halt()

          true ->
            case read_body(conn, length: @max_request_size, read_length: 1_000_000) do
              {:ok, body, conn} ->
                if not Runlocal.BandwidthLimiter.allow?(subdomain, byte_size(body)) do
                  conn
                  |> put_resp_content_type("text/plain")
                  |> send_resp(429, "Bandwidth limit exceeded")
                  |> halt()
                else
                  Runlocal.Stats.track_request()
                  forward_request(conn, channel_pid, body)
                end

              {:more, _partial, conn} ->
                conn
                |> put_resp_content_type("text/plain")
                |> send_resp(413, "Payload Too Large")
                |> halt()

              {:error, _reason} ->
                conn
                |> put_resp_content_type("text/plain")
                |> send_resp(400, "Bad Request")
                |> halt()
            end
        end
    end
  end

  defp forward_request(conn, channel_pid, body) do
    request_id = generate_request_id()

    request_data = %{
      "method" => conn.method,
      "path" => conn.request_path,
      "query_string" => conn.query_string,
      "headers" => Enum.map(conn.req_headers, fn {k, v} -> [k, v] end),
      "body" => body
    }

    Logger.info("[Tunnel] Sending request #{request_id} to channel #{inspect(channel_pid)} alive=#{Process.alive?(channel_pid)}")
    send(channel_pid, {:http_request, request_id, request_data, self()})

    receive do
      {:tunnel_response, ^request_id, response} ->
        Logger.info("[Tunnel] Got response for #{request_id} status=#{response["status"]}")
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
        Logger.error("[Tunnel] TIMEOUT for #{request_id} - channel #{inspect(channel_pid)} alive=#{Process.alive?(channel_pid)}")
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(504, "Gateway timeout: tunnel client did not respond")
        |> halt()
    end
  end

  defp generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.hex_encode32(case: :lower, padding: false)
  end
end
