defmodule RunlocalWeb.Plugs.SubdomainRouter do
  def init(opts), do: opts

  def call(conn, _opts) do
    base_domain = Application.get_env(:runlocal, :base_domain, "localhost")

    case extract_subdomain(conn.host, base_domain) do
      nil ->
        conn

      subdomain ->
        RunlocalWeb.TunnelController.proxy(conn, subdomain)
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
