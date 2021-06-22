defmodule LivebookWeb.HelpersTest do
  use ExUnit.Case, async: true

  alias LivebookWeb.Helpers

  describe "ansi_to_html_lines/1" do
    test "puts every line in its own tag" do
      assert [
               {:safe, ~s{<span style="color: var(--ansi-color-blue);">smiley</span>}},
               {:safe, ~s{<span style="color: var(--ansi-color-blue);">cat</span>}}
             ] ==
               Helpers.ansi_to_html_lines("\e[34msmiley\ncat\e[0m")
    end
  end

  describe "names_to_html_ids/1" do
    test "title case" do
      assert(Helpers.names_to_html_ids(["Title of a Section"]) == ["title-of-a-section"])
    end

    # Contains a couple of unicode spaces to ensure that we handle those
    test "space characters" do
      assert Helpers.names_to_html_ids(["  slug \n   with  spaces \t  "]) == ["slug-with-spaces"]
    end

    test "emoji at end" do
      assert Helpers.names_to_html_ids(["Test 🦦 "]) == ["test-🦦"]
    end

    test "emoji in middle" do
      assert Helpers.names_to_html_ids(["One 🥮 Two"]) == ["one-🥮-two"]
    end

    test "returns empty list for an empty list" do
      assert Helpers.names_to_html_ids([]) == []
    end

    test "returns id-ified strings for different kinds of names" do
      names = [
        "Title of a Section",
        "  something with \n  many  space  characters \t  "
      ]

      assert Helpers.names_to_html_ids(names) == [
               "title-of-a-section",
               "something-with-many-space-characters"
             ]
    end

    test "enumerates ids when they would be the same" do
      names = [
        "Title of a Section",
        "Some other title",
        " Title of a  Section",
        "random",
        " Title of a  section",
        "Title  of a Section "
      ]

      assert Helpers.names_to_html_ids(names) == [
               "title-of-a-section",
               "some-other-title",
               "title-of-a-section-2",
               "random",
               "title-of-a-section-3",
               "title-of-a-section-4"
             ]
    end
  end
end
