defmodule OnelistWeb.SwarmController do
  use OnelistWeb, :controller

  @swarm_root "/root/.openclaw/workspace/stream.onelist.my/claude_code_swarm"

  defp normalize_path(path) when is_list(path), do: Path.join(path)
  defp normalize_path(path) when is_binary(path), do: path

  def index(conn, _params) do
    files = list_swarm_files()
    html = render_index(files)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  def show(conn, %{"path" => path_parts}) do
    path = normalize_path(path_parts)
    full_path = Path.join(@swarm_root, path)

    cond do
      File.dir?(full_path) ->
        files = list_directory(path)
        html = render_directory(path, files)
        conn |> put_resp_content_type("text/html") |> send_resp(200, html)

      File.exists?(full_path) && String.ends_with?(path, ".md") ->
        content = File.read!(full_path)
        html = render_markdown(path, content)
        conn |> put_resp_content_type("text/html") |> send_resp(200, html)

      File.exists?(full_path) ->
        send_file(conn, 200, full_path)

      true ->
        conn |> put_resp_content_type("text/html") |> send_resp(404, render_404(path))
    end
  end

  def raw(conn, %{"path" => path_parts}) do
    path = normalize_path(path_parts)
    full_path = Path.join(@swarm_root, path)

    if File.exists?(full_path) && !File.dir?(full_path) do
      conn
      |> put_resp_content_type("text/plain; charset=utf-8")
      |> put_resp_header(
        "content-disposition",
        "attachment; filename=\"#{Path.basename(path)}\""
      )
      |> send_file(200, full_path)
    else
      conn |> send_resp(404, "Not found")
    end
  end

  def changelog(conn, _params) do
    changelog_dir = Path.join(@swarm_root, "change_log")

    files =
      if File.dir?(changelog_dir) do
        File.ls!(changelog_dir)
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.sort(:desc)
        |> Enum.take(50)
      else
        []
      end

    html = render_changelog(files)
    conn |> put_resp_content_type("text/html") |> send_resp(200, html)
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

  defp render_index(files) do
    file_items =
      Enum.map(files, fn
        {:dir, path, count} ->
          """
          <a href="/swarm/#{path}" class="item dir">
            <span class="icon">📁</span>
            <span class="name">#{path}/</span>
            <span class="meta">#{count} items</span>
          </a>
          """

        {:file, path, size} ->
          """
          <a href="/swarm/#{path}" class="item file">
            <span class="icon">📄</span>
            <span class="name">#{path}</span>
            <span class="meta">#{format_size(size)}</span>
            <a href="/swarm/raw/#{path}" class="download" title="Download">⬇</a>
          </a>
          """
      end)
      |> Enum.join("\n")

    base_html("Claude Code Swarm", """
    <h1>🐝 Claude Code Swarm</h1>
    <p class="subtitle">Multi-agent coordination framework. <a href="/swarm/changelog">View Changelog →</a></p>
    <div class="file-list">
      #{file_items}
    </div>
    """)
  end

  defp render_directory(path, files) do
    file_items =
      Enum.map(files, fn
        {:dir, name, rel_path} ->
          """
          <a href="/swarm/#{rel_path}" class="item dir">
            <span class="icon">📁</span>
            <span class="name">#{name}/</span>
          </a>
          """

        {:file, name, rel_path, size} ->
          icon = if String.ends_with?(name, ".md"), do: "📝", else: "📄"

          """
          <a href="/swarm/#{rel_path}" class="item file">
            <span class="icon">#{icon}</span>
            <span class="name">#{name}</span>
            <span class="meta">#{format_size(size)}</span>
            <a href="/swarm/raw/#{rel_path}" class="download" title="Download">⬇</a>
          </a>
          """
      end)
      |> Enum.join("\n")

    breadcrumbs = render_breadcrumbs(path)

    base_html(path, """
    #{breadcrumbs}
    <h1>📁 #{path}</h1>
    <div class="file-list">
      #{file_items}
    </div>
    """)
  end

  defp render_markdown(path, content) do
    html_content =
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

    breadcrumbs = render_breadcrumbs(path)

    base_html(Path.basename(path), """
    #{breadcrumbs}
    <div class="toolbar">
      <a href="/swarm/raw/#{path}" class="btn">⬇ Download Markdown</a>
    </div>
    <article class="markdown">
      #{html_content}
    </article>
    """)
  end

  defp render_changelog(files) do
    file_items =
      Enum.map(files, fn name ->
        """
        <a href="/swarm/change_log/#{name}" class="item file">
          <span class="icon">📋</span>
          <span class="name">#{name}</span>
        </a>
        """
      end)
      |> Enum.join("\n")

    base_html("Changelog", """
    <h1>📋 Swarm Changelog</h1>
    <p class="subtitle">Recent changes to the swarm. <a href="/swarm">← Back to Swarm</a></p>
    <div class="file-list">
      #{file_items}
    </div>
    """)
  end

  defp render_breadcrumbs(path) when is_list(path), do: render_breadcrumbs(Path.join(path))

  defp render_breadcrumbs(path) when is_binary(path) do
    parts = String.split(path, "/")

    crumbs =
      parts
      |> Enum.with_index()
      |> Enum.map(fn {part, idx} ->
        href = "/swarm/" <> (Enum.take(parts, idx + 1) |> Enum.join("/"))

        if idx == length(parts) - 1 do
          "<span>#{part}</span>"
        else
          "<a href=\"#{href}\">#{part}</a>"
        end
      end)
      |> Enum.join(" / ")

    """
    <nav class="breadcrumbs">
      <a href="/swarm">swarm</a> / #{crumbs}
    </nav>
    """
  end

  defp render_404(path) do
    base_html("Not Found", """
    <h1>404 - Not Found</h1>
    <p>The path <code>#{path}</code> does not exist.</p>
    <a href="/swarm">← Back to Swarm</a>
    """)
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"

  defp base_html(title, content) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{title} - Swarm</title>
      <style>
        :root {
          --bg: #0a0a0a;
          --card-bg: #141414;
          --border: #2a2a2a;
          --text: #e0e0e0;
          --text-muted: #888;
          --accent: #f59e0b;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: var(--bg);
          color: var(--text);
          line-height: 1.6;
          padding: 2rem;
          max-width: 900px;
          margin: 0 auto;
        }
        h1 { margin-bottom: 0.5rem; }
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
        .item .download {
          padding: 0.25rem 0.5rem;
          color: var(--accent);
          text-decoration: none;
        }
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
        .markdown pre code {
          background: none;
          padding: 0;
        }
        .markdown li { margin-left: 1.5rem; margin-bottom: 0.25rem; }
        .markdown strong { color: #fff; }
      </style>
    </head>
    <body>
      #{content}
    </body>
    </html>
    """
  end
end
