"""Villager brains.

MockBrain  - offline, free, instant. Deterministic templates so you can test
             movement and UI without spending anything.
LiveBrain  - Claude via the Anthropic SDK. Small prompts, structured outputs,
             an hourly call cap, and automatic fallback to MockBrain on any
             error, so the village never stalls.

The brain only writes *content* (plans, notes, summaries, dialogue). Where
villagers walk is decided by the simulation, which keeps live mode cheap:
roughly 1 call per plan, 1 per note, 1 per summary, 1 per conversation.
"""
from __future__ import annotations

import json
import os
import random
import re
import time

MODEL = os.environ.get("VILLAGE_MODEL", "claude-opus-5-5")
MAX_CALLS_PER_HOUR = int(os.environ.get("VILLAGE_MAX_CALLS_PER_HOUR", "40"))
WEB_SEARCH = os.environ.get("VILLAGE_WEB_SEARCH", "0") == "1"


class BrainUnavailable(Exception):
    pass


def live_available() -> tuple[bool, str]:
    try:
        import anthropic  # noqa: F401
    except ImportError:
        return False, "Install the 'anthropic' package to enable live mode."
    if not (os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN")
            or os.environ.get("ANTHROPIC_PROFILE")):
        return False, "Set ANTHROPIC_API_KEY before starting the server to enable live mode."
    return True, f"Live: {MODEL}" + (" + web search" if WEB_SEARCH else "")


# ---------------------------------------------------------------- mock brain
SMALL_TALK = {
    "ada": ["The task board is looking healthy today.", "I like a goal with a clear finish line.",
            "Remember: notes first, summary second.", "Anyone free? I may have work soon.",
            "The fountain needs a coin or two."],
    "leo": ["The Library has a new shelf on {topic}.", "I could research {topic} all day.",
            "Citations are my love language.", "Found a dusty book in the back stacks.",
            "Every note needs a source line."],
    "maya": ["Short sentences. Clear headings. That's the trick.", "My quill is freshly sharpened.",
             "I turned three pages of notes into one paragraph today!", "The outbox is tidy.",
             "Good summaries start with the answer."],
}
REPLIES = ["Ha, fair enough.", "Couldn't agree more.", "Tell me more later?", "That's the spirit!",
           "Oh nice, I'll keep that in mind.", "Mm, sounds about right.", "You always say that!"]


def _split_goal(goal: str) -> list[str]:
    parts = [p.strip(" .") for p in re.split(r",| and |;|\n", goal) if len(p.strip()) > 3]
    return parts[:3] if len(parts) > 1 else []


class MockBrain:
    name = "mock"

    async def plan(self, goal: dict) -> dict:
        parts = _split_goal(goal["title"])
        if parts:
            research = [{"title": p[:80], "question": f"What should we know about {p}?"} for p in parts]
        else:
            t = goal["title"][:70]
            research = [{"title": f"Background: {t}", "question": f"Key facts and context about {t}."},
                        {"title": f"Options & trade-offs: {t}", "question": f"Main options, pros and cons for {t}."}]
        return {"thought": f"I'll split this into {len(research)} research job(s) for Leo, then Maya writes it up.",
                "research": research,
                "writing_brief": f"One-page summary answering: {goal['title']}"}

    async def research(self, goal: dict, task: dict) -> str:
        return (f"# {task['title']}\n\n> Mock mode: placeholder content, no API call was made.\n\n"
                f"**Question:** {task['detail']}\n\n## Findings\n\n"
                f"- Placeholder finding 1 about *{task['title']}*.\n"
                f"- Placeholder finding 2. Live mode would research this properly.\n"
                f"- Placeholder finding 3, with a caveat about what we don't know.\n\n"
                f"## Open questions\n\n- What constraints matter most for “{goal['title']}”?\n\n"
                f"## Sources\n\n- (mock) none\n")

    async def write(self, goal: dict, task: dict, notes: list[tuple[str, str]]) -> str:
        bullets = []
        for path, text in notes:
            heading = next((l[2:] for l in text.splitlines() if l.startswith("# ")), path)
            bullets.append(f"- **{heading}**: see `{path}`")
        return (f"# Summary: {goal['title']}\n\n> Mock mode: placeholder content, no API call was made.\n\n"
                f"## TL;DR\n\nPlaceholder answer to “{goal['title']}”. Live mode writes a real summary from "
                f"Leo's notes.\n\n## What we looked at\n\n" + "\n".join(bullets) +
                "\n\n## Next steps\n\n- Review the notes\n- Switch to live mode for real content\n")

    async def chat(self, a: dict, b: dict, context: str) -> list[dict]:
        topic = context or "the village"
        first = random.choice(SMALL_TALK.get(a["id"], ["Lovely day."])).format(topic=topic)
        lines = [{"speaker": a["id"], "text": first},
                 {"speaker": b["id"], "text": random.choice(REPLIES)}]
        if random.random() < 0.5:
            lines.append({"speaker": a["id"], "text": random.choice(["Catch you at the fountain.", "Back to it!", "See you around."])})
        return lines


