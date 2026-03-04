defmodule RunlocalWeb.WsProxy do
  @behaviour WebSock

  @impl true
  def init(state) do
    Process.monitor(state.channel_pid)
    send(state.channel_pid, {:ws_upgrade, state.ws_id, self(), state.request_data})
    {:ok, state}
  end

  @impl true
  def handle_in({data, opcode_opts}, state) do
    opcode = if is_list(opcode_opts), do: Keyword.get(opcode_opts, :opcode, :text), else: :text
    send(state.channel_pid, {:ws_client_frame, state.ws_id, data, opcode})
    {:ok, state}
  end

  @impl true
  def handle_info({:ws_frame, data, opcode}, state) do
    {:push, [{opcode, data}], state}
  end

  def handle_info({:ws_close}, state) do
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, _, :process, pid, _}, %{channel_pid: pid} = state) do
    {:stop, :normal, state}
  end

  def handle_info(_msg, state) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    send(state.channel_pid, {:ws_closed, state.ws_id})
    :ok
  end
end
