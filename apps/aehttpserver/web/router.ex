defmodule Aehttpserver.Router do
  use Aehttpserver.Web, :router

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

  scope "/", Aehttpserver do
    pipe_through :browser # Use the default browser stack
    get "/info", InfoController, :info
    resources "/block", BlockController, param: "hash", only: [:show]
  end


  # Other scopes may use custom stacks.
  # scope "/api", Aehttpserver do
  #   pipe_through :api
  # end
end
