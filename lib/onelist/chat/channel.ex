defmodule Onelist.Chat.Channel do
  @moduledoc """
  Schema for chat channels in the Triangle communication system.

  Channels:
  - group: All three participants (splntrb, key, stream)
  - dm:splntrb-key: Direct messages between splntrb and Keystone
  - dm:splntrb-stream: Direct messages between splntrb and Stream
  - dm:key-stream: Direct messages between Keystone and Stream
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_participants ["splntrb", "key", "stream"]
  @valid_channel_types ["group", "dm"]

  schema "chat_channels" do
    field :name, :string
    field :channel_type, :string
    field :participants, {:array, :string}, default: []
    field :description, :string
    field :last_activity_at, :utc_datetime_usec

    has_many :messages, Onelist.Chat.Message
    has_many :read_positions, Onelist.Chat.ReadPosition

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :channel_type, :participants, :description, :last_activity_at])
    |> validate_required([:name, :channel_type, :participants])
    |> validate_inclusion(:channel_type, @valid_channel_types)
    |> validate_participants()
    |> unique_constraint(:name, name: :chat_channels_unique_name)
  end

  defp validate_participants(changeset) do
    case get_change(changeset, :participants) do
      nil -> changeset
      participants ->
        if Enum.all?(participants, &(&1 in @valid_participants)) do
          changeset
        else
          add_error(changeset, :participants, "must be valid participants: #{inspect(@valid_participants)}")
        end
    end
  end

  # Channel name helpers
  def group_channel_name, do: "group"
  def dm_channel_name(p1, p2) when p1 < p2, do: "dm:#{p1}-#{p2}"
  def dm_channel_name(p1, p2), do: "dm:#{p2}-#{p1}"
end
