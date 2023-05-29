defmodule Livebook.Runtime.Evaluator.Doctests do
  @moduledoc false

  @test_timeout 5_000
  @line_width 80
  @pad_size 3

  @doc """
  Runs doctests in the given modules.
  """
  @spec run(list(module())) :: :ok
  def run(modules)

  def run([]), do: :ok

  def run(modules) do
    case define_test_module(modules) do
      {:ok, test_module} ->
        if test_module.tests != [] do
          tests =
            test_module.tests
            |> Enum.sort_by(& &1.tags.doctest_line)
            |> Enum.map(fn test ->
              report_doctest_state(:evaluating, test)
              test = run_test(test)
              report_doctest_state(:success_or_failed, test)
              test
            end)

          formatted = format_results(tests)
          put_output({:text, formatted})
        end

        delete_test_module(test_module)

      {:error, kind, error} ->
        put_output({:error, colorize(:red, Exception.format(kind, error, [])), :other})
    end

    :ok
  end

  defp report_doctest_state(:evaluating, test) do
    result = %{
      doctest_line: test.tags.doctest_line,
      state: :evaluating
    }

    put_output({:doctest_result, result})
  end

  defp report_doctest_state(:success_or_failed, test) do
    result = %{
      doctest_line: test.tags.doctest_line,
      state: get_in(test, [Access.key(:state), Access.elem(0)]) || :success
    }

    put_output({:doctest_result, result})
  end

  defp define_test_module(modules) do
    id =
      modules
      |> Enum.sort()
      |> Enum.map_join("-", fn module ->
        module
        |> Atom.to_string()
        |> String.replace_prefix("Elixir.", "")
      end)
      |> :erlang.md5()
      |> Base.encode32(padding: false)

    name = Module.concat([LivebookDoctest, "TestModule#{id}"])

    try do
      defmodule name do
        use ExUnit.Case, register: false

        for module <- modules do
          doctest module
        end
      end

      {:ok, name.__ex_unit__()}
    catch
      kind, error -> {:error, kind, error}
    end
  end

  defp delete_test_module(%{name: module}) do
    :code.delete(module)
    :code.purge(module)
  end

  defp run_test(test) do
    runner_pid = self()

    {test_pid, test_ref} =
      spawn_monitor(fn ->
        test = exec_test(test)
        send(runner_pid, {:test_finished, self(), test})
      end)

    receive_test_reply(test, test_pid, test_ref)
  end

  defp receive_test_reply(test, test_pid, test_ref) do
    receive do
      {:test_finished, ^test_pid, test} ->
        Process.demonitor(test_ref, [:flush])
        test

      {:DOWN, ^test_ref, :process, ^test_pid, error} ->
        %{test | state: failed({:EXIT, test_pid}, error, [])}
    after
      @test_timeout ->
        case Process.info(test_pid, :current_stacktrace) do
          {:current_stacktrace, stacktrace} ->
            Process.exit(test_pid, :kill)

            receive do
              {:DOWN, ^test_ref, :process, ^test_pid, _} -> :ok
            end

            exception = RuntimeError.exception("doctest timed out after #{@test_timeout} ms")
            %{test | state: failed(:error, exception, prune_stacktrace(stacktrace))}

          nil ->
            receive_test_reply(test, test_pid, test_ref)
        end
    end
  end

  defp exec_test(%ExUnit.Test{module: module, name: name} = test) do
    apply(module, name, [:none])
    test
  catch
    kind, error ->
      %{test | state: failed(kind, error, prune_stacktrace(__STACKTRACE__))}
  end

  defp failed(kind, reason, stack) do
    {:failed, {kind, Exception.normalize(kind, reason, stack), stack}}
  end

  # As soon as we see our runner module, we ignore the rest of the stacktrace
  def prune_stacktrace([{__MODULE__, _, _, _} | _]), do: []
  def prune_stacktrace([h | t]), do: [h | prune_stacktrace(t)]
  def prune_stacktrace([]), do: []

  # Formatting

  defp format_results(tests) do
    filed_tests = Enum.reject(tests, &(&1.state == nil))

    test_count = length(tests)
    failure_count = length(filed_tests)

    doctests_pl = pluralize(test_count, "doctest", "doctests")
    failures_pl = pluralize(failure_count, "failure", "failures")

    headline =
      colorize(
        if(failure_count == 0, do: :green, else: :red),
        "#{test_count} #{doctests_pl}, #{failure_count} #{failures_pl}"
      )

    failures =
      for {test, idx} <- Enum.with_index(filed_tests) do
        {:failed, failure} = test.state

        name =
          test.name
          |> Atom.to_string()
          |> String.replace(~r/ \(\d+\)$/, "")

        line = test.tags.doctest_line

        [
          "\n\n",
          "#{idx + 1}) #{name} (line #{line})\n",
          format_failure(failure, test)
        ]
      end

    IO.iodata_to_binary([headline, failures])
  end

  defp format_failure({:error, %ExUnit.AssertionError{} = reason, _stack}, _test) do
    diff =
      ExUnit.Formatter.format_assertion_diff(
        reason,
        @pad_size + 2,
        @line_width,
        &diff_formatter/2
      )

    expected = diff[:right]
    got = diff[:left]

    {expected_label, got_label, source} =
      if reason.doctest == ExUnit.AssertionError.no_value() do
        {"right", "left", nil}
      else
        {"expected", "got", String.trim(reason.doctest)}
      end

    message_io =
      if_io(reason.message != "Doctest failed", fn ->
        message =
          reason.message
          |> String.replace_prefix("Doctest failed: ", "")
          |> pad(@pad_size)

        [colorize(:red, message), "\n"]
      end)

    source_io =
      if_io(source, fn ->
        [
          String.duplicate(" ", @pad_size),
          format_label("doctest"),
          "\n",
          pad(source, @pad_size + 2)
        ]
      end)

    expected_io =
      if_io(expected, fn ->
        [
          "\n",
          String.duplicate(" ", @pad_size),
          format_label(expected_label),
          "\n",
          String.duplicate(" ", @pad_size + 2),
          expected
        ]
      end)

    got_io =
      if_io(got, fn ->
        [
          "\n",
          String.duplicate(" ", @pad_size),
          format_label(got_label),
          "\n",
          String.duplicate(" ", @pad_size + 2),
          got
        ]
      end)

    message_io ++ source_io ++ expected_io ++ got_io
  end

  defp format_failure({kind, reason, stacktrace}, test) do
    {blamed, stacktrace} = Exception.blame(kind, reason, stacktrace)

    banner =
      case blamed do
        %FunctionClauseError{} ->
          banner = Exception.format_banner(kind, reason, stacktrace)
          inspect_opts = Livebook.Runtime.Evaluator.DefaultFormatter.inspect_opts()
          blame = FunctionClauseError.blame(blamed, &inspect(&1, inspect_opts), &blame_match/1)
          colorize(:red, banner) <> blame

        _ ->
          banner = Exception.format_banner(kind, blamed, stacktrace)
          colorize(:red, banner)
      end

    if stacktrace == [] do
      pad(banner, @pad_size)
    else
      [
        pad(banner, @pad_size),
        "\n",
        String.duplicate(" ", @pad_size),
        format_label("stacktrace"),
        format_stacktrace(stacktrace, test.module, test.name)
      ]
    end
  end

  defp if_io(value, fun), do: if(value, do: fun.(), else: [])

  defp format_stacktrace(stacktrace, test_case, test) do
    for entry <- stacktrace do
      message = format_stacktrace_entry(entry, test_case, test)
      "\n" <> pad(message, @pad_size + 2)
    end
  end

  defp format_stacktrace_entry({test_case, test, _, location}, test_case, test) do
    "doctest at line #{location[:line]}"
  end

  defp format_stacktrace_entry(entry, _test_case, _test) do
    Exception.format_stacktrace_entry(entry)
  end

  defp format_label(label), do: colorize(:cyan, "#{label}:")

  defp pad(string, pad_size) do
    padding = String.duplicate(" ", pad_size)
    padding <> String.replace(string, "\n", "\n" <> padding)
  end

  defp blame_match(%{match?: true, node: node}), do: Macro.to_string(node)

  defp blame_match(%{match?: false, node: node}) do
    colorize(:red, Macro.to_string(node))
  end

  defp diff_formatter(:diff_enabled?, _doc), do: true

  defp diff_formatter(key, doc) do
    colors = [
      diff_delete: :red,
      diff_delete_whitespace: IO.ANSI.color_background(4, 0, 0),
      diff_insert: :green,
      diff_insert_whitespace: IO.ANSI.color_background(0, 3, 0)
    ]

    Inspect.Algebra.color(doc, key, %Inspect.Opts{syntax_colors: colors})
  end

  defp colorize(color, string) do
    [color, string, :reset]
    |> IO.ANSI.format_fragment(true)
    |> IO.iodata_to_binary()
  end

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_, _singular, plural), do: plural

  defp put_output(output) do
    gl = Process.group_leader()
    ref = make_ref()

    send(gl, {:io_request, self(), ref, {:livebook_put_output, output}})

    receive do
      {:io_reply, ^ref, reply} -> {:ok, reply}
    end
  end
end
