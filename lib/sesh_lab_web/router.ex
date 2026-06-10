defmodule SeshLabWeb.Router do
  use SeshLabWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SeshLabWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :admin do
    plug SeshLabWeb.Plugs.BasicAuth
  end

  pipeline :admin_api do
    plug :accepts, ["json"]
    plug SeshLabWeb.Plugs.BasicAuth
  end

  pipeline :client_stream do
    plug :accepts, ["sse"]
    plug :fetch_session
    plug :protect_from_forgery
  end

  # Public JSON for customer push. Keeps CSRF protection (browser sends the
  # x-csrf-token header), unlike :admin_api which relies on Basic auth instead.
  pipeline :client_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
  end

  scope "/", SeshLabWeb do
    pipe_through :browser

    get "/", PageController, :index
    get "/pedido", OrderController, :new
    post "/pedido", OrderController, :create
    get "/meus-pedidos", OrderController, :history
    get "/avisos", PageController, :avisos
    get "/pedido/:id", OrderController, :show
  end

  scope "/", SeshLabWeb do
    pipe_through :client_stream

    get "/vitrine/stream", PageController, :stock_stream
  end

  scope "/", SeshLabWeb do
    pipe_through :client_api

    get "/push/vapid-key", PushController, :vapid_key
    get "/push/subscribe", PushController, :show
    post "/push/subscribe", PushController, :subscribe
    patch "/push/subscribe", PushController, :update
    delete "/push/subscribe", PushController, :unsubscribe
  end

  scope "/admin", SeshLabWeb do
    pipe_through [:browser, :admin]

    live "/", Admin.DashboardLive, :index
    live "/produtos/novo", Admin.ProductFormLive, :new
    live "/produtos/:id", Admin.ProductFormLive, :edit
    live "/promos/novo", Admin.PromoFormLive, :new
    live "/promos/:id", Admin.PromoFormLive, :edit
    live "/pedidos/:id", Admin.OrderShowLive, :show

    live "/cupons", Admin.CouponsLive, :index
    live "/cupons/novo", Admin.CouponFormLive, :new
    live "/cupons/regras/nova", Admin.CouponRuleFormLive, :new
    live "/cupons/regras/:id", Admin.CouponRuleFormLive, :edit
    live "/cupons/:id", Admin.CouponFormLive, :edit
  end

  scope "/admin", SeshLabWeb do
    pipe_through :admin_api

    get "/push/vapid-key", Admin.PushController, :vapid_key
    post "/push/subscribe", Admin.PushController, :subscribe
    delete "/push/subscribe", Admin.PushController, :unsubscribe
  end
end
