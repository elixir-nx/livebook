defmodule Livebook.Copilot.LlamaCppHttpApi.Client do
  require Logger

  @moduledoc """
  A client for interacting with the llama.cpp API described here:
  https://github.com/ggerganov/llama.cpp/blob/df9d1293defe783f42bc83af732d3c670552c541/examples/server/server.cpp

  You can run the llama.cpp server using a command like this

  ./server -m ~/Dev/llm/models/gguf/codellama-7b.Q5_K_M.gguf -c 4096


  This whole file was generated by ChatGPT :P
  """

  # Default base URL
  @base_url "http://127.0.0.1:8080"

  def completion(prompt, options \\ %{}) do
    post("/completion", Map.put(options, :prompt, prompt))
  end

  def tokenize(content) do
    post("/tokenize", %{content: content})
  end

  def detokenize(tokens) do
    post("/detokenize", %{tokens: tokens})
  end

  def embedding(content) do
    post("/embedding", %{content: content})
  end

  def infill(prefix, suffix, options \\ %{}) do
    post("/infill", Map.put(options, :input_prefix, prefix) |> Map.put(:input_suffix, suffix))
  end

  defp log_request_response(endpoint, payload, response) do
    Logger.debug("""
    Request to #{endpoint}:
    #{inspect(payload)}

    Response:
    #{inspect(response)}
    """)
  end

  defp post(endpoint, payload) do
    response = Req.post!("#{@base_url}#{endpoint}", json: payload)
    log_request_response(endpoint, payload, response)
    response
  end
end
