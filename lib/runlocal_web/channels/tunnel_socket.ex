defmodule RunlocalWeb.TunnelSocket do
  use Phoenix.Socket

  channel "tunnel:*", RunlocalWeb.TunnelChannel

  @impl true
  def connect(_params, socket, connect_info) do
    client_ip = extract_client_ip(connect_info)

    if Runlocal.IpBlocklist.blocked?(client_ip) do
      :error
    else
      query_params = extract_query_params(connect_info)

      socket =
        socket
        |> assign(:client_ip, client_ip)
        |> assign(:api_key, query_params["api_key"])

      {:ok, socket}
    end
  end

  @impl true
  def id(_socket), do: nil

  defp extract_query_params(connect_info) do
    case connect_info[:uri] do
      %URI{query: query} when is_binary(query) -> URI.decode_query(query)
      _ -> %{}
    end
  end

  defp extract_client_ip(connect_info) do
    forwarded_for =
      connect_info
      |> Map.get(:x_headers, [])
      |> Enum.find_value(fn
        {"x-forwarded-for", value} -> value
        _ -> nil
      end)

    case forwarded_for do
      nil ->
        case get_in(connect_info, [:peer_data, :address]) do
          nil -> nil
          address -> :inet.ntoa(address) |> to_string()
        end

      value ->
        value |> String.split(",") |> List.first() |> String.trim()
    end
  end
end
