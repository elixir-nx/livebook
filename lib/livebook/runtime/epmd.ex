defmodule Livebook.Runtime.EPMD do
  # A custom EPMD module used to bypass the epmd OS daemon in the
  # standalone runtime.
  #
  # We used to start epmd on application boot, however sometimes it
  # would fail. In particular, on Windows starting epmd may require
  # accepting a firewall pop up, and the first boot could still fail.
  # To avoid this, we use a custom port resolution that does not rely
  # on the epmd OS daemon running.

  # From Erlang/OTP 23+
  @epmd_dist_version 6

  @doc """
  Persists parent information, used when connecting to the parent.
  """
  def register_parent(parent_node, parent_port) do
    [name, host] = parent_node |> Atom.to_charlist() |> :string.split(~c"@")
    :persistent_term.put(:livebook_parent, {name, host, parent_node, parent_port})
  end

  @doc """
  Returns the current distribution port.
  """
  def dist_port do
    :persistent_term.get(:livebook_dist_port)
  end

  # Custom EPMD callbacks

  # Custom callback to register our current node port.
  def register_node(name, port), do: register_node(name, port, :inet)

  def register_node(name, port, family) do
    :persistent_term.put(:livebook_dist_port, port)

    case :erl_epmd.register_node(name, port, family) do
      {:ok, creation} -> {:ok, creation}
      {:error, :already_registered} -> {:error, :already_registered}
      # If registration fails because EPMD is not running, we ignore
      # that, because we do not rely on EPMD
      _ -> {:ok, -1}
    end
  end

  # Custom callback for resolving parent and sibling node ports.
  def port_please(name, host), do: port_please(name, host, :infinity)

  def port_please(name, host, timeout) do
    case livebook_port(name) do
      0 -> :erl_epmd.port_please(name, host, timeout)
      port -> {:port, port, @epmd_dist_version}
    end
  end

  defp livebook_port(name) do
    {parent_name, parent_host, parent_node, parent_port} = :persistent_term.get(:livebook_parent)

    case match_name(name, parent_name) do
      :parent -> parent_port
      :sibling -> sibling_port(parent_node, name, parent_host)
      :none -> 0
    end
  end

  defp match_name([x | name], [x | parent_name]), do: match_name(name, parent_name)
  defp match_name([?-, ?- | _name], _parent), do: :sibling
  defp match_name([], []), do: :parent
  defp match_name(_name, _parent), do: :none

  defp sibling_port(parent_node, name, host) do
    :gen_server.call(
      {Livebook.EPMD.NodePool, parent_node},
      {:get_port, :erlang.list_to_binary(name ++ [?@] ++ host)},
      5000
    )
  catch
    _, _ -> 0
  end

  # Default EPMD callbacks

  defdelegate start_link(), to: :erl_epmd
  defdelegate address_please(name, host, address_family), to: :erl_epmd
  defdelegate listen_port_please(name, host), to: :erl_epmd
  defdelegate names(host_name), to: :erl_epmd
end
