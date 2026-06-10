defmodule SeshLab.Notifications.PushSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  # Categories a client device can opt into. Admin subs ignore this.
  @topics ~w(order_status promos coupons)
  def topics, do: @topics

  schema "push_subscriptions" do
    field :endpoint, :string
    field :p256dh, :string
    field :auth, :string
    field :user_agent, :string
    field :audience, Ecto.Enum, values: [:admin, :client], default: :admin
    field :topics, {:array, :string}, default: []

    timestamps()
  end

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, ~w(endpoint p256dh auth user_agent audience topics)a)
    |> validate_required(~w(endpoint p256dh auth audience)a)
    |> validate_subset(:topics, @topics)
    |> unique_constraint(:endpoint)
  end
end
