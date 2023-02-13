defmodule Livebook.HubsTest do
  use Livebook.DataCase

  alias Livebook.Hubs

  test "get_hubs/0 returns a list of persisted hubs" do
    fly = insert_hub(:fly, id: "fly-baz")
    assert fly in Hubs.get_hubs()

    Hubs.delete_hub("fly-baz")
    refute fly in Hubs.get_hubs()
  end

  test "get_metadata/0 returns a list of persisted hubs normalized" do
    fly = insert_hub(:fly, id: "fly-livebook")
    metadata = Hubs.Provider.to_metadata(fly)

    assert metadata in Hubs.get_metadatas()

    Hubs.delete_hub("fly-livebook")
    refute metadata in Hubs.get_metadatas()
  end

  test "fetch_hub!/1 returns one persisted fly" do
    assert_raise Livebook.Storage.NotFoundError,
                 ~s/could not find entry in \"hubs\" with ID "fly-exception-foo"/,
                 fn ->
                   Hubs.fetch_hub!("fly-exception-foo")
                 end

    fly = insert_hub(:fly, id: "fly-exception-foo")

    assert Hubs.fetch_hub!("fly-exception-foo") == fly
  end

  test "hub_exists?/1" do
    refute Hubs.hub_exists?("fly-bar")
    insert_hub(:fly, id: "fly-bar")
    assert Hubs.hub_exists?("fly-bar")
  end

  test "save_hub/1 persists hub" do
    fly = build(:fly, id: "fly-foo")
    Hubs.save_hub(fly)

    assert Hubs.fetch_hub!("fly-foo") == fly
  end

  test "save_hub/1 updates hub" do
    fly = insert_hub(:fly, id: "fly-foo2")
    Hubs.save_hub(%{fly | hub_emoji: "🐈"})

    refute Hubs.fetch_hub!("fly-foo2") == fly
    assert Hubs.fetch_hub!("fly-foo2").hub_emoji == "🐈"
  end
end
