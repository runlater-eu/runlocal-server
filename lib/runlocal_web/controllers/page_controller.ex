defmodule RunlocalWeb.PageController do
  use RunlocalWeb, :controller

  def home(conn, _params) do
    conn
    |> assign(:meta_description, "Expose localhost to the internet with one command. No signup, no config, no tracking. European-owned and GDPR-compliant.")
    |> render(:home)
  end

  def getting_started(conn, _params) do
    conn
    |> assign(:page_title, "Getting Started")
    |> assign(:meta_description, "Learn how to expose your local dev server to the internet with npx runlocal. Webhook testing, request inspection, stable subdomains, and more.")
    |> render(:getting_started)
  end

  def privacy(conn, _params) do
    conn
    |> assign(:page_title, "Privacy Policy")
    |> render(:privacy)
  end

  def dpa(conn, _params) do
    conn
    |> assign(:page_title, "Data Processing Agreement")
    |> render(:dpa)
  end
end
