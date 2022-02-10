defprotocol Livebook.Runtime do
  @moduledoc false

  # This protocol defines an interface for code evaluation backends.
  #
  # Usually a runtime involves a set of processes responsible for
  # evaluation, which could be running on a different node, however
  # the protocol does not require that.

  @typedoc """
  An arbitrary term identifying an evaluation container.

  A container is an abstraction of an isolated group of evaluations.
  Containers are mostly independent and therefore can be evaluated
  concurrently (if possible).

  Note that every evaluation can use the resulting binding and env
  of any previous evaluation, even from a different container.
  """
  @type container_ref :: term()

  @typedoc """
  An arbitrary term identifying an evaluation.
  """
  @type evaluation_ref :: term()

  @typedoc """
  A pair identifying evaluation together with its container.

  When the evaluation reference is `nil`, the `locator` points to
  a container and may be used to represent its default evaluation
  context.
  """
  @type locator :: {container_ref(), evaluation_ref() | nil}

  @typedoc """
  An output emitted during evaluation or as the final result.

  For more details on output types see `t:Kino.Output.t/0`.
  """
  @type output ::
          :ignored
          # IO output, adjacent such outputs are treated as a whole
          | {:stdout, binary()}
          # Standalone text block
          | {:text, binary()}
          # Markdown content
          | {:markdown, binary()}
          # A raw image in the given format
          | {:image, content :: binary(), mime_type :: binary()}
          # JavaScript powered output
          | {:js, info :: map()}
          # Outputs placeholder
          | {:frame, outputs :: list(output()), info :: map()}
          # An input field
          | {:input, attrs :: map()}
          # A control element
          | {:control, attrs :: map()}
          # Internal output format for errors
          | {:error, message :: binary(), type :: :other | :runtime_restart_required}

  @typedoc """
  Additional information about a complted evaluation.
  """
  @type evaluation_response_metadata :: %{
          evaluation_time_ms: non_neg_integer(),
          code_error: code_error(),
          memory_usage: runtime_memory()
        }

  @typedoc """
  Recognised intellisense request.
  """
  @type intellisense_request ::
          completion_request()
          | details_request()
          | signature_request()
          | format_request()

  @typedoc """
  Expected intellisense response.

  Responding with `nil` indicates there is no relevant reply and
  effectively aborts the request, so it's suitable for error cases.
  """
  @type intellisense_response ::
          nil
          | completion_response()
          | details_response()
          | signature_response()
          | format_response()

  @typedoc """
  Looks up a list of identifiers that are suitable code completions
  for the given hint.
  """
  @type completion_request :: {:completion, hint :: String.t()}

  @type completion_response :: %{
          items: list(completion_item())
        }

  @type completion_item :: %{
          label: String.t(),
          kind: completion_item_kind(),
          detail: String.t() | nil,
          documentation: String.t() | nil,
          insert_text: String.t()
        }

  @type completion_item_kind ::
          :function | :module | :struct | :interface | :type | :variable | :field | :keyword

  @typedoc """
  Looks up more details about an identifier found in `column` in
  `line`.
  """
  @type details_request :: {:details, line :: String.t(), column :: pos_integer()}

  @type details_response :: %{
          range: %{
            from: non_neg_integer(),
            to: non_neg_integer()
          },
          contents: list(String.t())
        }

  @typedoc """
  Looks up a list of function signatures matching the given hint.

  The resulting information includes current position in the argument
  list.
  """
  @type signature_request :: {:signature, hint :: String.t()}

  @type signature_response :: %{
          active_argument: non_neg_integer(),
          signature_items: list(signature_item())
        }

  @type signature_item :: %{
          signature: String.t(),
          arguments: list(String.t()),
          documentation: String.t() | nil
        }

  @typedoc """
  Formats the given code snippet.
  """
  @type format_request :: {:format, code :: String.t()}

  @type format_response :: %{
          code: String.t() | nil,
          code_error: code_error() | nil
        }

  @typedoc """
  A descriptive error pointing to a specific line in the code.
  """
  @type code_error :: %{line: pos_integer(), description: String.t()}

  @typedoc """
  The detailed runtime memory usage.

  The runtime may periodically send memory usage updates as

    * `{:runtime_memory_usage, runtime_memory()}`
  """
  @type runtime_memory :: %{
          atom: size_in_bytes(),
          binary: size_in_bytes(),
          code: size_in_bytes(),
          ets: size_in_bytes(),
          other: size_in_bytes(),
          processes: size_in_bytes(),
          total: size_in_bytes()
        }

  @type size_in_bytes :: non_neg_integer()

  @doc """
  Connects the caller to the given runtime.

  The caller becomes the runtime owner, which makes it the target
  for most of the runtime messages and ties the runtime life to the
  Sets the caller as runtime owner.

  It is advised for each runtime to have a leading process that is
  coupled to the lifetime of the underlying runtime resources. In
  such case the `connect` function may start monitoring this process
  and return the monitor reference. This way the caller is notified
  when the runtime goes down by listening to the :DOWN message with
  that reference.

  ## Options

    * `:runtime_broadcast_to` - the process to send runtime broadcast
      events to. Defaults to the owner
  """
  @spec connect(t(), keyword()) :: reference()
  def connect(runtime, opts \\ [])

  @doc """
  Disconnects the current owner from the runtime.

  This should cleanup the underlying node/processes.
  """
  @spec disconnect(t()) :: :ok
  def disconnect(runtime)

  @doc """
  Asynchronously parses and evaluates the given code.

  The given `locator` identifies the container where the code should
  be evaluated as well as the evaluation reference to store the
  resulting context under.

  Additionally, `prev_locator` points to a previous evaluation to be
  used as the starting point of this evaluation. If not applicable,
  the previous evaluation reference may be specified as `nil`.

  ## Communication

  During evaluation a number of messages may be sent to the runtime
  owner. All captured outputs have the form:

    * `{:runtime_evaluation_output, evaluation_ref, output}`

  When the evaluation completes, the resulting output and metadata
  is sent as:

    * `{:runtime_evaluation_response, evaluation_ref, output, metadata}`

  Outputs may include input fields. The evaluation may then request
  the current value of a previously rendered input by sending

    * `{:runtime_evaluation_input, evaluation_ref, reply_to, input_id}`

  to the  runtime owner who is supposed to reply with
  `{:runtime_evaluation_input_reply, reply}` where `reply` is either
  `{:ok, value}` or `:error` if no matching input can be found.

  If the evaluation state within a container is lost (for example when
  a process goes down), the runtime may send

    * `{:runtime_container_down, container_ref, message}`

  to notify the owner.

  ## Options

    * `:file` - the file considered as the source during evaluation.
      This information is relevant for errors formatting and imparts
      the value of `__DIR__`
  """
  @spec evaluate_code(t(), String.t(), locator(), locator(), keyword()) :: :ok
  def evaluate_code(runtime, code, locator, prev_locator, opts \\ [])

  @doc """
  Disposes of an evaluation identified by the given locator.

  This can be used to cleanup resources related to an old evaluation
  if it is no longer needed.
  """
  @spec forget_evaluation(t(), locator()) :: :ok
  def forget_evaluation(runtime, locator)

  @doc """
  Disposes of an evaluation container identified by the given ref.

  This should be used to cleanup resources keeping track of the
  container all of its evaluations.
  """
  @spec drop_container(t(), container_ref()) :: :ok
  def drop_container(runtime, container_ref)

  @doc """
  Asynchronously handles an intellisense request.

  This part of runtime functionality is used to provide language-
  and context-specific intellisense features in the text editor.

  The response is sent to the `send_to` process as

    * `{:runtime_intellisense_response, ref, request, response}`.

  The given `locator` idenfities an evaluation that may be used
  as the context when resolving the request (if relevant).
  """
  @spec handle_intellisense(t(), pid(), reference(), intellisense_request(), locator()) :: :ok
  def handle_intellisense(runtime, send_to, ref, request, locator)

  @doc """
  Synchronously starts a runtime of the same type with the same
  parameters.
  """
  @spec duplicate(Runtime.t()) :: {:ok, Runtime.t()} | {:error, String.t()}
  def duplicate(runtime)

  @doc """
  Returns true if the given runtime is self-contained.

  A standalone runtime always starts fresh and frees all resources
  on termination. This may not be the case for for runtimes that
  connect to an external running system and use it for code evaluation.
  """
  @spec standalone?(Runtime.t()) :: boolean()
  def standalone?(runtime)

  @doc """
  Reads file at the given absolute path within the runtime file system.
  """
  @spec read_file(Runtime.t(), String.t()) :: {:ok, binary()} | {:error, String.t()}
  def read_file(runtime, path)
end
