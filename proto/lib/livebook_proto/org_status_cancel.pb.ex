defmodule LivebookProto.OrgStatusCancel do
  @moduledoc """
  the org is or will be cancelled
  """

  use Protobuf, protoc_gen_elixir_version: "0.13.0", syntax: :proto3

  field :cancel_at, 1, type: :int64, json_name: "cancelAt"
end
