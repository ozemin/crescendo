defmodule Crescendo.TestSupport.Payloads do
  @moduledoc """
  Deterministic round payload used as the default `payload_mfa` in test
  config: no database, and the correct answer is always index 0.
  """

  @answer_index 0

  def answer_index, do: @answer_index

  def get_round_payload(_pool_id) do
    {:ok,
     %{
       track: %{
         apple_track_id: 111,
         title: "Correct Song",
         artist_name: "Artist A",
         preview_url: "https://example.com/preview.m4a",
         artwork_url: "https://example.com/artwork.jpg"
       },
       options: [
         %{title: "Correct Song", artist: "Artist A"},
         %{title: "Wrong Song 1", artist: "Artist B"},
         %{title: "Wrong Song 2", artist: "Artist C"},
         %{title: "Wrong Song 3", artist: "Artist D"}
       ],
       answer_index: @answer_index
     }}
  end
end
