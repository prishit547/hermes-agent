"""Music recommendation engine — endless, feedback-aware radio.

Ported from Atlantic OS (`music_recommender` + `music_taste`), adapted to Hermes:

* Taste comes from the JSON listening history in ``store.py`` (top artists / top
  tracks / likes / dislikes) — **not** an embedding centroid (Hermes ships no
  embeddings utility), so the cosine-similarity term is dropped.
* The LLM "DJ" re-rank uses Hermes' ``agent.auxiliary_client.call_llm`` instead
  of Atlantic's gateway.

Pipeline:
  build_candidates -> blend YouTube Mix radios (current track + top-taste seeds),
                      dedup + novelty-filter against dislikes/recents
  rank_fast        -> score by source weight + artist diversity (no LLM)
  rank_llm         -> an LLM DJ reorders the candidate set for an explicit
                      natural-language request (only reorders real candidates —
                      never invents tracks); falls back to rank_fast on any issue
  recommend        -> the public entry the routes/agent call

Everything degrades gracefully: no history -> source-weight radio; LLM error ->
fast path.
"""
from __future__ import annotations

import asyncio
import logging
import re
from typing import Optional

from plugins.music import store, youtube
from plugins.music.youtube import Track, is_duplicate_song

log = logging.getLogger("hermes.music.recommender")

# Higher = trust this source more.
_SOURCE_WEIGHT = {"radio": 1.0, "taste": 0.9, "search": 0.7}


# --------------------------------------------------------------------------- #
#  Candidate generation                                                        #
# --------------------------------------------------------------------------- #
async def build_candidates(
    *,
    seed: Optional[Track],
    profile: dict,
    steer: Optional[str] = None,
) -> list[tuple[Track, str]]:
    """Blend several radio sources into a deduped, novelty-filtered pool."""
    jobs: list[tuple[str, "asyncio.Future"]] = []

    # (a) radio off the currently-playing track
    if seed:
        jobs.append(("radio", youtube.get_recommendations(seed.video_id, seed.title, seed.artist, limit=15)))

    # (b) taste-seeded radios (diversity) from the user's top tracks
    for t in (profile.get("top_tracks") or [])[:3]:
        vid = t.get("videoId")
        if vid and (not seed or vid != seed.video_id):
            jobs.append(("taste", youtube.get_recommendations(vid, t.get("title", ""), t.get("artist", ""), limit=8)))

    # cold start: nothing to seed from → search the steer or top artist
    if not jobs:
        q = (steer or "").strip() or " ".join((profile.get("top_artists") or [])[:2]) or "popular music mix"
        jobs.append(("search", youtube.search(q, limit=15)))

    results = await asyncio.gather(*[c for _, c in jobs], return_exceptions=True)

    disliked = store.disliked_video_ids()
    recent = store.recently_played_ids()
    seen: set[str] = set()
    if seed:
        seen.add(seed.video_id)

    out: list[tuple[Track, str]] = []
    for (source, _), res in zip(jobs, results):
        if isinstance(res, Exception) or not res:
            continue
        for tr in res:
            if tr.video_id in seen or tr.video_id in disliked or tr.video_id in recent:
                continue
            if seed and is_duplicate_song(seed.title, seed.artist, tr.title, tr.artist):
                continue
            seen.add(tr.video_id)
            out.append((tr, source))
    return out


# --------------------------------------------------------------------------- #
#  Ranking — fast (no LLM)                                                      #
# --------------------------------------------------------------------------- #
def rank_fast(cands: list[tuple[Track, str]]) -> list[Track]:
    """Score by source weight, then diversify by artist."""
    scored: list[tuple[float, Track]] = [
        (_SOURCE_WEIGHT.get(source, 0.6), tr) for tr, source in cands
    ]
    scored.sort(key=lambda st: st[0], reverse=True)

    # Greedy artist-diversity pass: avoid three-in-a-row from one artist.
    ordered: list[Track] = []
    recent_artists: list[str] = []
    pool = [t for _, t in scored]
    while pool:
        pick_i = 0
        for i, tr in enumerate(pool):
            if recent_artists[-2:].count(tr.artist) == 0:
                pick_i = i
                break
        tr = pool.pop(pick_i)
        ordered.append(tr)
        recent_artists.append(tr.artist)
    return ordered


# --------------------------------------------------------------------------- #
#  Ranking — LLM DJ (explicit requests / fresh mixes)                          #
# --------------------------------------------------------------------------- #
async def rank_llm(cands: list[tuple[Track, str]], profile: dict, steer: str) -> list[Track]:
    """An LLM DJ reorders the candidate list for a natural-language request.

    We ask for a numbered list of candidate INDICES and parse defensively. The
    model can only pick from the provided candidates (never invents video ids).
    Any problem → rank_fast.
    """
    tracks = [t for t, _ in cands]
    if not tracks:
        return []
    listing = "\n".join(f"[{i}] {t.title} — {t.artist}" for i, t in enumerate(tracks))
    taste = ", ".join((profile.get("top_artists") or [])[:6]) or "unknown"

    sys = (
        "You are a music DJ building a queue for one listener. From the numbered "
        "candidate list, choose and ORDER the best tracks for their request. "
        "Reply with ONLY the chosen indices, best first, one per line like `1. 12`. "
        "No commentary, no new songs — only indices from the list."
    )
    user = f"Listener's usual taste: {taste}.\nRequest: {steer}\n\nCandidates:\n{listing}"

    try:
        from agent.auxiliary_client import async_call_llm, extract_content_or_reasoning

        resp = await async_call_llm(
            task="music_dj",
            messages=[{"role": "system", "content": sys}, {"role": "user", "content": user}],
            temperature=0.4,
        )
        text = (extract_content_or_reasoning(resp) or "").strip()
    except Exception as exc:  # noqa: BLE001
        log.warning("LLM DJ failed: %s", exc)
        return rank_fast(cands)

    if not text:
        return rank_fast(cands)

    idxs: list[int] = []
    for line in text.splitlines():
        m = re.search(r"\[?(\d+)\]?\s*$", line.strip()) or re.search(r"(\d+)", line)
        if m:
            idxs.append(int(m.group(1)))
    picked: list[Track] = []
    used: set[int] = set()
    for i in idxs:
        if 0 <= i < len(tracks) and i not in used:
            used.add(i)
            picked.append(tracks[i])
    picked += [t for i, t in enumerate(tracks) if i not in used]
    return picked or rank_fast(cands)


# --------------------------------------------------------------------------- #
#  Public entry                                                                #
# --------------------------------------------------------------------------- #
async def recommend(
    *,
    seed: Optional[Track],
    steer: Optional[str] = None,
    use_llm: bool = False,
    limit: int = 12,
) -> list[Track]:
    """Return an ordered list of recommended tracks."""
    profile = store.profile()
    cands = await build_candidates(seed=seed, profile=profile, steer=steer)
    if not cands:
        return []
    if use_llm and steer:
        ordered = await rank_llm(cands, profile, steer)
    else:
        ordered = rank_fast(cands)
    return ordered[:limit]
