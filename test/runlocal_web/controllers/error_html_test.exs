defmodule RunlocalWeb.ErrorHTMLTest do
  use RunlocalWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    result = render_to_string(RunlocalWeb.ErrorHTML, "404", "html", [])
    assert result =~ "404"
    assert result =~ "Page not found"
  end

  test "renders 500.html" do
    result = render_to_string(RunlocalWeb.ErrorHTML, "500", "html", [])
    assert result =~ "500"
    assert result =~ "Something went wrong"
  end
end
