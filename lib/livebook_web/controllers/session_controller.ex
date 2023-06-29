defmodule LivebookWeb.SessionController do
  use LivebookWeb, :controller

  alias Livebook.{Sessions, Session, FileSystem}

  def show_file(conn, %{"id" => id, "name" => name}) do
    with {:ok, session} <- Sessions.fetch_session(id),
         {:ok, file_entry} <- fetch_file_entry(session, name),
         true <- file_entry.type == :attachment do
      file = FileSystem.File.resolve(session.files_dir, file_entry.name)
      serve_static(conn, file)
    else
      _ ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp fetch_file_entry(session, name) do
    file_entries = Session.get_notebook_file_entries(session.pid)

    Enum.find_value(file_entries, :error, fn file_entry ->
      if file_entry.name == name do
        {:ok, file_entry}
      end
    end)
  end

  # Legacy endpoint for resolving images/
  def show_image(conn, %{"id" => id, "name" => name}) do
    case Sessions.fetch_session(id) do
      {:ok, session} ->
        images_dir = FileSystem.File.resolve(session.files_dir, "../images/")
        file = FileSystem.File.resolve(images_dir, name)
        serve_static(conn, file)

      :error ->
        send_resp(conn, 404, "Not found")
    end
  end

  def download_source(conn, %{"id" => id, "format" => format}) do
    case Sessions.fetch_session(id) do
      {:ok, session} ->
        notebook = Session.get_notebook(session.pid)
        file_name = Session.file_name_for_download(session)

        send_notebook_source(conn, notebook, file_name, format)

      :error ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp send_notebook_source(conn, notebook, file_name, "livemd" = format) do
    opts = [include_outputs: conn.params["include_outputs"] == "true"]
    {source, _warnings} = Livebook.LiveMarkdown.notebook_to_livemd(notebook, opts)

    send_download(conn, {:binary, source},
      filename: file_name <> "." <> format,
      content_type: "text/plain"
    )
  end

  defp send_notebook_source(conn, notebook, file_name, "exs" = format) do
    source = Livebook.Notebook.Export.Elixir.notebook_to_elixir(notebook)

    send_download(conn, {:binary, source},
      filename: file_name <> "." <> format,
      content_type: "text/plain"
    )
  end

  defp send_notebook_source(conn, _notebook, _file_name, _format) do
    send_resp(conn, 400, "Invalid format, supported formats: livemd, exs")
  end

  defp serve_static(conn, file) do
    with {:ok, cache_state, conn} <- put_cache_header(conn, file),
         {:ok, conn} <- serve_with_cache(conn, file, cache_state) do
      conn
    else
      {:error, message} -> send_resp(conn, 404, Livebook.Utils.upcase_first(message))
    end
  end

  defp put_cache_header(conn, file) do
    with {:ok, etag} <- FileSystem.File.etag_for(file) do
      conn =
        conn
        |> put_resp_header("cache-control", "public")
        |> put_resp_header("etag", etag)

      if etag in get_req_header(conn, "if-none-match") do
        {:ok, :fresh, conn}
      else
        {:ok, :stale, conn}
      end
    end
  end

  defp serve_with_cache(conn, file, :stale) do
    filename = FileSystem.File.name(file)

    with {:ok, content} <- FileSystem.File.read(file) do
      conn
      |> put_content_type(filename)
      |> send_resp(200, content)
      |> then(&{:ok, &1})
    end
  end

  defp serve_with_cache(conn, _file, :fresh) do
    {:ok, send_resp(conn, 304, "")}
  end

  def show_asset(conn, %{"id" => id, "hash" => hash, "file_parts" => file_parts}) do
    asset_path = Path.join(file_parts)

    # The request comes from a cross-origin iframe
    conn = allow_cors(conn)

    # This route include session id, while we want the browser to
    # cache assets across sessions, so we only ensure the asset
    # is available and redirect to the corresponding route without
    # session id
    if ensure_asset?(id, hash, asset_path) do
      conn
      |> cache_permanently()
      |> put_status(:moved_permanently)
      |> redirect(to: ~p"/public/sessions/assets/#{hash}/#{file_parts}")
    else
      send_resp(conn, 404, "Not found")
    end
  end

  def show_cached_asset(conn, %{"hash" => hash, "file_parts" => file_parts}) do
    asset_path = Path.join(file_parts)

    # The request comes from a cross-origin iframe
    conn = allow_cors(conn)

    case lookup_asset(hash, asset_path) do
      {:ok, local_asset_path} ->
        conn =
          conn
          |> put_content_type(asset_path)
          |> cache_permanently()

        local_asset_path_gz = local_asset_path <> ".gz"

        if accept_encoding?(conn, "gzip") and File.exists?(local_asset_path_gz) do
          conn
          |> put_resp_header("content-encoding", "gzip")
          |> put_resp_header("vary", "Accept-Encoding")
          |> send_file(200, local_asset_path_gz)
        else
          send_file(conn, 200, local_asset_path)
        end

      :error ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp accept_encoding?(conn, encoding) do
    encoding? = &String.contains?(&1, [encoding, "*"])

    Enum.any?(get_req_header(conn, "accept-encoding"), fn accept ->
      accept |> Plug.Conn.Utils.list() |> Enum.any?(encoding?)
    end)
  end

  defp ensure_asset?(session_id, hash, asset_path) do
    case lookup_asset(hash, asset_path) do
      {:ok, _local_asset_path} ->
        true

      :error ->
        with {:ok, session} <- Sessions.fetch_session(session_id),
             :ok <- Session.fetch_assets(session.pid, hash) do
          true
        else
          _ -> false
        end
    end
  end

  defp lookup_asset(hash, asset_path) do
    with {:ok, local_asset_path} <- Session.local_asset_path(hash, asset_path),
         true <- File.exists?(local_asset_path) do
      {:ok, local_asset_path}
    else
      _ -> :error
    end
  end

  defp allow_cors(conn) do
    put_resp_header(conn, "access-control-allow-origin", "*")
  end

  defp cache_permanently(conn) do
    put_resp_header(conn, "cache-control", "public, max-age=31536000")
  end

  defp put_content_type(conn, path) do
    content_type = MIME.from_path(path)
    put_resp_header(conn, "content-type", content_type)
  end
end
