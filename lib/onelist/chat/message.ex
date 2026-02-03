defmodule Onelist.Chat.Message do
  @moduledoc """
  Schema for chat messages in the Triangle communication system.

  Messages are eternal - never deleted, only soft-deleted.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_senders ["splntrb", "key", "stream"]
  @valid_message_types ["text", "system", "code"]

  schema "chat_messages" do
    field :sender, :string
    field :content, :string
    field :message_type, :string, default: "text"
    field :metadata, :map, default: %{}
    field :is_deleted, :boolean, default: false
    field :edited_at, :utc_datetime_usec

    belongs_to :channel, Onelist.Chat.Channel

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:channel_id, :sender, :content, :message_type, :metadata])
    |> validate_required([:channel_id, :sender, :content])
    |> validate_inclusion(:sender, @valid_senders)
    |> validate_inclusion(:message_type, @valid_message_types)
    |> validate_length(:content, min: 1, max: 50_000)
    |> foreign_key_constraint(:channel_id)
  end

  def edit_changeset(message, attrs) do
    message
    |> cast(attrs, [:content])
    |> validate_required([:content])
    |> validate_length(:content, min: 1, max: 50_000)
    |> put_change(:edited_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
  end

  def delete_changeset(message) do
    change(message, %{is_deleted: true})
  end
end
