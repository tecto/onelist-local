defmodule OnelistWeb.Watch.SwarmLive do
  @moduledoc """
  Swarm file browser LiveView - browse Claude Code Swarm content.

  PLAN-051: Phoenix Auth Migration
  """
  use OnelistWeb, :live_view

  @swarm_root "/root/.openclaw/workspace/stream.onelist.my/claude_code_swarm"

  def mount(params, _session, socket) do
    path = get_path_from_params(params)

    socket =
      socket
      |> assign(:swarm_root, @swarm_root)
      |> load_content(path)

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    path = get_path_from_params(params)
    {:noreply, load_content(socket, path)}
  end

  defp get_path_from_params(%{"path" => path_parts}) when is_list(path_parts) do
    Path.join(path_parts)
  end
  defp get_path_from_params(%{"path" => path}) when is_binary(path), do: path
  defp get_path_from_params(_), do: nil

  defp load_content(socket, nil) do
    files = list_swarm_files()
    socket
    |> assign(:view_mode, :index)
    |> assign(:path, nil)
    |> assign(:files, files)
    |> assign(:content, nil)
    |> assign(:breadcrumbs, [])
  end

  defp load_content(socket, path) do
    full_path = Path.join(@swarm_root, path)

    cond do
      File.dir?(full_path) ->
        files = list_directory(path)
        socket
        |> assign(:view_mode, :directory)
        |> assign(:path, path)
        |> assign(:files, files)
        |> assign(:content, nil)
        |> assign(:breadcrumbs, build_breadcrumbs(path))

      File.exists?(full_path) && String.ends_with?(path, ".md") ->
        content = File.read!(full_path)
        socket
        |> assign(:view_mode, :markdown)
        |> assign(:path, path)
        |> assign(:files, [])
        |> assign(:content, render_markdown(content))
        |> assign(:breadcrumbs, build_breadcrumbs(path))

      File.exists?(full_path) ->
        socket
        |> assign(:view_mode, :file)
        |> assign(:path, path)
        |> assign(:files, [])
        |> assign(:content, nil)
        |> assign(:breadcrumbs, build_breadcrumbs(path))

      true ->
        socket
        |> assign(:view_mode, :not_found)
        |> assign(:path, path)
        |> assign(:files, [])
        |> assign(:content, nil)
        |> assign(:breadcrumbs, [])
    end
  end

  defp list_swarm_files do
    if File.dir?(@swarm_root) do
      File.ls!(@swarm_root)
      |> Enum.map(fn name ->
        full_path = Path.join(@swarm_root, name)

        cond do
          File.dir?(full_path) ->
            {:dir, name, count_files(full_path)}

          File.exists?(full_path) ->
            {:file, name, File.stat!(full_path).size}

          true ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn
        {:dir, name, _} -> {0, name}
        {:file, name, _} -> {1, name}
      end)
    else
      []
    end
  end

  defp list_directory(dir_path) do
    full_path = Path.join(@swarm_root, dir_path)

    if File.dir?(full_path) do
      File.ls!(full_path)
      |> Enum.map(fn name ->
        item_path = Path.join(full_path, name)
        rel_path = Path.join(dir_path, name)

        if File.dir?(item_path) do
          {:dir, name, rel_path}
        else
          {:file, name, rel_path, File.stat!(item_path).size}
        end
      end)
      |> Enum.sort_by(fn
        {:dir, name, _} -> {0, name}
        {:file, name, _, _} -> {1, name}
      end)
    else
      []
    end
  end

  defp count_files(dir_path) do
    case File.ls(dir_path) do
      {:ok, files} -> length(files)
      _ -> 0
    end
  end

  defp build_breadcrumbs(path) do
    parts = String.split(path, "/")

    parts
    |> Enum.with_index()
    |> Enum.map(fn {part, idx} ->
      href = Enum.take(parts, idx + 1) |> Enum.join("/")
      is_last = idx == length(parts) - 1
      {part, href, is_last}
    end)
  end

  defp render_markdown(content) do
    content
    |> String.replace(~r/^### (.+)$/m, "<h3>\\1</h3>")
    |> String.replace(~r/^## (.+)$/m, "<h2>\\1</h2>")
    |> String.replace(~r/^# (.+)$/m, "<h1>\\1</h1>")
    |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/\*(.+?)\*/, "<em>\\1</em>")
    |> String.replace(~r/`([^`]+)`/, "<code>\\1</code>")
    |> String.replace(~r/^- (.+)$/m, "<li>\\1</li>")
    |> String.replace(~r/^(\d+)\. (.+)$/m, "<li>\\2</li>")
    |> String.replace(~r/```(\w*)\n([\s\S]*?)```/m, "<pre><code>\\2</code></pre>")
    |> String.replace(~r/\n\n/, "</p><p>")
    |> then(fn s -> "<p>#{s}</p>" end)
    |> Phoenix.HTML.raw()
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"

  def render(assigns) do
    ~H"""
    <div class="swarm">
      <style>
        :root {
          --bg: #0a0a0a;
          --card-bg: #141414;
          --border: #2a2a2a;
          --text: #e0e0e0;
          --text-muted: #888;
          --accent: #f59e0b;
        }
        .swarm {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: var(--bg);
          color: var(--text);
          line-height: 1.6;
          padding: 2rem;
          max-width: 900px;
          margin: 0 auto;
          min-height: 100vh;
        }
        .swarm h1 { margin-bottom: 0.5rem; }
        .subtitle { color: var(--text-muted); margin-bottom: 2rem; }
        .subtitle a { color: var(--accent); }
        .breadcrumbs {
          margin-bottom: 1rem;
          color: var(--text-muted);
          font-size: 0.9rem;
        }
        .breadcrumbs a { color: var(--accent); text-decoration: none; }
        .breadcrumbs a:hover { text-decoration: underline; }
        .file-list {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
        }
        .item {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.75rem 1rem;
          background: var(--card-bg);
          border: 1px solid var(--border);
          border-radius: 8px;
          text-decoration: none;
          color: var(--text);
          transition: border-color 0.2s;
        }
        .item:hover { border-color: var(--accent); }
        .item .icon { font-size: 1.2rem; }
        .item .name { flex: 1; }
        .item .meta { color: var(--text-muted); font-size: 0.85rem; }
        .toolbar { margin-bottom: 1rem; }
        .btn {
          display: inline-block;
          padding: 0.5rem 1rem;
          background: var(--card-bg);
          border: 1px solid var(--border);
          border-radius: 6px;
          color: var(--accent);
          text-decoration: none;
        }
        .btn:hover { border-color: var(--accent); }
        .markdown {
          background: var(--card-bg);
          padding: 2rem;
          border-radius: 8px;
          border: 1px solid var(--border);
        }
        .markdown h1, .markdown h2, .markdown h3 {
          margin-top: 1.5rem;
          margin-bottom: 0.75rem;
        }
        .markdown h1:first-child { margin-top: 0; }
        .markdown p { margin-bottom: 1rem; }
        .markdown code {
          background: var(--bg);
          padding: 0.15rem 0.4rem;
          border-radius: 4px;
          font-family: 'SF Mono', Monaco, monospace;
          font-size: 0.9em;
        }
        .markdown pre {
          background: var(--bg);
          padding: 1rem;
          border-radius: 6px;
          overflow-x: auto;
          margin: 1rem 0;
        }
        .markdown pre code { background: none; padding: 0; }
        .markdown li { margin-left: 1.5rem; margin-bottom: 0.25rem; }
        .markdown strong { color: #fff; }
        .error-page { text-align: center; padding: 4rem 2rem; }
        .error-page h1 { font-size: 3rem; margin-bottom: 1rem; }
      </style>

      <%= case @view_mode do %>
        <% :index -> %>
          <h1>Claude Code Swarm</h1>
          <p class="subtitle">Multi-agent coordination framework. <a href="/watch">← Back to Watch</a></p>
          <div class="file-list">
            <%= for file <- @files do %>
              <%= case file do %>
                <% {:dir, path, count} -> %>
                  <.link navigate={~p"/watch/swarm/#{path}"} class="item dir">
                    <span class="icon">📁</span>
                    <span class="name"><%= path %>/</span>
                    <span class="meta"><%= count %> items</span>
                  </.link>
                <% {:file, path, size} -> %>
                  <.link navigate={~p"/watch/swarm/#{path}"} class="item file">
                    <span class="icon">📄</span>
                    <span class="name"><%= path %></span>
                    <span class="meta"><%= format_size(size) %></span>
                  </.link>
              <% end %>
            <% end %>
          </div>

        <% :directory -> %>
          <nav class="breadcrumbs">
            <.link navigate={~p"/watch/swarm"}>swarm</.link>
            <%= for {part, href, is_last} <- @breadcrumbs do %>
              / <%= if is_last do %>
                <span><%= part %></span>
              <% else %>
                <.link navigate={~p"/watch/swarm/#{href}"}><%= part %></.link>
              <% end %>
            <% end %>
          </nav>
          <h1>📁 <%= @path %></h1>
          <div class="file-list">
            <%= for file <- @files do %>
              <%= case file do %>
                <% {:dir, name, rel_path} -> %>
                  <.link navigate={~p"/watch/swarm/#{rel_path}"} class="item dir">
                    <span class="icon">📁</span>
                    <span class="name"><%= name %>/</span>
                  </.link>
                <% {:file, name, rel_path, size} -> %>
                  <.link navigate={~p"/watch/swarm/#{rel_path}"} class="item file">
                    <span class="icon"><%= if String.ends_with?(name, ".md"), do: "📝", else: "📄" %></span>
                    <span class="name"><%= name %></span>
                    <span class="meta"><%= format_size(size) %></span>
                  </.link>
              <% end %>
            <% end %>
          </div>

        <% :markdown -> %>
          <nav class="breadcrumbs">
            <.link navigate={~p"/watch/swarm"}>swarm</.link>
            <%= for {part, href, is_last} <- @breadcrumbs do %>
              / <%= if is_last do %>
                <span><%= part %></span>
              <% else %>
                <.link navigate={~p"/watch/swarm/#{href}"}><%= part %></.link>
              <% end %>
            <% end %>
          </nav>
          <div class="toolbar">
            <a href={"/swarm/raw/#{@path}"} class="btn">⬇ Download Markdown</a>
          </div>
          <article class="markdown">
            <%= @content %>
          </article>

        <% :not_found -> %>
          <div class="error-page">
            <h1>404</h1>
            <p>The path <code><%= @path %></code> does not exist.</p>
            <.link navigate={~p"/watch/swarm"}>← Back to Swarm</.link>
          </div>

        <% _ -> %>
          <p>Unknown view mode</p>
      <% end %>
    </div>
    """
  end
end
