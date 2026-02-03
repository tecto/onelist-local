# OpenClaw Session Import Plan

**Version:** 1.1.0
**Created:** 2026-02-02
**Status:** Draft
**Blocks:** River Section 39 Implementation

---

## 1. Overview

### 1.1 Purpose

This plan defines how to import existing OpenClaw session history when a user first installs onelist-local and connects it to an existing OpenClaw bot. This is a **one-time initial import** that runs during setup.

**Primary scenario:**
User has been running OpenClaw (e.g., Claude Code, River, or custom agents) and accumulates session history. They then install onelist-local to add persistent memory. On first connection, all existing sessions should be imported so the memory layer starts with full historical context.

### 1.2 Integration with Setup Flow

This import can be triggered via two entry points:

**Option A: `octo onelist` (Recommended)**
```bash
octo onelist  # OCTO's Onelist installer
```
OCTO detects existing sessions and offers import as part of its Onelist integration.

**Option B: `onelist-local setup`**
```bash
onelist-local setup  # Standalone Onelist installation
```

Both paths follow the same flow:

```
┌─────────────────────────────────────────────────────────────────┐
│           octo onelist / onelist-local setup                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. Detect OpenClaw Installation                                  │
│    - Check $OPENCLAW_HOME or ~/.openclaw                        │
│    - Read agents/*/sessions.json for active sessions            │
│    - Scan agents/*/sessions/*.jsonl for all sessions            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Prompt User                                                   │
│    "Found 842 sessions from 3 agents. Import history?"          │
│    [Import All] [Select Agents] [Skip]                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Run Session Import (this plan)                               │
│    - Parse and import selected sessions                          │
│    - Queue memory extraction                                     │
│    - Configure onelist-memory plugin for real-time sync         │
└─────────────────────────────────────────────────────────────────┘
```

After initial import completes, the existing `onelist-memory` plugin handles real-time sync for ongoing conversations.

---

## 2. Session File Format

### 2.1 File Location

OpenClaw stores session transcripts at:
```
$OPENCLAW_HOME/agents/{agentId}/sessions/{sessionId}.jsonl
```

Where `$OPENCLAW_HOME` defaults to `~/.openclaw` if not set.

Each agent maintains its own session directory. The active session is tracked in `sessions.json`:
```
$OPENCLAW_HOME/agents/{agentId}/sessions.json
```

**sessions.json format:**
```json
{
  "agent:main:main": {
    "sessionId": "abc123",
    "sessionFile": "/root/.openclaw/agents/main/sessions/abc123.jsonl"
  }
}
```

**Session ID convention:**
```
{channel}:{agent}:{user_or_group_id}
```

**Example paths:**
```
~/.openclaw/agents/main/sessions/telegram:main:12345.jsonl
~/.openclaw/agents/main/sessions/cli:main:local.jsonl
~/.openclaw/agents/river/sessions/slack:river:C04ABC123.jsonl
```

### 2.2 JSONL Message Format

Each line in a session file is a JSON object. **Only `type: "message"` entries contain conversational content** - tool_use and tool_result are filtered during import:

```typescript
interface SessionMessage {
  type?: string;           // "message" | "tool_use" | "tool_result" | etc.
  id?: string;             // Unique message ID
  timestamp?: string;      // ISO 8601 timestamp
  message?: {
    role?: string;         // "user" | "assistant" | "system"
    content?: unknown;     // String or array of content blocks
    timestamp?: number;    // Unix timestamp (milliseconds)
  };
}

// Content can be string or structured blocks:
type ContentBlock = string | Array<{ type: "text"; text: string }>;
```

**Filtering rules (matching onelist-memory plugin):**
- Only process entries where `type === "message"`
- Only process messages where `role === "user"` or `role === "assistant"`
- Skip lines with JSON parse errors (log warning if >3 errors)
- Skip messages shorter than 10 characters after media filtering

### 2.3 Session Metadata

Session metadata is inferred from:
- **Session ID**: Parsed from filename (`{sessionId}.jsonl`)
- **Channel/Agent/User**: Parsed from session ID (`channel:agent:user`)
- **File timestamps**: Created/modified times from filesystem
- **First/last message**: Session start/end times from message timestamps
- **Agent ID**: From parent directory path

---

## 3. Import Architecture

