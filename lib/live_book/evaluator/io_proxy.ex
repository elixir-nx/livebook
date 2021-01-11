defmodule LiveBook.Evaluator.IOProxy do
  @moduledoc false

  # An IO device process used by `Evaluator` as its `:stdio`.
  #
  # The process implements [The Erlang I/O Protocol](https://erlang.org/doc/apps/stdlib/io_protocol.html)
  # and can be thought of as a *virtual* IO device.
  #
  # Upon receiving an IO requests, the process sends a message
  # the `target` process specified during initialization.
  # Currently only output requests are supported.
  #
  # The implementation is based on the build-in `StringIO`,
  # so check it out for more reference.

  use GenServer

  alias LiveBook.Evaluator

  ## API

  @doc """
  Starts the IO device process.

  Make sure to use `configure/3` to actually proxy the requests.
  """
  @spec start_link() :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Sets IO proxy destination and the reference to be attached to all messages.

  For all supported requests a message is sent to `target`,
  so this device serves as a proxy. The given evaluation
  reference (`ref`) is also sent in all messages.

  The possible messages are:

    * `{:evaluator_stdout, ref, string}` - for output requests,
      where `ref` is the given evaluation reference and `string` is the output.
  """
  @spec configure(pid(), pid(), Evaluator.ref()) :: :ok
  def configure(pid, target, ref) do
    GenServer.cast(pid, {:configure, target, ref})
  end

  ## Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{encoding: :unicode, target: nil, ref: nil}}
  end

  @impl true
  def handle_cast({:configure, target, ref}, state) do
    {:noreply, %{state | target: target, ref: ref}}
  end

  @impl true
  def handle_info({:io_request, from, reply_as, req}, state) do
    {reply, state} = io_request(req, state)
    io_reply(from, reply_as, reply)
    {:noreply, state}
  end

  defp io_request({:put_chars, chars} = req, state) do
    put_chars(:latin1, chars, req, state)
  end

  defp io_request({:put_chars, mod, fun, args} = req, state) do
    put_chars(:latin1, apply(mod, fun, args), req, state)
  end

  defp io_request({:put_chars, encoding, chars} = req, state) do
    put_chars(encoding, chars, req, state)
  end

  defp io_request({:put_chars, encoding, mod, fun, args} = req, state) do
    put_chars(encoding, apply(mod, fun, args), req, state)
  end

  defp io_request({:get_chars, _prompt, count}, state) when count >= 0 do
    {{:error, :enotsup}, state}
  end

  defp io_request({:get_chars, _encoding, _prompt, count}, state) when count >= 0 do
    {{:error, :enotsup}, state}
  end

  defp io_request({:get_line, _prompt}, state) do
    {{:error, :enotsup}, state}
  end

  defp io_request({:get_line, _encoding, _prompt}, state) do
    {{:error, :enotsup}, state}
  end

  defp io_request({:get_until, _prompt, _mod, _fun, _args}, state) do
    {{:error, :enotsup}, state}
  end

  defp io_request({:get_until, _encoding, _prompt, _mod, _fun, _args}, state) do
    {{:error, :enotsup}, state}
  end

  defp io_request({:get_password, _encoding}, state) do
    {{:error, :enotsup}, state}
  end

  defp io_request({:setopts, [encoding: encoding]}, state) when encoding in [:latin1, :unicode] do
    {:ok, %{state | encoding: encoding}}
  end

  defp io_request({:setopts, _opts}, state) do
    {{:error, :enotsup}, state}
  end

  defp io_request(:getopts, state) do
    {[binary: true, encoding: state.encoding], state}
  end

  defp io_request({:get_geometry, :columns}, state) do
    {{:error, :enotsup}, state}
  end

  defp io_request({:get_geometry, :rows}, state) do
    {{:error, :enotsup}, state}
  end

  defp io_request({:requests, reqs}, state) do
    io_requests(reqs, {:ok, state})
  end

  defp io_request(_, state) do
    {{:error, :request}, state}
  end

  defp io_requests([req | rest], {:ok, state}) do
    io_requests(rest, io_request(req, state))
  end

  defp io_requests(_, result) do
    result
  end

  defp put_chars(encoding, chars, req, state) do
    case :unicode.characters_to_binary(chars, encoding, state.encoding) do
      string when is_binary(string) ->
        if state.target do
          send(state.target, {:evaluator_stdout, state.ref, string})
        end

        {:ok, state}

      {_, _, _} ->
        {{:error, req}, state}
    end
  rescue
    ArgumentError -> {{:error, req}, state}
  end

  defp io_reply(from, reply_as, reply) do
    send(from, {:io_reply, reply_as, reply})
  end
end
