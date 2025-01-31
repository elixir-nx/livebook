defmodule LivebookProto.OrgStatus do
  use Protobuf, protoc_gen_elixir_version: "0.13.0", syntax: :proto3

  oneof :type, 0

  field :trial, 1, type: LivebookProto.OrgStatusTrial, oneof: 0
  field :cancel, 2, type: LivebookProto.OrgStatusCancel, oneof: 0
end
