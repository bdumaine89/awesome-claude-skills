"""Villager brains: decide *what to write*, never where to walk.

Movement and schedules are deterministic (free, predictable). The brain is only
asked for content at the moment real work happens, so cost scales with tasks
done, not with simulation ticks.

- ScriptedBrain: free, offline, template/keyword based. The default.
- ClaudeBrain:   calls the Claude API. Opt-in with VILLAGE_BRAIN=claude and
                 capped by VILLAGE_MAX_CALLS_PER_HOUR (falls back to scripted).
"""
from __future__ import annotations

import json
import os
import random
import re
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WS = ROOT / "workspace"

CHAT_LINES = {
    "ada": ["Found a great note in the stacks today.", "Citations or it didn't happen.",
            "The library could use a better index.", "I flagged two gaps in what we know."],
    "bo": ["Outbox is tidy. Every draft waits for a human.", "Keep it short enough for a phone screen.",
           "Who's got the latest research? I need facts, not vibes.", "Drafted, not sent. That's the rule."],
    "cy": ["Inbox is under control.", "Vague requests are my least favourite thing.",
           "I routed three things this morning.", "If it's not on the board, it didn't happen."],
    "dee": ["The noticeboard tells the real story.", "Writing up today's digest later.",
            "Anyone finish something I should log?", "Coffee first, digest second."],
}

KIND_KEYWORDS = {
    "email": ["email", "mail", "reply", "draft", "message", "write to", "send", "invite"],
    "research": ["research", "find", "look up", "summar", "what is", "what are", "compare", "learn", "explain"],
    "digest": ["digest", "recap", "report", "log", "update the board", "status"],
}


def _words(text: str) -> set[str]:
    return {w for w in re.findall(r"[a-z0-9]+", text.lower()) if len(w) > 3}


def _library_docs() -> list[tuple[Path, str]]:
    docs = []
    for folder in (WS / "library", WS / "research"):
        for p in sorted(folder.glob("*.md")):
            docs.append((p, p.read_text(errors="ignore")))
    return docs


class ScriptedBrain:
    name = "scripted"

    def triage(self, persona: dict, task: dict) -> dict:
        text = f"{task['title']} {task.get('detail', '')}".lower()
        scores = {k: sum(kw in text for kw in kws) for k, kws in KIND_KEYWORDS.items()}
        kind = max(scores, key=scores.get) if max(scores.values()) > 0 else "research"
        return {"kind": kind, "note": f"Routed by keyword match ({kind})."}

    def research(self, persona: dict, task: dict) -> str:
        query = _words(f"{task['title']} {task.get('detail', '')}")
        hits = []
        for path, text in _library_docs():
            for para in re.split(r"\n\s*\n", text):
                if para.lstrip().startswith(("#", "Source")):
                    continue
                overlap = len(query & _words(para))
                if overlap >= 2:
                    hits.append((overlap, path, para.strip()))
        hits.sort(key=lambda h: -h[0])
        lines = [f"# Research: {task['title']}", "", f"_Compiled by {persona['name']} (scripted brain)_", ""]
        if not hits:
            lines += ["Nothing in the library matched this question. Add notes to `workspace/library/` "
                      "or turn on the Claude brain for synthesis.", ""]
        else:
            lines += ["## Relevant passages", ""]
            for _, path, para in hits[:6]:
                snippet = " ".join(para.split())[:400]
                lines.append(f"- {snippet} _(from `{path.relative_to(ROOT)}`)_")
            lines += ["", "## Sources", ""] + sorted({f"- `{h[1].relative_to(ROOT)}`" for h in hits[:6]})
        return "\n".join(lines) + "\n"

    def email(self, persona: dict, task: dict, context: str) -> str:
        to = task.get("to") or "[TODO: recipient]"
        body_ctx = ""
        if context:
            first = [re.sub(r"\s*_\(from .*?\)_", "", l) for l in context.splitlines()
                     if l.startswith("- ") and "(from" in l][:3]
            if first:
                body_ctx = "\n\nKey points:\n" + "\n".join(first)
        return (f"To: {to}\nSubject: {task['title']}\n\n"
                f"Hi,\n\n{task.get('detail') or '[TODO: main point]'}{body_ctx}\n\n"
                f"Thanks,\n[TODO: your name]\n\n---\nDrafted by {persona['name']} (scripted brain). Not sent.\n")

    def digest(self, persona: dict, done: list[dict], open_: list[dict]) -> str:
        lines = [f"Done: {len(done)} · Open: {len(open_)}"]
        lines += [f"  - ✅ {t['title']} ({t.get('by') or '?'})" for t in done[-8:]]
        lines += [f"  - ⏳ {t['title']}" for t in open_[:5]]
        return "\n".join(lines)

    def chat(self, persona: dict, other: dict) -> str:
        return random.choice(CHAT_LINES.get(persona["id"], ["Nice day for it."]))


