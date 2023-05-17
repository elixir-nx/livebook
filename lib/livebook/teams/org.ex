defmodule Livebook.Teams.Org do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          emoji: String.t() | nil,
          name: String.t() | nil,
          teams_key: String.t() | nil,
          user_code: String.t() | nil
        }

  @primary_key {:id, :id, autogenerate: false}
  embedded_schema do
    field :emoji, :string
    field :name, :string
    field :teams_key, :string
    field :user_code, :string
  end

  @fields ~w(id emoji name teams_key user_code)a
  @required_fields @fields -- ~w(id user_code)a

  @doc """
  Generates a new teams key.
  """
  @spec teams_key() :: String.t()
  def teams_key, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  @doc false
  def changeset(org, attrs) do
    org
    |> cast(attrs, @fields)
    |> generate_teams_key()
    |> validate_required(@required_fields)
  end

  defp generate_teams_key(changeset) do
    if get_field(changeset, :teams_key),
      do: changeset,
      else: put_change(changeset, :teams_key, teams_key())
  end
end
