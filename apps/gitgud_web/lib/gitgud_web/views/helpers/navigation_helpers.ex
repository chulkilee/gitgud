defmodule GitGud.Web.NavigationHelpers do
  @moduledoc """
  Conveniences for routing and navigation.
  """

  import Phoenix.HTML.Tag
  import Phoenix.Controller, only: [controller_module: 1, action_name: 1]

  import GitGud.Web.Router, only: [__routes__: 0]

  @doc """
  Returns `true` if `conn` matches the given route `helper`; otherwhise return `false`.
  """
  @spec current_route?(Plug.Conn.t(), atom, []) :: boolean
  def current_route?(conn, helper, action \\ [])

  def current_route?(conn, helper, []) do
    controller_module(conn) == helper_controller(helper)
  end

  @spec current_route?(Plug.Conn.t(), atom, only: [atom]) :: boolean
  def current_route?(conn, helper, only: actions) when is_list(actions) do
    current_route?(conn, helper) && action_name(conn) in actions
  end

  @spec current_route?(Plug.Conn.t(), atom, except: [atom]) :: boolean
  def current_route?(conn, helper, except: actions) when is_list(actions) do
    current_route?(conn, helper) && action_name(conn) not in actions
  end

  @spec current_route?(Plug.Conn.t(), atom, atom) :: boolean
  def current_route?(conn, helper, action) when is_atom(action) do
    current_route?(conn, helper) && action_name(conn) == action
  end

  @doc """
  Renders a navigation item for the given `helper` and `action`.
  """
  @spec navigation_item(Plug.Conn.t(), atom, keyword | atom, atom, keyword, do: term) :: binary
  def navigation_item(conn, helper, action \\ [], tag \\ :li, attrs \\ [], do: block) do
    class = "is-active"

    attrs =
      if current_route?(conn, helper, action),
        do: Keyword.update(attrs, :class, class, &"#{&1} #{class}"),
        else: attrs

    content_tag(tag, block, attrs)
  end

  #
  # Helpers
  #

  for route <- Enum.uniq_by(Enum.filter(__routes__(), &is_binary(&1.helper)), & &1.helper) do
    helper = String.to_atom(route.helper)
    defp helper_controller(unquote(helper)), do: unquote(route.plug)
  end

  defp helper_controller(helper),
    do: raise(ArgumentError, message: "invalid helper #{inspect(helper)}")
end
