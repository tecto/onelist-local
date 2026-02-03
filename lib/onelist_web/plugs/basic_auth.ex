defmodule OnelistWeb.Plugs.BasicAuth do
  @moduledoc """
  HTTP Basic Authentication plug for protected routes.
  Supports both single-user and multi-user configurations.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    case get_req_header(conn, "authorization") do
      ["Basic " <> encoded] ->
        case Base.decode64(encoded) do
          {:ok, credentials} ->
            if valid_credentials?(credentials, opts) do
              conn
            else
              unauthorized(conn)
            end

          :error ->
            unauthorized(conn)
        end

      _ ->
        unauthorized(conn)
    end
  end

  # Multi-user mode: list of {username, password} tuples
  defp valid_credentials?(credentials, opts) when is_list(opts) do
    case Keyword.get(opts, :users) do
      users when is_list(users) ->
        Enum.any?(users, fn {username, password} ->
          credentials == "#{username}:#{password}"
        end)

      nil ->
        # Single-user mode (backwards compatible)
        username = Keyword.fetch!(opts, :username)
        password = Keyword.fetch!(opts, :password)
        credentials == "#{username}:#{password}"
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Basic realm="Restricted"))
    |> send_resp(401, "Unauthorized")
    |> halt()
  end
end