### 3.1 High-Level Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    OpenClaw Session Import                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1. Discovery                                                     │
│    - Scan ~/.openclaw/agents/*/sessions/*.jsonl                 │
│    - Build session inventory with metadata                       │
│    - Filter by date range, agent, channel (optional)            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Deduplication Check                                          │
│    - Query Onelist for existing sessions by external_id         │
│    - Compare message counts for partial imports                  │
│    - Build import manifest (new/update/skip)                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Entry Creation                                                │
│    - Create/update conversation entries                          │
│    - Create chat_log entries for message batches                │
│    - Link to agent person entries                                │
│    - Store raw JSONL in representations                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. Memory Extraction Queue                                       │
│    - Queue imported sessions for Reader Agent processing        │
│    - Batch processing with rate limiting                         │
│    - Progress tracking via job entries                          │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Component Responsibilities

| Component | Responsibility |
|-----------|----------------|
| `SessionDiscovery` | Find and inventory session files |
| `SessionParser` | Parse JSONL, extract metadata, validate format |
| `DeduplicationService` | Check existing entries, determine import action |
| `SessionImporter` | Create/update Onelist entries |
| `ImportJobManager` | Track progress, handle failures, queue memory extraction |

---

## 4. Entry Type Mapping

### 4.1 Conversation Entry

Each OpenClaw session maps to a `conversation` entry:

```elixir
%Entry{
  entry_type: "conversation",
  title: "Session with #{agent_name} - #{formatted_date}",
  external_id: "openclaw:session:#{session_id}",
  metadata: %{
    "channel" => "terminal",           # From session ID
    "agent_id" => "claude-code",       # From session ID
    "participant_ids" => ["user123"],  # From session ID
    "session_file" => "path/to/session.jsonl",
    "message_count" => 142,
    "started_at" => "2026-01-15T10:30:00Z",
    "ended_at" => "2026-01-15T11:45:00Z",
    "import_source" => "openclaw_bulk_import",
    "import_version" => "1.0.0"
  }
}
```

### 4.2 Chat Log Entries

Messages are stored as `chat_log` entries linked to the conversation:

```elixir
%Entry{
  entry_type: "chat_log",
  parent_id: conversation_entry.id,
  external_id: "openclaw:messages:#{session_id}:#{batch_index}",
  metadata: %{
    "batch_index" => 0,
    "message_count" => 50,
    "start_timestamp" => "2026-01-15T10:30:00Z",
    "end_timestamp" => "2026-01-15T10:45:00Z"
  }
}

# With representation containing the raw messages
%Representation{
  entry_id: chat_log_entry.id,
  format: "application/jsonl",
  content: "...",  # Raw JSONL for this batch
  purpose: "source"
}
```

### 4.3 Agent Person Entries

Agents are represented as `person` entries (if not already existing):

```elixir
%Entry{
  entry_type: "person",
  title: "Claude Code",
  external_id: "openclaw:agent:claude-code",
  metadata: %{
    "person_type" => "artificial",
    "agent_level" => "primary",
    "agent_id" => "claude-code",
    "capabilities" => ["code_generation", "file_editing", "shell_execution"]
  }
}
```

### 4.4 Entry Links

```
conversation ──[participant]──► person (agent)
conversation ──[participant]──► person (user, if exists)
chat_log ────[belongs_to]───► conversation
```

---

## 5. Deduplication Strategy

On first install, there's nothing to deduplicate. However, deduplication is needed for:
- Re-running import after reinstalling onelist-local
- Importing from a second machine with overlapping sessions
- Manual re-import after clearing data

### 5.1 Session-Level Deduplication

Query by `external_id` pattern:
```elixir
# Check if session already imported
existing = Entries.get_by_external_id("openclaw:session:#{session_id}")

case existing do
  nil -> :new_import
  entry ->
    if entry.metadata["message_count"] < current_message_count do
      :update_import  # Session has new messages since last import
    else
      :skip           # Already fully imported
    end
end
```

### 5.2 Conflict Resolution

| Scenario | Action |
|----------|--------|
| New session | Full import |
| Same message count | Skip (no changes) |
| More messages locally | Append new messages only |
| Fewer messages locally | Log warning, skip (possible data loss) |
| Corrupted local file | Log error, skip, report in summary |

---

## 6. Memory Extraction Integration

### 6.1 Queue for Reader Agent

After import, queue sessions for memory extraction:

```elixir
%Entry{
  entry_type: "job",
  title: "Memory extraction: #{session_id}",
  metadata: %{
    "job_type" => "memory_extraction",
    "status" => "pending",
    "target_entry_id" => conversation_entry.id,
    "priority" => "low",  # Bulk imports are low priority
    "batch_id" => import_batch_id
  }
}
```

### 6.2 Batch Processing Strategy

```
Import 1000 sessions
    │
    ▼
Queue 1000 extraction jobs (low priority)
    │
    ▼
Reader Agent processes at 10 sessions/minute
    │
    ▼
~100 minutes to complete extraction
```

Rate limiting prevents API cost spikes and ensures real-time operations remain responsive.

### 6.3 Progress Tracking

Track overall import progress:

```elixir
%Entry{
  entry_type: "job",
  title: "OpenClaw Bulk Import #{timestamp}",
  metadata: %{
    "job_type" => "openclaw_bulk_import",
    "status" => "in_progress",
    "progress" => %{
      "discovered" => 1000,
      "imported" => 750,
      "skipped" => 200,
      "failed" => 5,
      "extraction_queued" => 750,
      "extraction_complete" => 300
    },
    "started_at" => "2026-02-02T10:00:00Z",
    "errors" => [
      %{"session_id" => "...", "error" => "Parse error at line 42"}
    ]
  }
}
```

---

## 7. CLI Interface

### 7.1 Setup Wizard Integration

During `onelist-local setup`, the wizard automatically:
1. Detects OpenClaw installation at `~/.openclaw`
2. Counts sessions per agent
3. Prompts user to import
4. Runs import with progress bar
5. Enables real-time sync plugin

### 7.2 Manual Commands

For advanced users or re-import scenarios:

```bash
# Discover sessions without importing
onelist-local openclaw discover
onelist-local openclaw discover --agent claude-code

# Import sessions (runs interactively)
onelist-local openclaw import
onelist-local openclaw import --agent claude-code
onelist-local openclaw import --dry-run  # Preview only

# Check import status
onelist-local openclaw status
```

### 7.3 Setup Wizard Output

```
Detecting OpenClaw installation...

Found 842 sessions from 3 agents:
  claude-code:    623 sessions
  river:          201 sessions
  researcher:      18 sessions

Import session history? This enables your AI agents to remember
past conversations. [Y/n]

Importing sessions...
  [████████████████████████████████████████] 842/842

✓ Imported 842 sessions
✓ Queued memory extraction (processing in background)
✓ Enabled real-time sync for new conversations
```

### 7.3 Configuration

```yaml
# ~/.onelist-local/config.yaml

openclaw:
  session_path: "~/.openclaw/agents"
  import:
    batch_size: 50           # Sessions per API batch
    max_concurrent: 3        # Parallel API connections
    skip_agents: []          # Agents to exclude
    memory_extraction: true  # Queue for Reader processing
    priority: "low"          # Job priority for extraction
```

---

## 8. Internal API

The import runs locally within onelist-local. These internal functions are used by the setup wizard and CLI:

### 8.1 Core Functions

```typescript
// Discover available sessions
interface DiscoveryResult {
  agents: Array<{
    agentId: string;
    sessionCount: number;
    oldestSession: Date;
    newestSession: Date;
  }>;
  totalSessions: number;
}

async function discoverSessions(openclawPath?: string): Promise<DiscoveryResult>

// Import sessions
interface ImportOptions {
  agents?: string[];        // Filter to specific agents
  skipExtraction?: boolean; // Don't queue memory extraction
  onProgress?: (imported: number, total: number) => void;
}

interface ImportResult {
  imported: number;
  skipped: number;
  failed: number;
  errors: Array<{ sessionId: string; error: string }>;
}

async function importSessions(options?: ImportOptions): Promise<ImportResult>
```

### 8.2 Onelist API Usage

The importer uses the standard Onelist entries API to create entries:

```
POST /api/v1/entries  (for each conversation)
POST /api/v1/entries  (for each chat_log batch)
POST /api/v1/representations  (for raw JSONL storage)
```

No special import-specific endpoints are required.

---

## 9. Error Handling

### 9.1 Parse Errors

```elixir
defmodule Onelist.OpenClaw.SessionParser do
  def parse_session(path) do
    path
    |> File.stream!()
    |> Stream.with_index(1)
    |> Stream.map(fn {line, line_num} ->
      case Jason.decode(line) do
        {:ok, message} -> {:ok, message}
        {:error, reason} -> {:error, {:parse_error, line_num, reason}}
      end
    end)
    |> Enum.reduce({[], []}, fn
      {:ok, msg}, {messages, errors} -> {[msg | messages], errors}
      {:error, err}, {messages, errors} -> {messages, [err | errors]}
    end)
  end
end
```

### 9.2 Error Recovery

| Error Type | Recovery Strategy |
|------------|-------------------|
| Parse error (single line) | Skip line, continue, log warning |
| Parse error (>10% of file) | Skip file, log error |
| API timeout | Retry with exponential backoff (3 attempts) |
| API rate limit | Queue for later, respect Retry-After |
| Disk full | Abort import, preserve progress |
| Network failure | Checkpoint progress, resume later |

### 9.3 Checkpointing

Progress is checkpointed after each batch:

```elixir
# In job metadata
%{
  "checkpoint" => %{
    "last_processed_session" => "terminal:claude-code:user123",
    "sessions_complete" => 750,
    "updated_at" => "2026-02-02T10:03:00Z"
  }
}
```

Resume reads checkpoint and continues from last successful session.

---

## 10. Implementation Phases

### Phase 1: Core Import

- [ ] `SessionDiscovery` - scan `~/.openclaw` and inventory sessions
- [ ] `SessionParser` - JSONL parsing with error handling
- [ ] Entry creation for conversations and chat_logs
- [ ] Unit tests for parser and discovery

### Phase 2: Setup Wizard Integration

- [ ] Integrate discovery into `onelist-local setup`
- [ ] User prompt with agent/session counts
- [ ] Progress bar during import
- [ ] Enable real-time sync plugin after import

### Phase 3: Memory Extraction

- [ ] Queue imported sessions for Reader Agent
- [ ] Background processing with low priority
- [ ] Status reporting for extraction progress

### Phase 4: Manual CLI & Polish

- [ ] `onelist-local openclaw discover` command
- [ ] `onelist-local openclaw import` command (for re-import)
- [ ] Deduplication for re-import scenarios
- [ ] End-to-end tests

---

## 11. Testing Strategy

### 11.1 Unit Tests

```elixir
# test/onelist_local/openclaw/session_parser_test.exs
describe "parse_session/1" do
  test "parses valid JSONL file"
  test "handles malformed JSON lines gracefully"
  test "extracts metadata from messages"
  test "handles empty files"
  test "handles very large files (streaming)"
end

# test/onelist_local/openclaw/deduplication_test.exs
describe "check_duplicate/1" do
  test "detects new sessions"
  test "detects exact duplicates"
  test "detects sessions needing update"
  test "handles missing external_id"
end
```

### 11.2 Integration Tests

```elixir
# test/onelist_local/openclaw/import_integration_test.exs
describe "full import flow" do
  test "imports new sessions end-to-end"
  test "skips already-imported sessions"
  test "handles mixed new/existing sessions"
  test "queues memory extraction jobs"
  test "tracks progress correctly"
end
```

### 11.3 Test Fixtures

Create sample session files:
```
test/fixtures/openclaw/
├── valid_session.jsonl
├── malformed_session.jsonl
├── empty_session.jsonl
├── large_session.jsonl (1000+ messages)
└── mixed_content_session.jsonl (text, tool calls, etc.)
```

---

## 12. Security Considerations

### 12.1 File Access

- Only read from configured `session_path`
- Validate paths don't escape intended directory
- Skip files without read permission (log warning)

### 12.2 Content Sanitization

- Sanitize any HTML in message content before storage
- Validate JSON structure before processing
- Limit maximum message size (prevent DoS)

### 12.3 API Authentication

- Import API requires authentication
- Rate limit import requests per user
- Log all import operations for audit

---

## 13. OCTO Coordination

When OCTO is installed, the import process must coordinate with OCTO's monitoring systems.

### 13.1 Environment Variables

Respect OCTO's environment:
```bash
OPENCLAW_HOME    # Use this instead of hardcoded ~/.openclaw
OCTO_HOME        # Location of OCTO state files (default: ~/.octo)
```

### 13.2 Session Archive Paths

OCTO archives sessions to specific paths. The importer should:
- **Check archived sessions** in addition to active sessions
- **Not interfere** with OCTO's archival process during import
- **Use consistent paths** if creating any archives

| System | Archive Path |
|--------|-------------|
| OCTO Watchdog | `$OPENCLAW_HOME/workspace/session-archives/watchdog/YYYY-MM-DD/` |
| OCTO Surgery | `$OPENCLAW_HOME/workspace/session-archives/surgery/YYYY-MM-DD/` |
| OCTO Sentinel | `$OPENCLAW_HOME/workspace/session-archives/bloated/YYYY-MM-DD/` |

### 13.3 Health State Files

If OCTO reports database health issues, pause import:
```typescript
const OCTO_HEALTH_FILE = `${OCTO_HOME}/onelist-health.json`;

async function checkOctoHealth(): Promise<boolean> {
  if (fs.existsSync(OCTO_HEALTH_FILE)) {
    const health = JSON.parse(fs.readFileSync(OCTO_HEALTH_FILE, 'utf-8'));
    if (health.status === 'CRITICAL') {
      logger.warn('OCTO reports Onelist health CRITICAL - pausing import');
      return false;
    }
  }
  return true;
}
```

### 13.4 Triggering via OCTO

When triggered via `octo onelist`:
1. OCTO installs Onelist server and PostgreSQL
2. OCTO detects existing sessions and calls the import
3. OCTO configures the `onelist-memory` plugin
4. OCTO starts its monitoring services (sentinel, watchdog)

The import should report progress back to OCTO's dashboard if available.

---

## 14. Dependencies

### 13.1 Requires Before Implementation

- Entry types `conversation` and `chat_log` defined in schema
- `external_id` index on entries table
- Reader Agent memory extraction pipeline operational

### 13.2 Enables After Implementation

- **River Section 39**: External agent coordination can reference imported sessions
- **Multi-agent memory sharing**: Agents can query each other's session history
- **Analytics**: Session data available for usage analysis

---

## 14. Success Metrics

| Metric | Target |
|--------|--------|
| Import speed | 100+ sessions/minute |
| Parse success rate | >99% for valid files |
| Deduplication accuracy | 100% (no false positives) |
| Memory extraction queue | <5 minute delay after import |
| Recovery success | Resume from any failure point |

---

## Appendix A: JSONL Message Examples

### User Message (IMPORTED)
```json
{"type":"message","id":"msg_001","timestamp":"2026-01-15T10:30:00Z","message":{"role":"user","content":"Can you help me refactor this function?","timestamp":1705314600000}}
```

### Assistant Message (IMPORTED)
```json
{"type":"message","id":"msg_002","timestamp":"2026-01-15T10:30:15Z","message":{"role":"assistant","content":"I'd be happy to help. Let me take a look at the function...","timestamp":1705314615000}}
```

### Structured Content (IMPORTED)
```json
{"type":"message","id":"msg_003","timestamp":"2026-01-15T10:31:00Z","message":{"role":"assistant","content":[{"type":"text","text":"Here's the refactored version:"},{"type":"text","text":"```javascript\nfunction formatDate(date) {...}\n```"}]}}
```

### Tool Use (SKIPPED - not imported)
```json
{"type":"tool_use","id":"tool_001","timestamp":"2026-01-15T10:30:20Z","tool_name":"Read","tool_input":{"file_path":"/src/utils.js"}}
```

### Tool Result (SKIPPED - not imported)
```json
{"type":"tool_result","id":"tool_001","timestamp":"2026-01-15T10:30:21Z","tool_result":"function formatDate(date) {\n  return date.toISOString();\n}"}
```

---

## Appendix B: Related Documents

**In this repo:**
- [onelist-memory plugin](../extensions/onelist-memory/) - Real-time sync (runs after initial import)
- [OCTO_INTEGRATION_RECOMMENDATIONS.md](../extensions/onelist-memory/OCTO_INTEGRATION_RECOMMENDATIONS.md) - OCTO coordination patterns
- [openclaw-onelist-integration.md](./openclaw-onelist-integration.md) - Overall integration architecture

**In onelist.com repo:**
- [unified_schema.md](../../onelist.com/roadmap/unified_schema.md) - Entry type definitions
- [reader_agent_plan.md](../../onelist.com/roadmap/reader_agent_plan.md) - Memory extraction
- [river_agent_plan.md](../../onelist.com/roadmap/river_agent_plan.md) - Section 39: External Agent Coordination

**External:**
- [OCTO (trinsiklabs/octo)](https://github.com/trinsiklabs/octo) - Token optimizer with `octo onelist` command

---

## Changelog

| Date | Version | Changes |
|------|---------|---------|
| 2026-02-02 | 1.1.0 | Aligned with onelist-memory plugin, OCTO, and openclaw-onelist-integration |
| 2026-02-02 | 1.0.0 | Initial plan created |
