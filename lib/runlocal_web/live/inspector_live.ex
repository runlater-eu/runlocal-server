defmodule RunlocalWeb.InspectorLive do
  use RunlocalWeb, :live_view

  @max_entries 100

  @impl true
  def mount(%{"subdomain" => subdomain, "token" => token}, _session, socket) do
    socket =
      socket
      |> assign(:subdomain, subdomain)
      |> assign(:token, token)
      |> assign(:entries, [])
      |> assign(:selected_id, nil)
      |> assign(:tunnel_active, false)
      |> assign(:authorized, false)
      |> assign(:page_title, "Inspector — #{subdomain}")

    if connected?(socket) do
      tunnel = Runlocal.Registry.lookup(subdomain)

      cond do
        tunnel == nil ->
          {:ok, socket}

        tunnel.inspect_token != token ->
          {:ok, assign(socket, :authorized, false)}

        true ->
          Phoenix.PubSub.subscribe(Runlocal.PubSub, "inspect:#{subdomain}")
          Process.monitor(tunnel.channel_pid)
          {:ok, socket |> assign(:tunnel_active, true) |> assign(:authorized, true)}
      end
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_info({:new_request, entry}, socket) do
    entries =
      [entry | socket.assigns.entries]
      |> Enum.take(@max_entries)

    selected_id =
      if socket.assigns.selected_id == nil do
        entry.id
      else
        socket.assigns.selected_id
      end

    {:noreply, assign(socket, entries: entries, selected_id: selected_id)}
  end

  def handle_info({:request_updated, update}, socket) do
    entries =
      Enum.map(socket.assigns.entries, fn entry ->
        if entry.id == update.id do
          Map.merge(entry, update)
        else
          entry
        end
      end)

    {:noreply, assign(socket, :entries, entries)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, assign(socket, :tunnel_active, false)}
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_id, id)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, entries: [], selected_id: nil)}
  end

  defp selected_entry(_entries, nil), do: nil

  defp selected_entry(entries, id) do
    Enum.find(entries, &(&1.id == id))
  end

  defp request_count(entries), do: length(entries)

  defp format_time(nil), do: ""

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp method_color("GET"), do: "text-emerald-400"
  defp method_color("POST"), do: "text-blue-400"
  defp method_color("PUT"), do: "text-yellow-400"
  defp method_color("PATCH"), do: "text-orange-400"
  defp method_color("DELETE"), do: "text-red-400"
  defp method_color(_), do: "text-slate-400"

  defp status_color(status) when is_integer(status) and status >= 200 and status < 300, do: "text-emerald-400"
  defp status_color(status) when is_integer(status) and status >= 300 and status < 400, do: "text-blue-400"
  defp status_color(status) when is_integer(status) and status >= 400 and status < 500, do: "text-yellow-400"
  defp status_color(status) when is_integer(status) and status >= 500, do: "text-red-400"
  defp status_color(_), do: "text-slate-400"

  defp format_headers(nil), do: ""

  defp format_headers(headers) when is_list(headers) do
    Enum.map_join(headers, "\n", fn
      [k, v] -> "#{k}: #{v}"
      {k, v} -> "#{k}: #{v}"
    end)
  end

  defp format_body(nil), do: ""
  defp format_body(""), do: ""

  defp format_body(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> body
    end
  end

  defp truncated?(body_size, _body) when is_integer(body_size) and body_size > 10_240 do
    true
  end

  defp truncated?(_, _), do: false

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :selected, selected_entry(assigns.entries, assigns.selected_id))

    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-emerald-900">
      <!-- Header -->
      <div class="border-b border-white/10 px-6 py-4">
        <div class="max-w-7xl mx-auto flex items-center justify-between">
          <div class="flex items-center gap-4">
            <a href="/" class="flex items-center gap-2 text-white font-semibold no-underline">
              <svg viewBox="0 0 28 28" fill="none" class="w-6 h-6">
                <circle cx="14" cy="14" r="12" stroke="#34d399" stroke-width="2" stroke-opacity="0.3" fill="none" />
                <circle cx="14" cy="14" r="8" stroke="#34d399" stroke-width="2" stroke-opacity="0.5" fill="none" />
                <circle cx="14" cy="14" r="4" stroke="#34d399" stroke-width="2" stroke-opacity="0.8" fill="none" />
                <circle cx="14" cy="14" r="2" fill="#34d399" />
              </svg>
              runlocal
            </a>
            <span class="text-slate-500">/</span>
            <span class="text-slate-300 font-mono text-sm">{@subdomain}</span>
          </div>

          <div class="flex items-center gap-4">
            <span class="text-slate-400 text-sm">{request_count(@entries)} requests</span>
            <div class="flex items-center gap-2">
              <span class={[
                "w-2 h-2 rounded-full",
                if(@tunnel_active, do: "bg-emerald-400 animate-pulse", else: "bg-red-400")
              ]} />
              <span class="text-sm text-slate-400">
                {if @tunnel_active, do: "Connected", else: "Disconnected"}
              </span>
            </div>
            <button
              phx-click="clear"
              class="text-xs text-slate-400 hover:text-white transition-colors glass-button rounded px-3 py-1.5"
            >
              Clear
            </button>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div class="max-w-7xl mx-auto flex" style="height: calc(100vh - 73px);">
        <!-- Left Panel: Request Log -->
        <div class="w-1/3 border-r border-white/10 overflow-y-auto">
          <%= if !@tunnel_active and !@authorized and Enum.empty?(@entries) do %>
            <div class="flex items-center justify-center h-full">
              <div class="text-center px-6">
                <div class="w-12 h-12 rounded-full bg-red-500/20 flex items-center justify-center mx-auto mb-4">
                  <span class="w-3 h-3 rounded-full bg-red-400"></span>
                </div>
                <p class="text-slate-300 font-medium mb-2">Invalid or expired link</p>
                <p class="text-slate-500 text-sm">
                  This inspector URL is not valid. Start a tunnel with
                  <code class="text-emerald-400">npx runlocal &lt;port&gt;</code>
                  and use the link from the CLI output.
                </p>
              </div>
            </div>
          <% else %>
            <%= if Enum.empty?(@entries) do %>
              <div class="flex items-center justify-center h-full">
                <div class="text-center px-6">
                  <div class="w-12 h-12 rounded-full bg-emerald-500/20 flex items-center justify-center mx-auto mb-4">
                    <span class="w-3 h-3 rounded-full bg-emerald-400 animate-pulse"></span>
                  </div>
                  <p class="text-slate-300 font-medium mb-2">Waiting for requests...</p>
                  <p class="text-slate-500 text-sm">
                    Send a request to <code class="text-emerald-400">{@subdomain}.runlocal.eu</code>
                  </p>
                </div>
              </div>
            <% else %>
              <div class="divide-y divide-white/5">
                <div
                  :for={entry <- @entries}
                  phx-click="select"
                  phx-value-id={entry.id}
                  class={[
                    "px-4 py-3 cursor-pointer transition-colors",
                    if(entry.id == @selected_id, do: "bg-white/10", else: "hover:bg-white/5")
                  ]}
                >
                  <div class="flex items-center gap-3">
                    <span class={["font-mono text-xs font-semibold w-14", method_color(entry.method)]}>
                      {entry.method}
                    </span>
                    <span class="text-slate-300 text-sm font-mono truncate flex-1">{entry.path}</span>
                    <%= if Map.has_key?(entry, :status) do %>
                      <span class={["text-xs font-mono font-semibold", status_color(entry.status)]}>
                        {entry.status}
                      </span>
                    <% else %>
                      <span class="w-3 h-3 rounded-full border-2 border-slate-500 border-t-emerald-400 animate-spin"></span>
                    <% end %>
                  </div>
                  <div class="flex items-center gap-3 mt-1">
                    <span class="text-slate-500 text-xs">{format_time(entry.timestamp)}</span>
                    <%= if duration = Map.get(entry, :duration_ms) do %>
                      <span class="text-slate-500 text-xs">{duration}ms</span>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>

        <!-- Right Panel: Detail -->
        <div class="flex-1 overflow-y-auto">
          <%= if @selected do %>
            <div class="p-6 space-y-6">
              <!-- Request Section -->
              <div>
                <h3 class="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-3">Request</h3>
                <div class="glass-card rounded-lg p-4 space-y-3">
                  <div class="flex items-center gap-3">
                    <span class={["font-mono text-sm font-semibold", method_color(@selected.method)]}>
                      {@selected.method}
                    </span>
                    <span class="text-slate-300 text-sm font-mono">
                      {@selected.path}<%= if @selected.query_string != "", do: "?#{@selected.query_string}" %>
                    </span>
                  </div>

                  <%= if @selected.request_headers && @selected.request_headers != [] do %>
                    <div>
                      <p class="text-xs text-slate-500 uppercase tracking-wider mb-1">Headers</p>
                      <pre class="text-xs text-slate-300 font-mono whitespace-pre-wrap bg-black/20 rounded p-3 overflow-x-auto">{format_headers(@selected.request_headers)}</pre>
                    </div>
                  <% end %>

                  <%= if @selected.request_body && @selected.request_body != "" do %>
                    <div>
                      <div class="flex items-center gap-2 mb-1">
                        <p class="text-xs text-slate-500 uppercase tracking-wider">Body</p>
                        <%= if truncated?(@selected.request_body_size, @selected.request_body) do %>
                          <span class="text-xs text-yellow-400">
                            (truncated, {@selected.request_body_size} bytes total)
                          </span>
                        <% end %>
                      </div>
                      <pre class="text-xs text-slate-300 font-mono whitespace-pre-wrap bg-black/20 rounded p-3 overflow-x-auto">{format_body(@selected.request_body)}</pre>
                    </div>
                  <% end %>
                </div>
              </div>

              <!-- Response Section -->
              <div>
                <h3 class="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-3">Response</h3>
                <%= if Map.has_key?(@selected, :status) do %>
                  <div class="glass-card rounded-lg p-4 space-y-3">
                    <div class="flex items-center gap-4">
                      <span class={["font-mono text-sm font-semibold", status_color(@selected.status)]}>
                        {@selected.status}
                      </span>
                      <%= if duration = Map.get(@selected, :duration_ms) do %>
                        <span class="text-slate-400 text-sm">{duration}ms</span>
                      <% end %>
                    </div>

                    <%= if @selected[:response_headers] && @selected[:response_headers] != [] do %>
                      <div>
                        <p class="text-xs text-slate-500 uppercase tracking-wider mb-1">Headers</p>
                        <pre class="text-xs text-slate-300 font-mono whitespace-pre-wrap bg-black/20 rounded p-3 overflow-x-auto">{format_headers(@selected[:response_headers])}</pre>
                      </div>
                    <% end %>

                    <%= if @selected[:response_body] && @selected[:response_body] != "" do %>
                      <div>
                        <div class="flex items-center gap-2 mb-1">
                          <p class="text-xs text-slate-500 uppercase tracking-wider">Body</p>
                          <%= if truncated?(@selected[:response_body_size], @selected[:response_body]) do %>
                            <span class="text-xs text-yellow-400">
                              (truncated, {@selected[:response_body_size]} bytes total)
                            </span>
                          <% end %>
                        </div>
                        <pre class="text-xs text-slate-300 font-mono whitespace-pre-wrap bg-black/20 rounded p-3 overflow-x-auto">{format_body(@selected[:response_body])}</pre>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <div class="glass-card rounded-lg p-4">
                    <div class="flex items-center gap-3 text-slate-400">
                      <span class="w-4 h-4 rounded-full border-2 border-slate-500 border-t-emerald-400 animate-spin"></span>
                      <span class="text-sm">Waiting for response...</span>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% else %>
            <div class="flex items-center justify-center h-full">
              <p class="text-slate-500 text-sm">Select a request to view details</p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
