defmodule GitGud.Web.SessionControllerTest do
  use GitGud.Web.ConnCase

  alias GitGud.User
  alias GitGud.Web.AuthenticationPlug

  setup %{conn: conn} do
    user =
      User.register!(
        name: "Mario Flach",
        username: "redrabbit",
        email: "m.flach@almightycouch.com",
        password: "test1234"
      )

    conn = put_req_header(conn, "accept", "application/json")
    {:ok, conn: conn, user: user}
  end

  test "creates token with user credentials", %{conn: conn} do
    conn = post conn, user_token_path(conn, :create), username: "redrabbit", password: "test1234"
    resp = json_response(conn, :created)
    assert byte_size(resp["token"]) == 100
    assert resp["expiration_time"] == AuthenticationPlug.token_expiration_time()
  end

  test "fails to create token with invalid user credentials", %{conn: conn} do
    conn =
      post conn, user_token_path(conn, :create), username: "redrabbit", password: "testpasswd"

    assert json_response(conn, :unauthorized)
  end

  test "authenticates with valid token", %{conn: conn, user: user} do
    conn = put_token(conn, user.id)
    conn = authenticate(conn)
    assert AuthenticationPlug.authenticated?(conn)
  end

  test "fails to authenticate with invalid token", %{conn: conn} do
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    conn = put_req_header(conn, "authorization", "Bearer #{token}")
    conn = authenticate(conn)
    refute AuthenticationPlug.authenticated?(conn)
  end

  test "ensures user is authenticated when accessing restricted page", %{conn: conn, user: user} do
    conn = put_token(conn, user.id)
    conn = authenticate(conn)
    conn = AuthenticationPlug.ensure_authenticated(conn, [])
    assert conn.state == :unset
  end

  test "fails to access restricted page when user is not authenticated", %{conn: conn, user: user} do
    conn = put_token(conn, user.id)
    conn = AuthenticationPlug.ensure_authenticated(conn, [])
    assert response(conn, :unauthorized)
  end

  #
  # Helpers
  #

  defp authenticate(conn) do
    AuthenticationPlug.call(conn, [])
  end

  defp put_token(conn, user_id) do
    token = AuthenticationPlug.generate_token(user_id)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
