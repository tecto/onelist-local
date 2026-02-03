defmodule OnelistWeb.Plugs.RequireWatchAccess do
  @moduledoc """
  Plug that requires the user to have "watch" or "admin" role.

  Used for controller-based routes that need watch access protection.
  For LiveViews, use `{OnelistWeb.LiveAuth, :ensure_watch_access}` instead.

  PLAN-051: Phoenix Auth Migration
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    if has_watch_access?(user) do
      conn
    else
      conn
      |> put_flash(:error, "You need watch access to view this page.")
      |> redirect(to: "/login")
      |> halt()
    end
  end

  defp has_watch_access?(nil), do: false
  defp has_watch_access?(user) do
    roles = user.roles || []
    "watch" in roles or "admin" in roles
  end
end
