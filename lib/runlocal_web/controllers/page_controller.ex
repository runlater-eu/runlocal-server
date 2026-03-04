defmodule RunlocalWeb.PageController do
  use RunlocalWeb, :controller

  def home(conn, _params) do
    if Application.get_env(:runlocal, :landing_page) do
      conn
      |> assign(:meta_description, "Expose localhost to the internet with one command. No signup, no config, no tracking. European-owned and GDPR-compliant.")
      |> render(:home)
    else
      tunnel_count = :ets.info(:tunnel_registry, :size)

      conn
      |> assign(:tunnel_count, tunnel_count)
      |> render(:status)
    end
  end

  def getting_started(conn, _params) do
    if Application.get_env(:runlocal, :landing_page) do
      conn
      |> assign(:page_title, "Getting Started")
      |> assign(:meta_description, "Learn how to expose your local dev server to the internet with npx runlocal. Webhook testing, request inspection, stable subdomains, and more.")
      |> render(:getting_started)
    else
      redirect(conn, to: ~p"/")
    end
  end

  def privacy(conn, _params) do
    if Application.get_env(:runlocal, :landing_page) do
      conn
      |> assign(:page_title, "Privacy Policy")
      |> render(:privacy)
    else
      redirect(conn, to: ~p"/")
    end
  end

  def dpa(conn, _params) do
    if Application.get_env(:runlocal, :landing_page) do
      conn
      |> assign(:page_title, "Data Processing Agreement")
      |> render(:dpa)
    else
      redirect(conn, to: ~p"/")
    end
  end

  def terms(conn, _params) do
    if Application.get_env(:runlocal, :landing_page) do
      conn
      |> assign(:page_title, "Terms of Use")
      |> render(:terms)
    else
      redirect(conn, to: ~p"/")
    end
  end
end
