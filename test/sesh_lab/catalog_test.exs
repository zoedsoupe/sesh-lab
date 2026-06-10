defmodule SeshLab.CatalogTest do
  use SeshLab.DataCase, async: false

  alias SeshLab.Catalog
  alias SeshLab.Catalog.Product

  defp insert(attrs) do
    defaults = %{
      name: "Brownie",
      unit_label: "un",
      unit_price_cents: 1000,
      stock: 5,
      is_active: true,
      is_preorder: false
    }

    %Product{}
    |> Product.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "list_active_products/0" do
    test "returns only active rows, ordered by id" do
      insert(%{id: "c", name: "C"})
      insert(%{id: "a", name: "A"})
      insert(%{id: "b", name: "B", is_active: false})

      ids = Catalog.list_active_products() |> Enum.map(& &1.id)
      assert ids == ["a", "c"]
    end
  end

  describe "list_active_partitioned/0" do
    test "splits pronta entrega from preorder, preserves order" do
      insert(%{id: "brownie", name: "Brownie", stock: 2})
      insert(%{id: "encomenda", name: "Encomenda", is_preorder: true, lead_time_days: 3})
      insert(%{id: "coracao", name: "Coração", stock: 1})

      {pronta, encomenda} = Catalog.list_active_partitioned()
      assert Enum.map(pronta, & &1.id) == ["brownie", "coracao"]
      assert Enum.map(encomenda, & &1.id) == ["encomenda"]
    end
  end

  describe "list_all_products/0" do
    test "includes inactive rows" do
      insert(%{id: "a", name: "A"})
      insert(%{id: "b", name: "B", is_active: false})

      ids = Catalog.list_all_products() |> Enum.map(& &1.id)
      assert ids == ["a", "b"]
    end
  end

  describe "get_product!/1" do
    test "returns the product by id" do
      insert(%{id: "brownie", name: "Brownie"})
      assert %Product{name: "Brownie"} = Catalog.get_product!("brownie")
    end

    test "raises when missing" do
      assert_raise Ecto.NoResultsError, fn -> Catalog.get_product!("missing") end
    end
  end

  describe "update_product/2" do
    test "updates allowed fields" do
      p = insert(%{id: "brownie", name: "Brownie"})
      assert {:ok, updated} = Catalog.update_product(p, %{stock: 99, name: "Brownie Novo"})
      assert updated.stock == 99
      assert updated.name == "Brownie Novo"
    end

    test "validates positive price" do
      p = insert(%{id: "brownie", name: "Brownie"})
      assert {:error, cs} = Catalog.update_product(p, %{unit_price_cents: 0})
      assert "must be greater than 0" in errors_on(cs).unit_price_cents
    end
  end

  describe "set_stock/2" do
    test "overwrites stock value" do
      insert(%{id: "brownie", name: "Brownie", stock: 1})
      assert :ok = Catalog.set_stock("brownie", 25)
      assert Catalog.get_product!("brownie").stock == 25
    end

    test "rejects negative quantity at the guard" do
      assert_raise FunctionClauseError, fn -> Catalog.set_stock("brownie", -1) end
    end
  end

  describe "create_product/1 + delete_product/1" do
    test "round-trip" do
      attrs = %{
        id: "new",
        name: "Novo",
        unit_label: "un",
        unit_price_cents: 500
      }

      assert {:ok, p} = Catalog.create_product(attrs)
      assert {:ok, _} = Catalog.delete_product(p)
      assert_raise Ecto.NoResultsError, fn -> Catalog.get_product!("new") end
    end
  end

  describe "photo_url/1" do
    test "nil → nil; otherwise prefixed with uploads path" do
      assert Catalog.photo_url(nil) == nil
      assert Catalog.photo_url("brownie.jpg") == "/uploads/products/brownie.jpg"
    end
  end
end
