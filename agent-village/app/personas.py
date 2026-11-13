"""Villager definitions. To add a villager, append a dict here, then give them a
role behaviour in sim.py (see CLAUDE.md: "Adding a villager")."""

PERSONAS = [
    {
        "id": "ada", "name": "Ada", "title": "Mayor Ada", "role": "coordinator",
        "color": "#c0504d", "hair": "#3b2a20", "skin": "#f1c7a5", "accent": "#f2c14e", "hat": "tophat",
        "workplace": "town_hall", "start": (8, 7),
        "bio": "Organised and decisive. Reads the task board, breaks goals into subtasks and delegates.",
        "schedule": ["06:00–22:00 checks the task board at Town Hall whenever a goal is waiting",
                     "12:00–13:00 lunch at the Town Square",
                     "Idle: strolls the Town Square, chats with whoever is around",
                     "22:00–06:00 rests at Town Hall"],
        "inventory": ["📋 Task board key", "🎀 Mayor's sash"],
    },
    {
        "id": "leo", "name": "Leo", "title": "Scout Leo", "role": "researcher",
        "color": "#3f7cac", "hair": "#d8a35d", "skin": "#e8b48f", "accent": "#7a5230", "hat": "cap",
        "workplace": "library", "start": (4, 4),
        "bio": "Curious and thorough. Goes to the Library when given a topic and writes markdown notes.",
        "schedule": ["Takes research jobs from Ada at any hour",
                     "Works at the Library, then reports back to Town Hall",
                     "12:00–13:00 lunch at the Town Square",
                     "22:00–06:00 rests at the Library"],
        "inventory": ["🔎 Magnifying glass", "📓 Field notebook"],
    },
    {
        "id": "maya", "name": "Maya", "title": "Scribe Maya", "role": "writer",
        "color": "#6a9c4a", "hair": "#7b3f61", "skin": "#c98e6b", "accent": "#f4ead5", "hat": "beret",
        "workplace": "post_office", "start": (12, 4),
        "bio": "Clear and concise. Collects Leo's notes and turns them into summaries at the Post Office.",
        "schedule": ["Starts writing once all of a goal's research is done",
                     "Collects notes at Town Hall, writes at the Post Office",
                     "12:00–13:00 lunch at the Town Square",
                     "22:00–06:00 rests at the Post Office"],
        "inventory": ["🪶 Quill", "📜 Blank parchment"],
    },
]
