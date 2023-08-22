defmodule Livebook.FileSystem.S3 do
  @moduledoc false

  # File system backed by an S3 bucket.

  defstruct [:id, :bucket_url, :region, :access_key_id, :secret_access_key]

  @type t :: %__MODULE__{
          id: String.t(),
          bucket_url: String.t(),
          region: String.t(),
          access_key_id: String.t(),
          secret_access_key: String.t()
        }

  @doc """
  Returns a new file system struct.

  ## Options

    * `:region` - the bucket region. By default the URL is assumed
      to have the format `*.[region].[rootdomain].com` and the region
      is inferred from that URL

  """
  @spec new(String.t(), String.t(), String.t(), keyword()) :: t()
  def new(bucket_url, access_key_id, secret_access_key, opts \\ []) do
    opts = Keyword.validate!(opts, [:region])

    bucket_url = String.trim_trailing(bucket_url, "/")
    region = opts[:region] || region_from_uri(bucket_url)

    hash = :crypto.hash(:sha256, bucket_url) |> Base.url_encode64(padding: false)
    id = "s3-#{hash}"

    %__MODULE__{
      id: id,
      bucket_url: bucket_url,
      region: region,
      access_key_id: access_key_id,
      secret_access_key: secret_access_key
    }
  end

  defp region_from_uri(uri) do
    # For many services the API host is of the form *.[region].[rootdomain].com
    %{host: host} = URI.parse(uri)
    host |> String.split(".") |> Enum.reverse() |> Enum.at(2, "auto")
  end

  @doc """
  Parses file system from a configuration map.
  """
  @spec from_config(map()) :: {:ok, t()} | {:error, String.t()}
  def from_config(config) do
    case config do
      %{
        bucket_url: bucket_url,
        access_key_id: access_key_id,
        secret_access_key: secret_access_key
      } ->
        file_system = new(bucket_url, access_key_id, secret_access_key, region: config[:region])
        {:ok, file_system}

      _config ->
        {:error,
         "S3 configuration is expected to have keys: :bucket_url, :access_key_id and :secret_access_key, but got #{inspect(config)}"}
    end
  end

  @spec to_config(t()) :: map()
  def to_config(%__MODULE__{} = s3) do
    Map.take(s3, [:bucket_url, :region, :access_key_id, :secret_access_key])
  end
end

