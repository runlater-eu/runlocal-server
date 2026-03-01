defmodule RunlocalWeb.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import RunlocalWeb.ChannelCase

      @endpoint RunlocalWeb.Endpoint
    end
  end

  setup _tags do
    :ok
  end
end
