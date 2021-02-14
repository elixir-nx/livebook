defmodule LiveBook.ExMd.MarkdownRenderer do
  # TODO: split html/table/list rendering to submodules?

  # https://www.w3.org/TR/2011/WD-html-markup-20110113/syntax.html#void-element
  @void_elements ~W(area base br col command embed hr img input keygen link meta param source track wbr)

  def ast_to_markdown(ast) do
    ast
    |> ast_to_md([])
    |> IO.iodata_to_binary()
    |> String.trim()
  end

  defp ast_to_md([], iodata), do: iodata

  defp ast_to_md([string | ast], iodata) when is_binary(string) do
    ast_to_md(ast, [iodata, string])
  end

  defp ast_to_md([{tag, attrs, [], %{verbatim: true}} | ast], iodata)
       when tag in @void_elements do
    md = "<#{tag} #{attrs_to_string(attrs)} />"

    ast_to_md(ast, [iodata, "\n", md, "\n"])
  end

  defp ast_to_md([{tag, attrs, lines, %{verbatim: true}} | ast], iodata) do
    inner = Enum.join(lines, "\n")
    md = "<#{tag} #{attrs_to_string(attrs)}>\n#{inner}\n</#{tag}>"

    ast_to_md(ast, [iodata, "\n", md, "\n"])
  end

  defp ast_to_md([{"em", _, content, %{}} | ast], iodata) do
    md_content = ast_to_markdown(content)
    md = "*#{md_content}*"

    ast_to_md(ast, [iodata, md])
  end

  defp ast_to_md([{"strong", _, content, %{}} | ast], iodata) do
    md_content = ast_to_markdown(content)
    md = "**#{md_content}**"

    ast_to_md(ast, [iodata, md])
  end

  defp ast_to_md([{"del", _, content, %{}} | ast], iodata) do
    md_content = ast_to_markdown(content)
    md = "~~#{md_content}~~"

    ast_to_md(ast, [iodata, md])
  end

  defp ast_to_md([{"code", _, content, %{}} | ast], iodata) do
    md_content = ast_to_markdown(content)
    md = "`#{md_content}`"

    ast_to_md(ast, [iodata, md])
  end

  defp ast_to_md([{"a", attrs, content, %{}} | ast], iodata) do
    caption = ast_to_markdown(content)
    href = get_attr(attrs, "href", "")
    md = "[#{caption}](#{href})"

    ast_to_md(ast, [iodata, md])
  end

  defp ast_to_md([{"img", attrs, [], %{}} | ast], iodata) do
    if attr_keys(attrs) -- ["alt", "src", "title"] != [] do
      md = "<img #{attrs_to_string(attrs)} />"

      ast_to_md(ast, [iodata, md])
    else
      alt = get_attr(attrs, "alt", "")
      src = get_attr(attrs, "src", "")
      title = get_attr(attrs, "title", "")

      md =
        if title == "" do
          "![#{alt}](#{src})"
        else
          ~s/![#{alt}](#{src} "#{title}")/
        end

      ast_to_md(ast, [iodata, md])
    end
  end

  defp ast_to_md([{:comment, _, lines, %{comment: true}} | ast], iodata) do
    md =
      case lines do
        [line] ->
          line = String.trim(line)
          "<!-- #{line} -->"

        lines ->
          lines =
            lines
            |> Enum.drop_while(&blank?/1)
            |> Enum.reverse()
            |> Enum.drop_while(&blank?/1)
            |> Enum.reverse()

          Enum.join(["<!--" | lines] ++ ["-->"], "\n")
      end

    ast_to_md(ast, [iodata, md])
  end

  defp ast_to_md([{"hr", attrs, [], %{}} | ast], iodata) do
    class = get_attr(attrs, "class", "thin")
    md = ruler_by_class(class)
    ast_to_md(ast, [iodata, "\n", md, "\n"])
  end

  defp ast_to_md([{"p", _, content, %{}} | ast], iodata) do
    md = ast_to_markdown(content)
    ast_to_md(ast, [iodata, "\n", md, "\n"])
  end

  defp ast_to_md([{"h" <> n, _, content, %{}} | ast], iodata)
       when n in ["1", "2", "3", "4", "5", "6"] do
    title = ast_to_markdown(content)
    n = String.to_integer(n)
    md = String.duplicate("#", n) <> " " <> title
    ast_to_md(ast, [iodata, "\n", md, "\n"])
  end

  defp ast_to_md([{"pre", _, [{"code", attrs, [content], %{}}], %{}} | ast], iodata) do
    language = get_attr(attrs, "class", "")
    ast_to_md(ast, [iodata, "\n", "```#{language}\n#{content}\n```", "\n"])
  end

  defp ast_to_md([{"blockquote", [], content, %{}} | ast], iodata) do
    content_md = ast_to_markdown(content)

    md =
      content_md
      |> String.split("\n")
      |> Enum.map(&("> " <> &1))
      |> Enum.join("\n")

    ast_to_md(ast, [iodata, "\n", md, "\n"])
  end

  defp ast_to_md(
         [
           {"table", _, [{"thead", _, [{"tr", _, head, %{}}], %{}}, {"tbody", _, rows, %{}}], %{}}
           | ast
         ],
         iodata
       ) do
    alignments =
      Enum.map(head, fn
        {"th", [{"style", "text-align: left;"}], _, %{}} -> :left
        {"th", [{"style", "text-align: center;"}], _, %{}} -> :center
        {"th", [{"style", "text-align: right;"}], _, %{}} -> :right
      end)

    head = Enum.map(head, fn {"th", _, content, %{}} -> ast_to_markdown(content) end)

    rows =
      Enum.map(rows, fn {"tr", _, columns, %{}} ->
        Enum.map(columns, fn {"td", _, content, %{}} -> ast_to_markdown(content) end)
      end)

    max_lenghts =
      [head | rows]
      |> List.zip()
      |> Enum.map(&Tuple.to_list/1)
      |> Enum.map(fn values ->
        values
        |> Enum.map(&String.length/1)
        |> Enum.max()
      end)

    head_cells =
      head
      |> Enum.zip(max_lenghts)
      |> Enum.map(fn {value, length} ->
        String.pad_trailing(value, length, " ")
      end)

    rows_cells =
      Enum.map(rows, fn row ->
        row
        |> Enum.zip(max_lenghts)
        |> Enum.map(fn {value, length} ->
          String.pad_trailing(value, length, " ")
        end)
      end)

    separator_cells =
      alignments
      |> Enum.zip(max_lenghts)
      |> Enum.map(fn
        {:left, length} -> String.duplicate("-", length)
        {:center, length} -> ":" <> String.duplicate("-", length - 2) <> ":"
        {:right, length} -> String.duplicate("-", length - 1) <> ":"
      end)

    head_line = "| " <> Enum.join(head_cells, " | ") <> " |"
    separators_line = "| " <> Enum.join(separator_cells, " | ") <> " |"

    row_lines =
      Enum.map(rows_cells, fn row_cells ->
        "| " <> Enum.join(row_cells, " | ") <> " |"
      end)

    md = Enum.join([head_line, separators_line | row_lines], "\n")

    ast_to_md(ast, [iodata, "\n", md, "\n"])
  end

  defp ast_to_md([{"table", _, [{"tbody", _, rows, %{}}], %{}} | ast], iodata) do
    rows =
      Enum.map(rows, fn {"tr", _, columns, %{}} ->
        Enum.map(columns, fn {"td", _, content, %{}} -> ast_to_markdown(content) end)
      end)

    max_lenghts =
      rows
      |> List.zip()
      |> Enum.map(&Tuple.to_list/1)
      |> Enum.map(fn values ->
        values
        |> Enum.map(&String.length/1)
        |> Enum.max()
      end)

    rows_cells =
      Enum.map(rows, fn row ->
        row
        |> Enum.zip(max_lenghts)
        |> Enum.map(fn {value, length} ->
          String.pad_trailing(value, length, " ")
        end)
      end)

    row_lines =
      Enum.map(rows_cells, fn row_cells ->
        "| " <> Enum.join(row_cells, " | ") <> " |"
      end)

    md = Enum.join(row_lines, "\n")

    ast_to_md(ast, [iodata, "\n", md, "\n"])
  end

  defp ast_to_md([{"ul", _, items, %{}} | ast], iodata) do
    star_fun = fn _index -> "* " end
    md = list_items_to_md(items, star_fun, "  ")

    ast_to_md(ast, [iodata, "\n", md, "\n"])
  end

  defp ast_to_md([{"ol", _, items, %{}} | ast], iodata) do
    numeric_fun = fn index -> "#{index + 1}. " end
    md = list_items_to_md(items, numeric_fun, "   ")

    ast_to_md(ast, [iodata, "\n", md, "\n"])
  end

  # ---

  defp ruler_by_class("thin"), do: "---"
  defp ruler_by_class("medium"), do: "___"
  defp ruler_by_class("thick"), do: "***"

  defp list_items_to_md(items, marker_fun, indent) do
    spaced = spaced_list?(items)

    md_items =
      items
      |> Enum.map(fn {"li", _, content, %{}} -> content end)
      |> Enum.with_index()
      |> Enum.map(fn {content, index} ->
        md_item = ast_to_markdown(content)

        [head | tail] = String.split(md_item, "\n")
        head = marker_fun.(index) <> head

        tail =
          Enum.map(tail, fn
            "" -> ""
            line -> indent <> line
          end)

        Enum.join([head | tail], "\n")
      end)

    item_separator = if(spaced, do: "\n\n", else: "\n")

    Enum.join(md_items, item_separator)
  end

  defp spaced_list?([{"li", _, [{"p", _, _content, %{}} | _], %{}} | _items]), do: true
  defp spaced_list?([_ | items]), do: spaced_list?(items)
  defp spaced_list?([]), do: false

  defp get_attr(attrs, key, default) do
    Enum.find_value(attrs, default, fn {attr_key, attr_value} ->
      attr_key == key && attr_value
    end)
  end

  defp attr_keys(attrs) do
    Enum.map(attrs, &elem(&1, 0))
  end

  defp attrs_to_string(attrs) do
    attrs
    |> Enum.map(fn {key, value} -> ~s/#{key}="#{value}"/ end)
    |> Enum.join(" ")
  end

  defp blank?(string), do: String.trim(string) == ""
end
