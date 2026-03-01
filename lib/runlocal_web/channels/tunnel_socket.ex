defmodule RunlocalWeb.TunnelSocket do
  use Phoenix.Socket

  channel "tunnel:*", RunlocalWeb.TunnelChannel

  @impl true
  def connect(_params, socket, connect_info) do
    client_ip = extract_client_ip(connect_info)

    if Runlocal.IpBlocklist.blocked?(client_ip) do
      :error
    else
      {:ok, assign(socket, :client_ip, client_ip)}
    end
  end

  @impl true
  def id(_socket), do: nil

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
