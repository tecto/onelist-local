defmodule OnelistWeb.WatchController do
  use OnelistWeb, :controller

  def index(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html>
    <head>
      <title>Stream Watch</title>
      <style>
        body {
          font-family: system-ui, -apple-system, sans-serif;
          max-width: 600px;
          margin: 50px auto;
          padding: 20px;
          background: #0a0a0a;
          color: #e0e0e0;
        }
        h1 {
          border-bottom: 2px solid #333;
          padding-bottom: 10px;
          margin-bottom: 20px;
        }
        .endpoint {
          margin: 20px 0;
          padding: 20px;
          background: #141414;
          border-radius: 8px;
          border: 1px solid #2a2a2a;
        }
        .endpoint h2 {
          margin: 0 0 10px 0;
          font-size: 1.2em;
        }
        .endpoint p {
          margin: 0;
          color: #888;
        }
        a {
          color: #3b82f6;
          text-decoration: none;
        }
        a:hover {
          text-decoration: underline;
        }
        .status {
          font-size: 0.85em;
          color: #28a745;
          margin-top: 8px;
        }
      </style>
    </head>
    <body>
      <h1>Stream Watch</h1>
      <p>Monitoring endpoints for stream.onelist.my</p>

      <div class="endpoint">
        <h2><a href="/watch/livelog">Live Log</a></h2>
        <p>Real-time activity stream from Stream and connected services.</p>
        <div class="status">LiveView - Auto-updates</div>
      </div>

      <div class="endpoint">
        <h2><a href="/watch/workspace">Workspace</a></h2>
        <p>Browse OpenClaw workspace files, memory, and configuration.</p>
        <div class="status">File browser - Markdown rendering</div>
      </div>

      <div class="endpoint">
        <h2><a href="/watch/swarm">Swarm</a></h2>
        <p>Claude Code Swarm content - plans, docs, roster, and more.</p>
        <div class="status">File browser - Markdown rendering</div>
      </div>
    </body>
    </html>
    """)
  end
end
