defmodule LivebookProto.OrgStatusTrial do
  @moduledoc """
  the org is on active or expired trial
  """

  use Protobuf, protoc_gen_elixir_version: "0.13.0", syntax: :proto3

  field :trial_ends_at, 1, type: :int64, json_name: "trialEndsAt"
end