defimpl Livebook.FileSystem, for: Livebook.FileSystem.S3 do
  alias Livebook.FileSystem
  alias Livebook.FileSystem.S3

  def resource_identifier(file_system) do
    {:s3, file_system.bucket_url}
  end

  def type(_file_system) do
    :global
  end

  def default_path(_file_system) do
    "/"
  end

  def list(file_system, path, recursive) do
    FileSystem.Utils.assert_dir_path!(path)
    "/" <> dir_key = path
    delimiter = if recursive, do: nil, else: "/"
    opts = [prefix: dir_key, delimiter: delimiter]

    with {:ok, %{keys: keys}} <- S3.Client.list_objects(file_system, opts) do
      if keys == [] and dir_key != "" do
        FileSystem.Utils.posix_error(:enoent)
      else
        paths = keys |> List.delete(dir_key) |> Enum.map(&("/" <> &1))
        {:ok, paths}
      end
    end
  end

  def read(file_system, path) do
    FileSystem.Utils.assert_regular_path!(path)
    "/" <> key = path

    S3.Client.get_object(file_system, key)
  end

  def write(file_system, path, content) do
    FileSystem.Utils.assert_regular_path!(path)
    "/" <> key = path

    S3.Client.put_object(file_system, key, content)
  end

  def access(_file_system, _path) do
    {:ok, :read_write}
  end

  def create_dir(file_system, path) do
    FileSystem.Utils.assert_dir_path!(path)
    "/" <> key = path

    # S3 has no concept of directories, but keys with trailing
    # slash are interpreted as such, so we create an empty
    # object for the given key
    S3.Client.put_object(file_system, key, nil)
  end

  def remove(file_system, path) do
    "/" <> key = path

    if FileSystem.Utils.dir_path?(path) do
      with {:ok, %{keys: keys}} <- S3.Client.list_objects(file_system, prefix: key) do
        if keys == [] do
          FileSystem.Utils.posix_error(:enoent)
        else
          S3.Client.delete_objects(file_system, keys)
        end
      end
    else
      S3.Client.delete_object(file_system, key)
    end
  end

  def copy(file_system, source_path, destination_path) do
    FileSystem.Utils.assert_same_type!(source_path, destination_path)
    "/" <> source_key = source_path
    "/" <> destination_key = destination_path

    if FileSystem.Utils.dir_path?(source_path) do
      with {:ok, %{bucket: bucket, keys: keys}} <-
             S3.Client.list_objects(file_system, prefix: source_key) do
        if keys == [] do
          FileSystem.Utils.posix_error(:enoent)
        else
          keys
          |> Enum.map(fn key ->
            renamed_key = String.replace_prefix(key, source_key, destination_key)

            Task.async(fn ->
              S3.Client.copy_object(file_system, bucket, key, renamed_key)
            end)
          end)
          |> Task.await_many(:infinity)
          |> Enum.filter(&match?({:error, _}, &1))
          |> case do
            [] -> :ok
            [error | _] -> error
          end
        end
      end
    else
      with {:ok, bucket} <- S3.Client.get_bucket_name(file_system) do
        S3.Client.copy_object(file_system, bucket, source_key, destination_key)
      end
    end
  end

  def rename(file_system, source_path, destination_path) do
    FileSystem.Utils.assert_same_type!(source_path, destination_path)
    "/" <> destination_key = destination_path

    with {:ok, destination_exists?} <- S3.Client.object_exists(file_system, destination_key) do
      if destination_exists? do
        FileSystem.Utils.posix_error(:eexist)
      else
        # S3 doesn't support an atomic rename/move operation,
        # so we implement it as copy followed by remove
        with :ok <- copy(file_system, source_path, destination_path) do
          remove(file_system, source_path)
        end
      end
    end
  end

  def etag_for(file_system, path) do
    FileSystem.Utils.assert_regular_path!(path)
    "/" <> key = path

    with {:ok, %{etag: etag}} <- S3.Client.head_object(file_system, key) do
      {:ok, etag}
    end
  end

  def exists?(file_system, path) do
    "/" <> key = path

    S3.Client.object_exists(file_system, key)
  end

  def resolve_path(_file_system, dir_path, subject) do
    FileSystem.Utils.resolve_unix_like_path(dir_path, subject)
  end

  def write_stream_init(_file_system, path, opts) do
    opts = Keyword.validate!(opts, part_size: 50_000_000)

    FileSystem.Utils.assert_regular_path!(path)
    "/" <> key = path

    {:ok,
     %{
       key: key,
       parts: 0,
       etags: [],
       current_chunks: [],
       current_size: 0,
       part_size: opts[:part_size],
       upload_id: nil
     }}
  end

  def write_stream_chunk(file_system, state, chunk) when is_binary(chunk) do
    chunk_size = byte_size(chunk)

    state = update_in(state.current_size, &(&1 + chunk_size))
    state = update_in(state.current_chunks, &[chunk | &1])

    if state.current_size >= state.part_size do
      maybe_state =
        if state.upload_id do
          {:ok, state}
        else
          with {:ok, upload_id} <- S3.Client.create_multipart_upload(file_system, state.key) do
            {:ok, %{state | upload_id: upload_id}}
          end
        end

      with {:ok, state} <- maybe_state do
        upload_part_from_state(file_system, state, state.part_size)
      end
    else
      {:ok, state}
    end
  end

  defp upload_part_from_state(file_system, state, part_size) do
    <<part::binary-size(part_size), rest::binary>> =
      state.current_chunks
      |> Enum.reverse()
      |> IO.iodata_to_binary()

    parts = state.parts + 1

    with {:ok, %{etag: etag}} <-
           S3.Client.upload_part(file_system, state.key, state.upload_id, parts, part) do
      {:ok,
       %{
         state
         | current_chunks: [rest],
           current_size: byte_size(rest),
           etags: [etag | state.etags],
           parts: parts
       }}
    end
  end

  def write_stream_finish(file_system, state) do
    if state.upload_id do
      maybe_state =
        if state.current_size > 0 do
          upload_part_from_state(file_system, state, state.current_size)
        else
          {:ok, state}
        end

      with {:ok, state} <- maybe_state,
           :ok <-
             S3.Client.complete_multipart_upload(
               file_system,
               state.key,
               state.upload_id,
               Enum.reverse(state.etags)
             ) do
        :ok
      else
        {:error, error} ->
          S3.Client.abort_multipart_upload(file_system, state.key, state.upload_id)
          {:error, error}
      end
    else
      content = state.current_chunks |> Enum.reverse() |> IO.iodata_to_binary()
      S3.Client.put_object(file_system, state.key, content)
    end
  end

  def write_stream_halt(file_system, state) do
    if state.upload_id do
      S3.Client.abort_multipart_upload(file_system, state.key, state.upload_id)
    else
      :ok
    end
  end

  def read_stream_into(file_system, path, collectable) do
    FileSystem.Utils.assert_regular_path!(path)
    "/" <> key = path

    S3.Client.multipart_get_object(file_system, key, collectable)
  end

  def load(_file_system, %{"bucket_url" => _} = fields) do
    S3.new(fields["bucket_url"], fields["access_key_id"], fields["secret_access_key"],
      region: fields["region"]
    )
  end

  def load(_file_system, fields) do
    S3.new(fields.bucket_url, fields.access_key_id, fields.secret_access_key,
      region: fields[:region]
    )
  end

  def dump(file_system) do
    file_system
    |> Map.from_struct()
    |> Map.take([:bucket_url, :region, :access_key_id, :secret_access_key])
  end
end