class ClaudeBrain(ScriptedBrain):
    """Uses the Anthropic SDK. Every call is counted against an hourly cap."""

    name = "claude"

    def __init__(self, model: str, max_calls_per_hour: int, log):
        import anthropic  # imported lazily so the scripted mode needs no deps

        self.client = anthropic.Anthropic()
        self.anthropic = anthropic
        self.model = model
        self.max_calls = max_calls_per_hour
        self.calls: list[float] = []
        self.lock = threading.Lock()
        self.log = log

    # -- guardrail ---------------------------------------------------------
    def _budget_ok(self) -> bool:
        with self.lock:
            now = time.time()
            self.calls = [t for t in self.calls if now - t < 3600]
            if len(self.calls) >= self.max_calls:
                return False
            self.calls.append(now)
            return True

    def _persona_text(self, persona: dict) -> str:
        p = ROOT / "villagers" / f"{persona['id']}.md"
        rules = (ROOT / "CLAUDE.md").read_text() if (ROOT / "CLAUDE.md").exists() else ""
        return (p.read_text() if p.exists() else persona["role"]) + "\n\n" + rules

    def _ask(self, persona: dict, prompt: str, schema: dict | None = None, effort: str = "low") -> str | None:
        if not self._budget_ok():
            self.log(f"Claude call cap reached ({self.max_calls}/h) — {persona['name']} using scripted brain.")
            return None
        kwargs = dict(
            model=self.model,
            max_tokens=4000,
            system=self._persona_text(persona),
            messages=[{"role": "user", "content": prompt}],
            output_config={"effort": effort},
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
        )
        if schema:
            kwargs["output_config"]["format"] = {"type": "json_schema", "schema": schema}
        try:
            resp = self.client.beta.messages.create(**kwargs)
        except self.anthropic.RateLimitError:
            self.log("Claude rate-limited — falling back to scripted brain for this action.")
            return None
        except self.anthropic.APIStatusError as e:
            self.log(f"Claude API error {e.status_code} — falling back to scripted brain.")
            return None
        except self.anthropic.APIConnectionError:
            self.log("Claude unreachable — falling back to scripted brain.")
            return None
        if resp.stop_reason == "refusal":
            self.log(f"Claude declined a request from {persona['name']} — using scripted brain.")
            return None
        return "".join(b.text for b in resp.content if b.type == "text").strip()

    # -- actions -----------------------------------------------------------
    def triage(self, persona, task):
        schema = {
            "type": "object",
            "properties": {"kind": {"type": "string", "enum": ["research", "email", "digest"]},
                           "note": {"type": "string"}},
            "required": ["kind", "note"], "additionalProperties": False,
        }
        out = self._ask(persona, "Route this village request to exactly one task kind "
                        "(research, email, digest) and note any assumption in one sentence.\n\n"
                        f"Title: {task['title']}\nDetail: {task.get('detail', '')}", schema)
        if out:
            try:
                return json.loads(out)
            except json.JSONDecodeError:
                pass
        return super().triage(persona, task)

    def research(self, persona, task):
        docs = _library_docs()
        corpus = "\n\n".join(f"<doc path=\"{p.relative_to(ROOT)}\">\n{t}\n</doc>" for p, t in docs)
        out = self._ask(persona, f"Using ONLY the documents below, write a markdown research brief titled "
                        f"'# Research: {task['title']}'. Cite the doc path for each claim and end with a "
                        f"Sources section. If the docs don't answer it, say so.\n\nRequest detail: "
                        f"{task.get('detail', '')}\n\n{corpus}", effort="medium")
        return out + "\n" if out else super().research(persona, task)

    def email(self, persona, task, context):
        out = self._ask(persona, "Draft (do not send) a short email. Format exactly:\nTo: ...\nSubject: ...\n\n"
                        "<body>\n\nUse [TODO: ...] for anything you don't know. "
                        f"Request: {task['title']}\nDetail: {task.get('detail', '')}\nRecipient: "
                        f"{task.get('to', 'unknown')}\n\nResearch context:\n{context[:6000]}")
        return out + "\n\n---\nDrafted by " + persona["name"] + " (Claude). Not sent.\n" if out \
            else super().email(persona, task, context)

    def digest(self, persona, done, open_):
        out = self._ask(persona, "Write a 3-6 line village digest from this task log. Only report what's "
                        f"listed.\n\nDone: {json.dumps(done[-15:])}\nOpen: {json.dumps(open_[:10])}")
        return out or super().digest(persona, done, open_)

    def chat(self, persona, other):
        # Small talk is never worth a paid call; keep it scripted.
        return super().chat(persona, other)


def make_brain(log) -> ScriptedBrain:
    mode = os.environ.get("VILLAGE_BRAIN", "scripted").lower()
    if mode == "claude":
        try:
            brain = ClaudeBrain(
                model=os.environ.get("VILLAGE_MODEL", "claude-opus-5-5"),
                max_calls_per_hour=int(os.environ.get("VILLAGE_MAX_CALLS_PER_HOUR", "20")),
                log=log,
            )
            log(f"Claude brain on ({brain.model}, cap {brain.max_calls} calls/hour).")
            return brain
        except ImportError:
            log("VILLAGE_BRAIN=claude but the 'anthropic' package isn't installed — using scripted brain.")
    return ScriptedBrain()
