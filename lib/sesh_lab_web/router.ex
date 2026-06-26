defmodule SeshLabWeb.Router do
  use SeshLabWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SeshLabWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # Tematiza toda página com o accent da edição publicada (CSS var --accent).
    plug SeshLabWeb.Plugs.Accent
  end

  pipeline :admin do
    plug SeshLabWeb.Plugs.BasicAuth
  end

  pipeline :dj_rate_limit do
    plug SeshLabWeb.Plugs.RateLimit, max: 5, window_ms: 3_600_000, bucket: "tocar"
  end

  pipeline :admin_api do
    plug :accepts, ["json"]
    plug SeshLabWeb.Plugs.BasicAuth
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
    get "/comprar", OrderController, :new
    post "/comprar", OrderController, :create
    get "/compra/:id", OrderController, :show
    get "/meus-ingressos", OrderController, :history
    get "/loja", LojaController, :index
    post "/loja", LojaController, :create
    get "/sobre", PageController, :sobre
    get "/avisos", PageController, :avisos
    get "/tocar", DjController, :new
    get "/robots.txt", SeoController, :robots
    get "/sitemap.xml", SeoController, :sitemap
  end

  scope "/", SeshLabWeb do
    pipe_through [:browser, :dj_rate_limit]

    post "/tocar", DjController, :create
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
    live "/edicoes/nova", Admin.EditionFormLive, :new
    live "/edicoes/:id", Admin.EditionFormLive, :edit
    live "/edicoes/:id/cortesia", Admin.CortesiaLive, :index
    live "/pedidos/:id", Admin.OrderShowLive, :show
    live "/buscar", Admin.OrderSearchLive, :index
    live "/validar", Admin.ScannerLive, :index
    live "/validar/:edition_id", Admin.ScannerLive, :index
    live "/tocar", Admin.DjApplicationsLive, :index

    live "/cupons", Admin.CouponsLive, :index
    live "/cupons/novo", Admin.CouponFormLive, :new
    live "/cupons/regras/nova", Admin.CouponRuleFormLive, :new
    live "/cupons/regras/:id", Admin.CouponRuleFormLive, :edit
    live "/cupons/:id", Admin.CouponFormLive, :edit

    live "/produtos", Admin.ProductsLive, :index
    live "/produtos/novo", Admin.ProductFormLive, :new
    live "/produtos/:id", Admin.ProductFormLive, :edit
    live "/balcao", Admin.BalcaoLive, :index
  end

  scope "/admin", SeshLabWeb do
    pipe_through :admin_api

    get "/push/vapid-key", Admin.PushController, :vapid_key
    post "/push/subscribe", Admin.PushController, :subscribe
    delete "/push/subscribe", Admin.PushController, :unsubscribe
  end
end
