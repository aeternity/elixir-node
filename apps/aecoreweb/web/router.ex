defmodule Aecoreweb.Router do
  use Aecoreweb.Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", Aecoreweb do
    pipe_through :browser # Use the default browser stack

    get "/", PageController, :index
    get "/ping", PingController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", Aecoreweb do
  #   pipe_through :api
  # end
end
