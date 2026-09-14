defmodule RunlocalWeb.TunnelController do
  import Plug.Conn
  alias RunlocalWeb.TunnelErrorHTML
  require Logger

  # How long the local server has to produce response headers.
  @response_timeout_ms 30_000
  # How long a streaming response may stall between two chunks. Long-lived
  # responses — server-sent events, large downloads — are bounded by this gap
  # rather than by total duration, so they are not cut off at 30s.
  @stream_idle_timeout_ms 60_000
  @chunk_size 1_000_000
  # Clients too old to accept a streamed request body still have their upload
  # buffered in memory, so that path keeps its hard ceiling.
  @max_buffered_request_size 10_000_000
  @bandwidth_backoff_ms 250
  @bandwidth_max_backoffs 10
  @hop_by_hop_headers ~w(transfer-encoding connection keep-alive te trailers upgrade proxy-authenticate proxy-authorization)

  def proxy(conn, subdomain) do
    case Runlocal.Registry.lookup(subdomain) do
      nil ->
        tunnel_not_found(conn, subdomain)

      %{channel_pid: channel_pid} = entry ->
        if Runlocal.RateLimiter.allow?(subdomain) do
          Runlocal.Stats.track_request()
          request_id = generate_request_id()
          streamable? = Runlocal.Registry.supports?(entry, "stream")

          case send_request(conn, channel_pid, subdomain, request_id, streamable?) do
            {:ok, conn} -> await_response(conn, channel_pid, subdomain, request_id)
            {:sent, conn} -> conn
          end
        else
          TunnelErrorHTML.send_error(conn, 429, "Too many requests", """
          <p>This tunnel is receiving too many requests. Please slow down and try again in a moment.</p>
          """)
        end
    end
  end

  # Sends the request to the tunnel client, streaming the body in chunks when
  # it is larger than one read and the client can accept it that way. Returns
  # `{:sent, conn}` when it has already responded with an error.
  defp send_request(conn, channel_pid, subdomain, request_id, streamable?) do
    read_opts =
      if streamable? do
        [length: @chunk_size, read_length: @chunk_size]
      else
        [length: @max_buffered_request_size, read_length: @chunk_size]
      end

    case read_body(conn, read_opts) do
      {:ok, body, conn} ->
        case throttle(subdomain, byte_size(body)) do
          :ok ->
            send(channel_pid, {:http_request, request_id, request_meta(conn, body), self()})
            {:ok, conn}

          :error ->
            {:sent, bandwidth_exceeded(conn)}
        end

      {:more, first_chunk, conn} when streamable? ->
        send(channel_pid, {:http_request_start, request_id, request_meta(conn, ""), self()})
        pump_request(conn, channel_pid, subdomain, request_id, first_chunk)

      {:more, _partial, conn} ->
        TunnelErrorHTML.send_error(conn, 413, "Payload too large", """
        <p>The request body exceeds the maximum size of 10 MB.</p>
        """)
        |> then(&{:sent, &1})

      {:error, _reason} ->
        TunnelErrorHTML.send_error(conn, 400, "Bad request", """
        <p>The request could not be read. Please check the request and try again.</p>
        """)
        |> then(&{:sent, &1})
    end
  end

  defp pump_request(conn, channel_pid, subdomain, request_id, chunk) do
    case throttle(subdomain, byte_size(chunk)) do
      :error ->
        cancel(channel_pid, request_id)
        {:sent, bandwidth_exceeded(conn)}

      :ok ->
        send(channel_pid, {:http_request_chunk, request_id, chunk})

        case read_body(conn, length: @chunk_size, read_length: @chunk_size) do
          {:ok, last, conn} ->
            if last != "", do: send(channel_pid, {:http_request_chunk, request_id, last})
            send(channel_pid, {:http_request_end, request_id})
            {:ok, conn}

          {:more, next, conn} ->
            pump_request(conn, channel_pid, subdomain, request_id, next)

          {:error, _reason} ->
            cancel(channel_pid, request_id)

            TunnelErrorHTML.send_error(conn, 400, "Bad request", """
            <p>The request could not be read. Please check the request and try again.</p>
            """)
            |> then(&{:sent, &1})
        end
    end
  end

  defp await_response(conn, channel_pid, subdomain, request_id) do
    receive do
      {:tunnel_response_start, ^request_id, status, headers} ->
        stream_response(conn, channel_pid, subdomain, request_id, status, headers)

      {:tunnel_response, ^request_id, response} ->
        send_buffered_response(conn, response)
    after
      @response_timeout_ms ->
        Logger.error("[Tunnel] TIMEOUT for #{request_id} waiting on response headers")
        cancel(channel_pid, request_id)

        TunnelErrorHTML.send_error(conn, 504, "Gateway timeout", """
        <p>The tunnel client did not respond within 30 seconds. The local server may be down or overloaded.</p>
        """)
    end
  end

  defp send_buffered_response(conn, response) do
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
      conn
      |> put_proxied_headers(headers)
      |> send_resp(status, resp_body)
      |> halt()
    end
  end

  defp stream_response(conn, channel_pid, subdomain, request_id, status, headers) do
    conn =
      conn
      # The length is not known up front and Plug sets the transfer encoding
      # itself, so any content-length the origin supplied has to go.
      |> put_proxied_headers(headers, drop: ["content-length"])
      |> send_chunked(status)

    stream_chunks(conn, channel_pid, subdomain, request_id)
  end

  defp stream_chunks(conn, channel_pid, subdomain, request_id) do
    receive do
      {:tunnel_response_chunk, ^request_id, data} ->
        with :ok <- throttle(subdomain, byte_size(data)),
             {:ok, conn} <- chunk(conn, data) do
          stream_chunks(conn, channel_pid, subdomain, request_id)
        else
          # Either the visitor hung up or the tunnel blew its bandwidth budget.
          # Headers are already on the wire, so there is no error page to show —
          # just stop pulling bytes the local server no longer needs to produce.
          _ ->
            cancel(channel_pid, request_id)
            halt(conn)
        end

      {:tunnel_response_end, ^request_id} ->
        halt(conn)
    after
      @stream_idle_timeout_ms ->
        Logger.warning("[Tunnel] stream #{request_id} stalled, closing")
        cancel(channel_pid, request_id)
        halt(conn)
    end
  end

  # Streams are throttled rather than cut off: exceeding the per-second budget
  # parks the request process until the window rolls, which backpressures the
  # tunnel instead of truncating a download half-way through.
  defp throttle(subdomain, bytes, attempts \\ 0)

  defp throttle(_subdomain, _bytes, attempts) when attempts >= @bandwidth_max_backoffs,
    do: :error

  defp throttle(subdomain, bytes, attempts) do
    if Runlocal.BandwidthLimiter.allow?(subdomain, bytes) do
      :ok
    else
      Process.sleep(@bandwidth_backoff_ms)
      throttle(subdomain, bytes, attempts + 1)
    end
  end

  defp cancel(channel_pid, request_id) do
    send(channel_pid, {:cancel_request, request_id})
  end

  defp request_meta(conn, body) do
    %{
      "method" => conn.method,
      "path" => conn.request_path,
      "query_string" => conn.query_string,
      "headers" => Enum.map(conn.req_headers, fn {k, v} -> [k, v] end),
      "body" => body
    }
  end

  defp put_proxied_headers(conn, headers, opts \\ []) do
    drop = @hop_by_hop_headers ++ Keyword.get(opts, :drop, [])

    headers
    |> Enum.reject(fn [key, _] -> String.downcase(key) in drop end)
    |> Enum.reduce(conn, fn [key, value], acc -> put_resp_header(acc, key, value) end)
  end

  defp bandwidth_exceeded(conn) do
    TunnelErrorHTML.send_error(conn, 429, "Bandwidth limit exceeded", """
    <p>This tunnel has exceeded its bandwidth limit. Please try again shortly.</p>
    """)
  end

  defp tunnel_not_found(conn, subdomain) do
    TunnelErrorHTML.send_error(conn, 404, "Tunnel not found", """
    <div class="hint">
      <p>The tunnel <code>#{subdomain}</code> is not connected. The developer may have stopped their session or the tunnel may have expired.</p>
    </div>
    <a href="https://runlocal.eu" class="btn">
      <svg viewBox="0 0 20 20" fill="currentColor" width="16" height="16"><path fill-rule="evenodd" d="M17 10a.75.75 0 0 1-.75.75H5.612l4.158 3.96a.75.75 0 1 1-1.04 1.08l-5.5-5.25a.75.75 0 0 1 0-1.08l5.5-5.25a.75.75 0 1 1 1.04 1.08L5.612 9.25H16.25A.75.75 0 0 1 17 10Z" clip-rule="evenodd" /></svg>
      Go to runlocal.eu
    </a>
    """)
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
