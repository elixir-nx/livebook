defmodule LivebookProto.Event do
  @moduledoc false
  use Protobuf, protoc_gen_elixir_version: "0.11.0", syntax: :proto3

  oneof :type, 0

  field :secret_created, 100,
    type: LivebookProto.SecretCreated,
    json_name: "secretCreated",
    oneof: 0

  field :secret_updated, 101,
    type: LivebookProto.SecretUpdated,
    json_name: "secretUpdated",
    oneof: 0
end
