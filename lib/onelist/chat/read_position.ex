defmodule Onelist.Chat.ReadPosition do
  @moduledoc """
  Tracks where each participant last read in each channel.

  This enables session awareness - Stream can see which messages
  in the Key↔Stream DM are new since her last session.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_participants ["splntrb", "key", "stream"]

  schema "chat_read_positions" do
    field :participant, :string
    field :last_read_at, :utc_datetime_usec
    field :last_read_message_id, :binary_id

    belongs_to :channel, Onelist.Chat.Channel

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(read_position, attrs) do
    read_position
    |> cast(attrs, [:channel_id, :participant, :last_read_at, :last_read_message_id])
    |> validate_required([:channel_id, :participant])
    |> validate_inclusion(:participant, @valid_participants)
    |> unique_constraint([:channel_id, :participant], name: :chat_read_positions_unique_participant)
    |> foreign_key_constraint(:channel_id)
  end

  def update_changeset(read_position, message) do
    read_position
    |> change(%{
      last_read_at: message.inserted_at,
      last_read_message_id: message.id
    })
  end
end
