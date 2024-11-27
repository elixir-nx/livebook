defmodule Livebook.Users.User do
  # Represents a Livebook user.
  #
  # Livebook users are not regular web app accounts,
  # but rather ephemeral data about the clients
  # using the app. Every person using Livebook
  # can provide data like name and cursor color
  # to improve visibility during collaboration.

  use Ecto.Schema
  import Ecto.Changeset

  alias Livebook.Utils

  @type t :: %__MODULE__{
          id: id(),
          name: String.t() | nil,
          email: String.t() | nil,
          avatar_url: String.t() | nil,
          payload: map() | nil,
          role: :editor | :viewer,
          hex_color: hex_color()
        }

  @type id :: Utils.id()
  @type hex_color :: String.t()

  embedded_schema do
    field :name, :string
    field :email, :string
    field :avatar_url, :string
    field :payload, :map
    field :role, Ecto.Enum, values: [:editor, :viewer]
    field :hex_color, Livebook.EctoTypes.HexColor
  end

  @doc """
  Generates a new user.
  """
  @spec new(String.t()) :: t()
  def new(id \\ Utils.random_long_id()) do
    %__MODULE__{
      id: id,
      name: nil,
      email: nil,
      avatar_url: nil,
      role: :editor,
      hex_color: Livebook.EctoTypes.HexColor.random()
    }
  end

  def changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:name, :email, :avatar_url, :hex_color, :role])
    |> validate_required([:hex_color])
  end
end
