defmodule LiveBook.Session.DataTest do
  use ExUnit.Case, async: true

  alias LiveBook.Session.Data

  describe "apply_operation/2 given :insert_section" do
    test "adds new section to notebook and session info" do
      data = Data.new()

      operation = {:insert_section, 0, "s1"}

      assert {:ok,
              %{
                notebook: %{
                  sections: [%{id: "s1"}]
                },
                section_infos: %{"s1" => _}
              }} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :insert_cell" do
    test "returns an error given invalid section id" do
      data = Data.new()
      operation = {:insert_cell, "nonexistent", 0, :elixir, "c1"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "insert_cell adds new cell to notebook and session info" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"}
        ])

      operation = {:insert_cell, "s1", 0, :elixir, "c1"}

      assert {:ok,
              %{
                notebook: %{
                  sections: [
                    %{cells: [%{id: "c1"}]}
                  ]
                },
                cell_infos: %{"c1" => _}
              }} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :delete_section" do
    test "returns an error given invalid section id" do
      data = Data.new()
      operation = {:delete_section, "nonexistent"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "removes the section from notebook and session info, adds to deleted sections" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"}
        ])

      operation = {:delete_section, "s1"}
      empty_map = %{}

      assert {:ok,
              %{
                notebook: %{
                  sections: []
                },
                section_infos: ^empty_map,
                deleted_sections: [%{id: "s1"}]
              }} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :delete_cell" do
    test "returns an error given invalid cell id" do
      data = Data.new()
      operation = {:delete_cell, "nonexistent"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "if the cell is evaluating, cencels section evaluation" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :elixir, "c1"},
          {:insert_cell, "s1", 1, :elixir, "c2"},
          {:queue_cell_evaluation, "c1"},
          {:queue_cell_evaluation, "c2"}
        ])

      operation = {:delete_cell, "c1"}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{status: :fresh}},
                section_infos: %{"s1" => %{evaluating_cell_id: nil, evaluation_queue: []}}
              }} = Data.apply_operation(data, operation)
    end

    test "removes the cell from notebook and session info, adds to deleted cells" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :elixir, "c1"}
        ])

      operation = {:delete_cell, "c1"}
      empty_map = %{}

      assert {:ok,
              %{
                notebook: %{
                  sections: [%{cells: []}]
                },
                cell_infos: ^empty_map,
                deleted_cells: [%{id: "c1"}]
              }} = Data.apply_operation(data, operation)
    end

    test "unqueues the cell if it's queued for evaluation" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :elixir, "c1"},
          {:insert_cell, "s1", 1, :elixir, "c2"},
          {:queue_cell_evaluation, "c1"},
          {:queue_cell_evaluation, "c2"}
        ])

      operation = {:delete_cell, "c2"}

      assert {:ok,
              %{
                section_infos: %{"s1" => %{evaluation_queue: []}}
              }} = Data.apply_operation(data, operation)
    end

    test "marks evaluated child cells as stale" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :elixir, "c1"},
          {:insert_cell, "s1", 1, :elixir, "c2"},
          # Evaluate both cells
          {:queue_cell_evaluation, "c1"},
          {:add_cell_evaluation_response, "c1", {:ok, [1, 2, 3]}},
          {:queue_cell_evaluation, "c2"},
          {:add_cell_evaluation_response, "c2", {:ok, [1, 2, 3]}}
        ])

      operation = {:delete_cell, "c1"}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{status: :stale}}
              }} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :queue_cell_evaluation" do
    test "returns an error given invalid cell id" do
      data = Data.new()
      operation = {:queue_cell_evaluation, "nonexistent"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error given non-elixir cell" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :markdown, "c1"}
        ])

      operation = {:queue_cell_evaluation, "c1"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error for an evaluating cell" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :elixir, "c1"},
          {:queue_cell_evaluation, "c1"}
        ])

      operation = {:queue_cell_evaluation, "c1"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "marks the cell as evaluating if the corresponding section is idle" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :elixir, "c1"}
        ])

      operation = {:queue_cell_evaluation, "c1"}

      assert {:ok,
              %{
                cell_infos: %{"c1" => %{status: :evaluating}},
                section_infos: %{"s1" => %{evaluating_cell_id: "c1", evaluation_queue: []}}
              }} = Data.apply_operation(data, operation)
    end

    test "marks the cell as queued if the corresponding section is already evaluating" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :elixir, "c1"},
          {:insert_cell, "s1", 1, :elixir, "c2"},
          {:queue_cell_evaluation, "c1"}
        ])

      operation = {:queue_cell_evaluation, "c2"}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{status: :queued}},
                section_infos: %{"s1" => %{evaluating_cell_id: "c1", evaluation_queue: ["c2"]}}
              }} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :add_cell_evaluation_stdout" do
    test "update the cell output" do
      # TODO assert against output being updated once we do so
    end
  end

  describe "apply_operation/2 given :add_cell_evaluation_response" do
    test "update the cell output" do
      # TODO assert against output being updated once we do so
    end

    test "marks the cell as evaluated" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :elixir, "c1"},
          {:insert_cell, "s1", 1, :elixir, "c2"},
          {:queue_cell_evaluation, "c1"}
        ])

      operation = {:add_cell_evaluation_response, "c1", {:ok, [1, 2, 3]}}

      assert {:ok,
              %{
                cell_infos: %{"c1" => %{status: :evaluated}},
                section_infos: %{"s1" => %{evaluating_cell_id: nil, evaluation_queue: []}}
              }} = Data.apply_operation(data, operation)
    end

    test "marks next queued cell in this section as evaluating if there is one" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :elixir, "c1"},
          {:insert_cell, "s1", 1, :elixir, "c2"},
          {:queue_cell_evaluation, "c1"},
          {:queue_cell_evaluation, "c2"}
        ])

      operation = {:add_cell_evaluation_response, "c1", {:ok, [1, 2, 3]}}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{status: :evaluating}},
                section_infos: %{"s1" => %{evaluating_cell_id: "c2", evaluation_queue: []}}
              }} = Data.apply_operation(data, operation)
    end

    test "if parent cells are not executed, marks them for evaluation first" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :elixir, "c1"},
          {:insert_cell, "s1", 1, :elixir, "c2"}
        ])

      operation = {:queue_cell_evaluation, "c2"}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{status: :evaluating},
                  "c2" => %{status: :queued}
                },
                section_infos: %{"s1" => %{evaluating_cell_id: "c1", evaluation_queue: ["c2"]}}
              }} = Data.apply_operation(data, operation)
    end

    test "marks evaluated child cells as stale" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :elixir, "c1"},
          {:insert_cell, "s1", 1, :elixir, "c2"},
          # Evaluate both cells
          {:queue_cell_evaluation, "c1"},
          {:add_cell_evaluation_response, "c1", {:ok, [1, 2, 3]}},
          {:queue_cell_evaluation, "c2"},
          {:add_cell_evaluation_response, "c2", {:ok, [1, 2, 3]}},
          # Queue the first cell again
          {:queue_cell_evaluation, "c1"}
        ])

      operation = {:add_cell_evaluation_response, "c1", {:ok, [1, 2, 3]}}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{status: :stale}}
              }} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :cancel_cell_evaluation" do
    test "returns an error given invalid cell id" do
      data = Data.new()
      operation = {:cancel_cell_evaluation, "nonexistent"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error for an evaluated cell" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :elixir, "c1"},
          {:queue_cell_evaluation, "c1"},
          {:add_cell_evaluation_response, "c1", {:ok, [1, 2, 3]}}
        ])

      operation = {:cancel_cell_evaluation, "c1"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "if the cell is evaluating, clears the corresponding section evaluation and the queue" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :elixir, "c1"},
          {:insert_cell, "s1", 1, :elixir, "c2"},
          {:queue_cell_evaluation, "c1"},
          {:queue_cell_evaluation, "c2"}
        ])

      operation = {:cancel_cell_evaluation, "c1"}

      assert {:ok,
              %{
                cell_infos: %{"c1" => %{status: :fresh}, "c2" => %{status: :fresh}},
                section_infos: %{"s1" => %{evaluating_cell_id: nil, evaluation_queue: []}}
              }} = Data.apply_operation(data, operation)
    end

    test "if the cell is queued, unqueues it" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :elixir, "c1"},
          {:insert_cell, "s1", 1, :elixir, "c2"},
          {:queue_cell_evaluation, "c1"},
          {:queue_cell_evaluation, "c2"}
        ])

      operation = {:cancel_cell_evaluation, "c2"}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{status: :stale}},
                section_infos: %{"s1" => %{evaluating_cell_id: "c1", evaluation_queue: []}}
              }} = Data.apply_operation(data, operation)
    end

    test "if the cell is queued, unqueues dependent cells that are also queued" do
      data =
        data_after_operations!([
          {:insert_section, 0, "s1"},
          {:insert_cell, "s1", 0, :elixir, "c1"},
          {:insert_cell, "s1", 1, :elixir, "c2"},
          {:insert_cell, "s1", 2, :elixir, "c3"},
          {:queue_cell_evaluation, "c1"},
          {:queue_cell_evaluation, "c2"},
          {:queue_cell_evaluation, "c3"}
        ])

      operation = {:cancel_cell_evaluation, "c2"}

      assert {:ok,
              %{
                cell_infos: %{"c3" => %{status: :stale}},
                section_infos: %{"s1" => %{evaluating_cell_id: "c1", evaluation_queue: []}}
              }} = Data.apply_operation(data, operation)
    end
  end

  defp data_after_operations!(operations) do
    Enum.reduce(operations, Data.new(), fn operation, data ->
      case Data.apply_operation(data, operation) do
        {:ok, data} ->
          data

        :error ->
          raise "failed to set up test data, operation #{inspect(operation)} returned an error"
      end
    end)
  end
end
