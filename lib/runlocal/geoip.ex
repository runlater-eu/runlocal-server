defmodule Runlocal.GeoIP do
  @moduledoc """
  IP → ASN / country lookups backing the network blocklists.

  Uses the free DB-IP Lite databases (https://db-ip.com, CC BY 4.0) by
  default, downloaded and periodically refreshed by `locus`. No account or
  license key is required; the download URLs can be overridden (e.g. to
  point at MaxMind GeoLite2) via `:geoip_asn_db_url` / `:geoip_country_db_url`.

  Loaders only start when the corresponding blocklist is configured, so
  installs that don't opt in never download anything. Lookups fail open:
  an IP that cannot be resolved is never blocked.
  """

  require Logger

  @asn_db :geoip_asn
  @country_db :geoip_country

  def maybe_start_loaders do
    unless static_entries() do
      if blocked_tunnel_asns() != [], do: start_loader(@asn_db, asn_db_url())
      if blocked_visitor_countries() != [], do: start_loader(@country_db, country_db_url())
    end

    :ok
  end

  @doc "Whether tunnel creation from this IP's network (ASN) is blocked."
  def blocked_asn?(ip) do
    case blocked_tunnel_asns() do
      [] -> false
      blocked -> asn(ip) in blocked
    end
  end

  @doc "Whether tunnel visitors from this IP's country are blocked."
  def blocked_country?(ip) do
    case blocked_visitor_countries() do
      [] -> false
      blocked -> country(ip) in blocked
    end
  end

  @doc "Autonomous system number for an IP, or nil when unknown."
  def asn(nil), do: nil

  def asn(ip) do
    if static = static_entries() do
      get_in(static, [ip, :asn])
    else
      case lookup(@asn_db, ip) do
        %{"autonomous_system_number" => number} -> number
        _ -> nil
      end
    end
  end

  @doc "ISO 3166-1 country code for an IP, or nil when unknown."
  def country(nil), do: nil

  def country(ip) do
    if static = static_entries() do
      get_in(static, [ip, :country])
    else
      case lookup(@country_db, ip) do
        %{"country" => %{"iso_code" => code}} -> code
        _ -> nil
      end
    end
  end

  defp lookup(db, ip) do
    case :locus.lookup(db, ip) do
      {:ok, entry} -> entry
      _ -> nil
    end
  end

  defp start_loader(db, url) do
    case :locus.start_loader(db, url) do
      :ok ->
        Logger.info("[GeoIP] #{db} loading from #{url}")

      {:error, reason} ->
        Logger.warning("[GeoIP] could not start #{db} loader: #{inspect(reason)}")
    end
  end

  defp asn_db_url do
    Application.get_env(:runlocal, :geoip_asn_db_url) || db_ip_url("asn")
  end

  defp country_db_url do
    Application.get_env(:runlocal, :geoip_country_db_url) || db_ip_url("country")
  end

  # DB-IP publishes a fresh Lite file each month, named by year and month.
  # The URL is pinned at boot; a restart (or deploy) picks up newer months.
  defp db_ip_url(edition) do
    %Date{year: year, month: month} = Date.utc_today()
    month = String.pad_leading(Integer.to_string(month), 2, "0")
    "https://download.db-ip.com/free/dbip-#{edition}-lite-#{year}-#{month}.mmdb.gz"
  end

  defp blocked_tunnel_asns, do: Application.get_env(:runlocal, :blocked_tunnel_asns, [])

  defp blocked_visitor_countries,
    do: Application.get_env(:runlocal, :blocked_visitor_countries, [])

  # Test-only escape hatch: a %{ip => %{asn: n, country: cc}} map that
  # replaces database lookups entirely (see config/test.exs).
  defp static_entries, do: Application.get_env(:runlocal, :geoip_static)
end
