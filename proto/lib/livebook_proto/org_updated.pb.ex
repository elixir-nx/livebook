defmodule LivebookProto.OrgUpdated do
  use Protobuf, protoc_gen_elixir_version: "0.13.0", syntax: :proto3

  field :id, 1, type: :string
  field :active, 2, type: :bool
end
