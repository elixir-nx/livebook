defmodule Livebook.EctoTypes.HexColor do
  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def load(value), do: {:ok, value}

  @impl true
  def dump(value), do: {:ok, value}

  @impl true
  def cast(value) do
    if valid?(value) do
      {:ok, value}
    else
      {:error, message: "not a valid color"}
    end
  end

  @doc """
  Returns a random hex color for a user.

  ## Options

    * `:except` - a list of colors to omit

  """
  def random(opts \\ []) do
    colors = [
      # red
      "#F87171",
      # yellow
      "#FBBF24",
      # green
      "#6EE7B7",
      # blue
      "#60A5FA",
      # purple
      "#A78BFA",
      # pink
      "#F472B6",
      # salmon
      "#FA8072",
      # mat green
      "#9ED9CC"
    ]

    except = opts[:except] || []
    colors = colors -- except

    Enum.random(colors)
  end

  @doc """
  Validates if the given hex color is the correct format

  ## Examples

      iex> Livebook.EctoTypes.HexColor.valid?("#111111")
      true

      iex> Livebook.EctoTypes.HexColor.valid?("#ABC123")
      true

      iex> Livebook.EctoTypes.HexColor.valid?("ABCDEF")
      false

      iex> Livebook.EctoTypes.HexColor.valid?("#111")
      false

  """
  @spec valid?(String.t()) :: boolean()
  def valid?(hex_color), do: hex_color =~ ~r/^#[0-9a-fA-F]{6}$/
end
