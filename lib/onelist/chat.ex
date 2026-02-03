defmodule Onelist.Chat do
  @moduledoc """
  The Triangle Chat system - unified communication between splntrb, Keystone, and Stream.

  ## Simple API for Stream (internal calls)

      # Send to group
      Onelist.Chat.send_message(:group, "stream", "Hello from Stream")

      # Send to DM
      Onelist.Chat.send_message(:dm_key_stream, "stream", "Hey Key")

      # Get unread messages
      Onelist.Chat.get_unread(:dm_key_stream, "stream")

      # Mark as read
      Onelist.Chat.mark_read(:dm_key_stream, "stream", message_id)

  ## Channel Names

  - `:group` or `"group"` - All three participants
  - `:dm_splntrb_key` or `"dm:splntrb-key"` - splntrb ↔ Keystone
  - `:dm_splntrb_stream` or `"dm:splntrb-stream"` - splntrb ↔ Stream
  - `:dm_key_stream` or `"dm:key-stream"` - Keystone ↔ Stream

  PLAN-048: Unified Chat Dashboard
  """

  import Ecto.Query
  alias Onelist.Repo
  alias Onelist.Chat.{Channel, Message, ReadPosition}

  # ============================================
  # CHANNEL NAME MAPPING
  # ============================================

  @channel_atoms %{
    group: "group",
    dm_splntrb_key: "dm:splntrb-key",
    dm_splntrb_stream: "dm:splntrb-stream",
    dm_key_stream: "dm:key-stream"
  }

  defp normalize_channel(channel) when is_atom(channel) do
    Map.get(@channel_atoms, channel, to_string(channel))
  end
  defp normalize_channel(channel) when is_binary(channel), do: channel

  # ============================================
  # SEND MESSAGE
  # ============================================

  @doc """
  Send a message to a channel.

  ## Examples

      iex> Onelist.Chat.send_message(:group, "stream", "Hello everyone!")
      {:ok, %Message{}}

      iex> Onelist.Chat.send_message("dm:key-stream", "key", "Hey Stream")
      {:ok, %Message{}}
  """
  def send_message(channel, sender, content, opts \\ []) do
    channel_name = normalize_channel(channel)
    message_type = Keyword.get(opts, :type, "text")
    metadata = Keyword.get(opts, :metadata, %{})

    with {:ok, channel_record} <- get_channel(channel_name),
         :ok <- validate_sender_in_channel(channel_record, sender),
         {:ok, message} <- create_message(channel_record, sender, content, message_type, metadata) do
      # Update channel's last activity
      update_channel_activity(channel_record)

      # Broadcast to PubSub
      broadcast_message(channel_name, message)

      {:ok, message}
    end
  end

  defp create_message(channel, sender, content, message_type, metadata) do
    %Message{}
    |> Message.changeset(%{
      channel_id: channel.id,
      sender: sender,
      content: content,
      message_type: message_type,
      metadata: metadata
    })
    |> Repo.insert()
  end

  defp validate_sender_in_channel(channel, sender) do
    if sender in channel.participants do
      :ok
    else
      {:error, :sender_not_in_channel}
    end
  end

  defp update_channel_activity(channel) do
    channel
    |> Channel.changeset(%{last_activity_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)})
    |> Repo.update()
  end

  # ============================================
  # GET MESSAGES
  # ============================================

  @doc """
  Get messages from a channel.

  ## Options

  - `:limit` - Max messages to return (default: 50)
  - `:since` - Only messages after this timestamp
  - `:before` - Only messages before this timestamp (for pagination)
  - `:include_deleted` - Include soft-deleted messages (default: false)

  ## Examples

      iex> Onelist.Chat.get_messages(:group)
      [%Message{}, ...]

      iex> Onelist.Chat.get_messages(:dm_key_stream, since: ~U[2026-02-03 19:00:00Z])
      [%Message{}, ...]
  """
  def get_messages(channel, opts \\ []) do
    channel_name = normalize_channel(channel)
    limit = Keyword.get(opts, :limit, 50)
    since = Keyword.get(opts, :since)
    before_ts = Keyword.get(opts, :before)
    include_deleted = Keyword.get(opts, :include_deleted, false)

    case get_channel(channel_name) do
      {:ok, channel_record} ->
        query =
          Message
          |> where(channel_id: ^channel_record.id)
          |> maybe_filter_deleted(include_deleted)
          |> maybe_filter_since(since)
          |> maybe_filter_before(before_ts)
          |> order_by(desc: :inserted_at)
          |> limit(^limit)

        messages = Repo.all(query) |> Enum.reverse()
        {:ok, messages}

      error -> error
    end
  end

  defp maybe_filter_deleted(query, true), do: query
  defp maybe_filter_deleted(query, false), do: where(query, is_deleted: false)

  defp maybe_filter_since(query, nil), do: query
  defp maybe_filter_since(query, since), do: where(query, [m], m.inserted_at > ^since)

  defp maybe_filter_before(query, nil), do: query
  defp maybe_filter_before(query, before_ts), do: where(query, [m], m.inserted_at < ^before_ts)

  # ============================================
  # UNREAD MESSAGES (Session Awareness)
  # ============================================

  @doc """
  Get unread messages for a participant in a channel.

  Returns messages that arrived after the participant's last read position.

  ## Examples

      iex> Onelist.Chat.get_unread(:dm_key_stream, "stream")
      [%Message{}, ...]
  """
  def get_unread(channel, participant) do
    channel_name = normalize_channel(channel)

    with {:ok, channel_record} <- get_channel(channel_name),
         {:ok, read_position} <- get_or_create_read_position(channel_record, participant) do
      query =
        Message
        |> where(channel_id: ^channel_record.id)
        |> where(is_deleted: false)
        |> maybe_filter_since(read_position.last_read_at)
        |> order_by(asc: :inserted_at)

      {:ok, Repo.all(query)}
    end
  end

  @doc """
  Get unread count for a participant in a channel.
  """
  def unread_count(channel, participant) do
    channel_name = normalize_channel(channel)

    with {:ok, channel_record} <- get_channel(channel_name),
         {:ok, read_position} <- get_or_create_read_position(channel_record, participant) do
      query =
        Message
        |> where(channel_id: ^channel_record.id)
        |> where(is_deleted: false)
        |> maybe_filter_since(read_position.last_read_at)

      {:ok, Repo.aggregate(query, :count)}
    end
  end

  # ============================================
  # MARK AS READ
  # ============================================

  @doc """
  Mark messages as read up to a specific message or timestamp.

  ## Examples

      iex> Onelist.Chat.mark_read(:dm_key_stream, "stream", message_id)
      :ok

      iex> Onelist.Chat.mark_read(:dm_key_stream, "stream")  # Mark all as read
      :ok
  """
  def mark_read(channel, participant, message_id \\ nil) do
    channel_name = normalize_channel(channel)

    with {:ok, channel_record} <- get_channel(channel_name),
         {:ok, read_position} <- get_or_create_read_position(channel_record, participant) do
      update_attrs =
        if message_id do
          message = Repo.get(Message, message_id)
          %{last_read_at: message.inserted_at, last_read_message_id: message.id}
        else
          # Mark all as read - use current time
          %{last_read_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)}
        end

      read_position
      |> ReadPosition.changeset(update_attrs)
      |> Repo.update()

      :ok
    end
  end

  # ============================================
  # CHANNEL HELPERS
  # ============================================

  @doc """
  Get a channel by name.
  """
  def get_channel(channel_name) do
    case Repo.get_by(Channel, name: channel_name) do
      nil -> {:error, :channel_not_found}
      channel -> {:ok, channel}
    end
  end

  @doc """
  List all channels.
  """
  def list_channels do
    Channel
    |> order_by(asc: :name)
    |> Repo.all()
  end

  @doc """
  List channels for a participant.
  """
  def list_channels_for(participant) do
    Channel
    |> where([c], ^participant in c.participants)
    |> order_by(desc: :last_activity_at)
    |> Repo.all()
  end

  # ============================================
  # READ POSITION HELPERS
  # ============================================

  defp get_or_create_read_position(channel, participant) do
    case Repo.get_by(ReadPosition, channel_id: channel.id, participant: participant) do
      nil ->
        %ReadPosition{}
        |> ReadPosition.changeset(%{channel_id: channel.id, participant: participant})
        |> Repo.insert()

      read_position ->
        {:ok, read_position}
    end
  end

  @doc """
  Get read positions for all channels for a participant.
  Returns a map of channel_name => last_read_at.
  """
  def get_read_positions(participant) do
    ReadPosition
    |> where(participant: ^participant)
    |> join(:inner, [rp], c in Channel, on: rp.channel_id == c.id)
    |> select([rp, c], {c.name, rp.last_read_at})
    |> Repo.all()
    |> Map.new()
  end

  # ============================================
  # PUBSUB
  # ============================================

  @pubsub Onelist.PubSub

  @doc """
  Subscribe to a channel's messages.
  """
  def subscribe(channel) do
    channel_name = normalize_channel(channel)
    Phoenix.PubSub.subscribe(@pubsub, "chat:#{channel_name}")
  end

  @doc """
  Unsubscribe from a channel.
  """
  def unsubscribe(channel) do
    channel_name = normalize_channel(channel)
    Phoenix.PubSub.unsubscribe(@pubsub, "chat:#{channel_name}")
  end

  defp broadcast_message(channel_name, message) do
    Phoenix.PubSub.broadcast(@pubsub, "chat:#{channel_name}", {:new_message, message})
  end

  @doc """
  Broadcast a system message (e.g., "Stream came online").
  """
  def broadcast_system(channel, content) do
    send_message(channel, "system", content, type: "system")
  end
end
