defmodule RunlocalWeb.TunnelSocketTest do
  use ExUnit.Case, async: true

  # Phoenix logs socket connect params ("CONNECTED TO RunlocalWeb.TunnelSocket
  # ... Parameters:") through filter_values/1, and clients send their runlater
  # api_key as one of those params.
  test "connect params are filtered of credentials before logging" do
    params = %{
      "api_key" => "rl_live_secret",
      "token" => "t",
      "client_secret" => "s",
      "subdomain" => "acme"
    }

    assert Phoenix.Logger.filter_values(params) == %{
             "api_key" => "[FILTERED]",
             "token" => "[FILTERED]",
             "client_secret" => "[FILTERED]",
             "subdomain" => "acme"
           }
  end
end
