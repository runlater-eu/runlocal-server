defmodule RunlocalWeb.TunnelErrorHTML do
  @moduledoc """
  Renders styled HTML error pages for tunnel proxy errors.
  """

  import Plug.Conn

  @doc """
  Sends a styled tunnel error page as the response.
  """
  def send_error(conn, status, title, message) do
    html = render(status, title, message)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, html)
    |> halt()
  end

  defp render(status, title, message) do
    status_color = if status >= 500, do: "text-red-400/20", else: "text-amber-400/20"

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>#{title} — runlocal</title>
      <link rel="icon" type="image/svg+xml" href="https://runlocal.eu/favicon.svg" />
      <link rel="preconnect" href="https://fonts.googleapis.com" />
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
      <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet" />
      <style>
        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
        body {
          font-family: 'Inter', system-ui, -apple-system, sans-serif;
          -webkit-font-smoothing: antialiased;
          min-height: 100vh;
          display: flex;
          flex-direction: column;
          background: linear-gradient(to bottom right, #0f172a, #1e293b, #064e3b);
        }
        .nav { max-width: 56rem; margin: 0 auto; padding: 1.5rem; display: flex; align-items: center; width: 100%; }
        .nav a { display: flex; align-items: center; gap: 0.625rem; font-size: 1.25rem; font-weight: 600; color: white; text-decoration: none; }
        .center { flex: 1; display: flex; align-items: center; justify-content: center; padding: 1.5rem; }
        .card { text-align: center; max-width: 28rem; }
        .status { font-size: 6rem; font-weight: 700; #{status_color |> css_color()}; margin-bottom: 1rem; line-height: 1; }
        h1 { font-size: 1.5rem; font-weight: 700; color: white; margin-bottom: 0.75rem; }
        p { color: #94a3b8; margin-bottom: 2rem; line-height: 1.6; }
        code { background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.12); border-radius: 0.375rem; padding: 0.125rem 0.5rem; color: #6ee7b7; font-size: 0.875rem; }
        .btn {
          display: inline-flex; align-items: center; gap: 0.5rem;
          background: rgba(255,255,255,0.08); border: 1px solid rgba(255,255,255,0.12);
          border-radius: 0.5rem; padding: 0.625rem 1.25rem;
          font-size: 0.875rem; font-weight: 500; color: #6ee7b7;
          text-decoration: none; transition: all 0.2s;
        }
        .btn:hover { background: rgba(255,255,255,0.14); border-color: rgba(255,255,255,0.2); }
        .hint { background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.08); border-radius: 0.75rem; padding: 1rem 1.25rem; margin-bottom: 2rem; text-align: left; }
        .hint p { color: #94a3b8; font-size: 0.875rem; margin-bottom: 0; }
      </style>
    </head>
    <body>
      <div class="nav">
        <a href="https://runlocal.eu">
          <svg viewBox="0 0 28 28" fill="none" width="28" height="28">
            <circle cx="14" cy="14" r="12" stroke="#34d399" stroke-width="2" stroke-opacity="0.3" fill="none" />
            <circle cx="14" cy="14" r="8" stroke="#34d399" stroke-width="2" stroke-opacity="0.5" fill="none" />
            <circle cx="14" cy="14" r="4" stroke="#34d399" stroke-width="2" stroke-opacity="0.8" fill="none" />
            <circle cx="14" cy="14" r="2" fill="#34d399" />
          </svg>
          runlocal
        </a>
      </div>
      <div class="center">
        <div class="card">
          <div class="status">#{status}</div>
          <h1>#{title}</h1>
          #{message}
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp css_color("text-red-400/20"), do: "color: rgba(248, 113, 113, 0.2)"
  defp css_color("text-amber-400/20"), do: "color: rgba(251, 191, 36, 0.2)"
end
