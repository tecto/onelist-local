defmodule Onelist.Repo.Migrations.CreateTriangleChat do
  @moduledoc """
  Creates the Triangle Chat system - unified communication between
  splntrb, Keystone, and Stream.

  PLAN-048: Unified Chat Dashboard
  """
  use Ecto.Migration

  def change do
    # ============================================
    # CHAT CHANNELS
    # ============================================
    create table(:chat_channels, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false           # "group", "dm:key-splntrb", etc.
      add :channel_type, :string, null: false   # "group" or "dm"
      add :participants, {:array, :string}, null: false, default: []
      add :description, :text
      add :last_activity_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:chat_channels, [:channel_type])
    create index(:chat_channels, [:last_activity_at])
    create unique_index(:chat_channels, [:name], name: :chat_channels_unique_name)

    # ============================================
    # CHAT MESSAGES
    # ============================================
    create table(:chat_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel_id, references(:chat_channels, type: :binary_id, on_delete: :delete_all), null: false
      add :sender, :string, null: false         # "splntrb", "key", "stream"
      add :content, :text, null: false
      add :message_type, :string, default: "text"  # "text", "system", "code"
      add :metadata, :map, default: %{}         # For future: attachments, reactions, etc.
      add :is_deleted, :boolean, default: false
      add :edited_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    # CRITICAL: Primary index for fast message retrieval
    # Query: Get messages in channel, ordered by time (most common)
    create index(:chat_messages, [:channel_id, :inserted_at],
      name: :chat_messages_channel_timestamp_idx)

    # Index for non-deleted messages (filtered queries)
    create index(:chat_messages, [:channel_id, :is_deleted, :inserted_at],
      where: "is_deleted = false",
      name: :chat_messages_channel_active_idx)

    # Index for sender queries (e.g., "all messages from key")
    create index(:chat_messages, [:sender, :inserted_at],
      name: :chat_messages_sender_idx)

    # ============================================
    # CHAT READ POSITIONS
    # Session awareness - tracks where each participant last read
    # ============================================
    create table(:chat_read_positions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel_id, references(:chat_channels, type: :binary_id, on_delete: :delete_all), null: false
      add :participant, :string, null: false    # "splntrb", "key", "stream"
      add :last_read_at, :utc_datetime_usec     # Timestamp of last message seen
      add :last_read_message_id, :binary_id     # ID of last message seen (for cursor)

      timestamps(type: :utc_datetime_usec)
    end

    # One read position per participant per channel
    create unique_index(:chat_read_positions, [:channel_id, :participant],
      name: :chat_read_positions_unique_participant)

    create index(:chat_read_positions, [:participant])

    # ============================================
    # SEED INITIAL CHANNELS
    # ============================================
    # This runs as part of migration - creates the 4 Triangle channels
    execute(&seed_channels/0, &drop_channels/0)
  end

  defp seed_channels do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    channels = [
      %{
        id: Ecto.UUID.generate(),
        name: "group",
        channel_type: "group",
        participants: ["splntrb", "key", "stream"],
        description: "The Triangle - main group chat",
        inserted_at: now,
        updated_at: now
      },
      %{
        id: Ecto.UUID.generate(),
        name: "dm:splntrb-key",
        channel_type: "dm",
        participants: ["splntrb", "key"],
        description: "Direct messages: splntrb ↔ Keystone",
        inserted_at: now,
        updated_at: now
      },
      %{
        id: Ecto.UUID.generate(),
        name: "dm:splntrb-stream",
        channel_type: "dm",
        participants: ["splntrb", "stream"],
        description: "Direct messages: splntrb ↔ Stream",
        inserted_at: now,
        updated_at: now
      },
      %{
        id: Ecto.UUID.generate(),
        name: "dm:key-stream",
        channel_type: "dm",
        participants: ["key", "stream"],
        description: "Direct messages: Keystone ↔ Stream",
        inserted_at: now,
        updated_at: now
      }
    ]

    for channel <- channels do
      """
      INSERT INTO chat_channels (id, name, channel_type, participants, description, inserted_at, updated_at)
      VALUES (
        '#{channel.id}',
        '#{channel.name}',
        '#{channel.channel_type}',
        ARRAY['#{Enum.join(channel.participants, "','")}'],
        '#{channel.description}',
        '#{channel.inserted_at}',
        '#{channel.updated_at}'
      );
      """
    end
    |> Enum.join("\n")
  end

  defp drop_channels do
    "DELETE FROM chat_channels WHERE name IN ('group', 'dm:splntrb-key', 'dm:splntrb-stream', 'dm:key-stream');"
  end
end