# ---------------------------------------------------------------- live brain
class LiveBrain(MockBrain):
    name = "live"

    def __init__(self):
        import anthropic
        self.anthropic = anthropic
        self.client = anthropic.AsyncAnthropic()
        self.calls: list[float] = []

    def _check_budget(self):
        now = time.time()
        self.calls = [t for t in self.calls if now - t < 3600]
        if len(self.calls) >= MAX_CALLS_PER_HOUR:
            raise BrainUnavailable(f"hourly cap of {MAX_CALLS_PER_HOUR} live calls reached")
        self.calls.append(now)

    async def _ask(self, system: str, prompt: str, *, schema: dict | None = None, effort: str = "low",
                   max_tokens: int = 2000, tools: list | None = None) -> str:
        self._check_budget()
        output_config: dict = {"effort": effort}
        if schema:
            output_config["format"] = {"type": "json_schema", "schema": schema}
        messages = [{"role": "user", "content": prompt}]
        try:
            for _ in range(3):  # resume server-tool pauses (web search) a couple of times at most
                kwargs = dict(model=MODEL, max_tokens=max_tokens, system=system, messages=messages,
                              output_config=output_config,
                              betas=["server-side-fallback-2026-07-01"], fallbacks="default")
                if tools:
                    kwargs["tools"] = tools
                resp = await self.client.beta.messages.create(**kwargs)
                if resp.stop_reason == "pause_turn":
                    messages = [messages[0], {"role": "assistant", "content": resp.content}]
                    continue
                break
        except self.anthropic.RateLimitError as e:
            raise BrainUnavailable("rate limited") from e
        except self.anthropic.APIStatusError as e:
            raise BrainUnavailable(f"API error {e.status_code}") from e
        except self.anthropic.APIConnectionError as e:
            raise BrainUnavailable("can't reach the API") from e
        if resp.stop_reason == "refusal":
            raise BrainUnavailable("request declined")
        text = "".join(b.text for b in resp.content if b.type == "text").strip()
        if not text:
            raise BrainUnavailable("empty response")
        return text

    async def plan(self, goal):
        schema = {
            "type": "object", "additionalProperties": False,
            "required": ["thought", "research", "writing_brief"],
            "properties": {
                "thought": {"type": "string"},
                "research": {"type": "array", "items": {
                    "type": "object", "additionalProperties": False, "required": ["title", "question"],
                    "properties": {"title": {"type": "string"}, "question": {"type": "string"}}}},
                "writing_brief": {"type": "string"},
            },
        }
        out = await self._ask(
            "You are Mayor Ada, coordinator of a small AI village. Break goals into 1-3 focused research "
            "subtasks for Scout Leo (researcher) and one writing brief for Scribe Maya (writer). "
            "Keep titles under 8 words. 'thought' is one short first-person sentence.",
            f"Goal: {goal['title']}\nDetails: {goal.get('detail') or '(none)'}", schema=schema)
        data = json.loads(out)
        data["research"] = data["research"][:3] or (await super().plan(goal))["research"]
        return data

    async def research(self, goal, task):
        tools = [{"type": "web_search_20260209", "name": "web_search", "max_uses": 3}] if WEB_SEARCH else None
        src = ("Use web search and cite URLs in a Sources section." if WEB_SEARCH else
               "You have no web access: rely on what you know, flag anything that may be outdated, and say "
               "'from model knowledge' in Sources.")
        return await self._ask(
            "You are Scout Leo, the village researcher. Write concise markdown research notes: a '# ' title, "
            "'## Findings' bullets, '## Open questions', '## Sources'. Under 350 words. Be explicit about "
            "uncertainty. " + src,
            f"Overall goal: {goal['title']}\nYour subtask: {task['title']}\nQuestion: {task['detail']}",
            effort="medium", max_tokens=4000, tools=tools) + "\n"

    async def write(self, goal, task, notes):
        corpus = "\n\n".join(f'<note path="{p}">\n{t}\n</note>' for p, t in notes)
        return await self._ask(
            "You are Scribe Maya, the village writer. Turn research notes into a clean markdown summary: "
            "'# Summary: <goal>', '## TL;DR' (2-3 sentences), '## Key points', '## Next steps'. Under 300 "
            "words. Only use facts from the notes; cite note paths inline like (notes/x.md).",
            f"Goal: {goal['title']}\nBrief: {task['detail']}\n\n{corpus}", effort="medium", max_tokens=3000) + "\n"

    async def chat(self, a, b, context):
        schema = {
            "type": "object", "additionalProperties": False, "required": ["lines"],
            "properties": {"lines": {"type": "array", "items": {
                "type": "object", "additionalProperties": False, "required": ["speaker", "text"],
                "properties": {"speaker": {"type": "string", "enum": [a["id"], b["id"]]},
                               "text": {"type": "string"}}}}},
        }
        out = await self._ask(
            "Write a tiny, cozy 2-4 line exchange between two villagers in a pixel-art village. Each line "
            "under 12 words, in character, alternating speakers, starting with the first villager.",
            f"First: {a['name']} ({a['title']}). Second: {b['name']} ({b['title']}).\n"
            f"What's going on in the village: {context or 'a quiet moment'}", schema=schema)
        lines = json.loads(out)["lines"][:4]
        return lines or await super().chat(a, b, context)
