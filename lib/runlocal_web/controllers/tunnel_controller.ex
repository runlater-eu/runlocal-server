defmodule RunlocalWeb.TunnelController do
  import Plug.Conn
  alias RunlocalWeb.TunnelErrorHTML
  require Logger

  @timeout_ms 30_000
  @max_request_size 10_000_000
  @hop_by_hop_headers ~w(transfer-encoding connection keep-alive te trailers upgrade proxy-authenticate proxy-authorization)

  def proxy(conn, subdomain) do
    case Runlocal.Registry.lookup(subdomain) do
      nil ->
        TunnelErrorHTML.send_error(conn, 404, "Tunnel not found", """
        <div class="hint">
          <p>The tunnel <code>#{subdomain}</code> is not connected. The developer may have stopped their session or the tunnel may have expired.</p>
        </div>
        <a href="https://runlocal.eu" class="btn">
          <svg viewBox="0 0 20 20" fill="currentColor" width="16" height="16"><path fill-rule="evenodd" d="M17 10a.75.75 0 0 1-.75.75H5.612l4.158 3.96a.75.75 0 1 1-1.04 1.08l-5.5-5.25a.75.75 0 0 1 0-1.08l5.5-5.25a.75.75 0 1 1 1.04 1.08L5.612 9.25H16.25A.75.75 0 0 1 17 10Z" clip-rule="evenodd" /></svg>
          Go to runlocal.eu
        </a>
        """)

      %{channel_pid: channel_pid} ->
        cond do
          not Runlocal.RateLimiter.allow?(subdomain) ->
            TunnelErrorHTML.send_error(conn, 429, "Too many requests", """
            <p>This tunnel is receiving too many requests. Please slow down and try again in a moment.</p>
            """)

          true ->
            case read_body(conn, length: @max_request_size, read_length: 1_000_000) do
              {:ok, body, conn} ->
                if not Runlocal.BandwidthLimiter.allow?(subdomain, byte_size(body)) do
                  TunnelErrorHTML.send_error(conn, 429, "Bandwidth limit exceeded", """
                  <p>This tunnel has exceeded its bandwidth limit. Please try again shortly.</p>
                  """)
                else
                  Runlocal.Stats.track_request()
                  forward_request(conn, channel_pid, body)
                end

              {:more, _partial, conn} ->
                TunnelErrorHTML.send_error(conn, 413, "Payload too large", """
                <p>The request body exceeds the maximum size of 10 MB.</p>
                """)

              {:error, _reason} ->
                TunnelErrorHTML.send_error(conn, 400, "Bad request", """
                <p>The request could not be read. Please check the request and try again.</p>
                """)
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

        if status == 502 and not has_content_type?(headers) do
          TunnelErrorHTML.send_error(conn, 502, "Bad gateway", """
          <div class="hint">
            <p>#{html_escape(resp_body)}</p>
          </div>
          <p>The tunnel is connected but your local server isn't responding. Make sure it's running on the right port.</p>
          """)
        else
          conn =
            headers
            |> Enum.reject(fn [key, _] -> key in @hop_by_hop_headers end)
            |> Enum.reduce(conn, fn [key, value], acc ->
              put_resp_header(acc, key, value)
            end)

          conn
          |> send_resp(status, resp_body)
          |> halt()
        end
    after
      @timeout_ms ->
        Logger.error("[Tunnel] TIMEOUT for #{request_id} - channel #{inspect(channel_pid)} alive=#{Process.alive?(channel_pid)}")
        TunnelErrorHTML.send_error(conn, 504, "Gateway timeout", """
        <p>The tunnel client did not respond within 30 seconds. The local server may be down or overloaded.</p>
        """)
    end
  end

  defp has_content_type?(headers) do
    Enum.any?(headers, fn [key, _] -> String.downcase(key) == "content-type" end)
  end

  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.hex_encode32(case: :lower, padding: false)
  end
end
