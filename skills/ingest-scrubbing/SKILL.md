---
name: ingest-scrubbing
description: >-
  Sanitize documents at ingestion time, before they're embedded and indexed
  in a RAG/vector store. Different attack surface from prompt-injection-defense:
  the poison sits in the corpus and fires whenever a later, unrelated query
  happens to retrieve it.
trigger:
  - "ingest pipeline"
  - "document ingestion"
  - "embed documents"
  - "vector store"
  - "rag pipeline"
  - "knowledge base upload"
---

# Ingest Scrubbing

Companion to [[prompt-injection-defense]]. That skill hardens the runtime
request path (a user's message, a tool's result). This one hardens the write
path: anything that gets embedded and stored so a *future, unrelated* query
can retrieve it.

## Why this is a distinct problem

Indirect prompt injection via a poisoned corpus is worse than a poisoned
chat message in one specific way: the attacker doesn't need to be the one
asking the question. They plant instructions in a PDF, a scraped web page,
an uploaded spreadsheet — anything that ends up in the knowledge base — and
wait. Weeks later, someone else's innocent query retrieves that chunk and
the injected instructions ride along into that person's LLM context.

This was the gap found auditing a reference RAG codebase (rag-supreme,
mid-2026): ingestion did file-type sniffing and text extraction, but the
only "cleaning" step was `.strip()`. Retrieved chunks went into the prompt
verbatim, with no scrub at write time and no re-check at read time.

## Where to scrub

Two checkpoints, not one:

1. **At ingestion** (before embedding/indexing) — this skill.
2. **At retrieval** (before the retrieved chunk enters a prompt) — reuse
   [[prompt-injection-defense]]'s baseline (`sanitize_untrusted_text`,
   `flag_injection_attempt`) on every retrieved chunk. Retrieval is just
   another untrusted-text-into-prompt path.

Scrubbing only at ingestion misses new attack patterns discovered after a
document was already indexed. Scrubbing only at retrieval means known-bad
documents sit in the corpus indefinitely, silently retrievable by anyone.
Do both.

## Ingestion-time scrub

```python
import re

_ZERO_WIDTH = re.compile("[\u200b\u200e\u200f\u2060\ufeff\u2028-\u202f]")
_HTML_TAG = re.compile(r"<[^>]+>")
_MD_IMAGE = re.compile(r"!\[.*?\]\([^)]*\)")

def scrub_document_for_ingest(text: str, max_chars: int = 500_000) -> tuple[str, list[str]]:
    """Returns (cleaned_text, flags). Flags don't block ingestion by default —
    a flagged doc still gets indexed but tagged, so a human can review the
    queue without every upload stalling on a false positive."""
    flags = []
    if _ZERO_WIDTH.search(text):
        flags.append("hidden_unicode")
    if _MD_IMAGE.search(text) or "<img" in text.lower():
        flags.append("embedded_markup_exfil_pattern")
    if len(text) > max_chars:
        flags.append("oversized_document")

    text = _ZERO_WIDTH.sub("", text)
    text = _HTML_TAG.sub(" ", text)  # strip tags; keep visible text
    text = re.sub(r"\s+", " ", text).strip()
    return text[:max_chars], flags
```

Store the `flags` alongside the chunk's metadata (not just in a log) so a
retrieval-time check or a review UI can act on them without re-scanning.

## PII redaction (optional, scope to what you actually need)

Only add this if the corpus can contain PII you don't want retrievable
verbatim (SSNs, account numbers, emails in a support-ticket corpus). Don't
add it by default — most internal knowledge bases don't need it, and a
half-built redaction pass gives false confidence. If you do need it:
`presidio` (Microsoft) or a targeted regex allowlist for the specific PII
types your corpus actually contains — not a generic NER model you're not
prepared to tune false-positive rates on.

## What NOT to over-build

- Don't run an LLM-as-judge classifier on every ingested chunk by default —
  that's Tier 3 territory (see [[prompt-injection-defense]]). Start with the
  regex/structural scrub above; add ML scanning only if the corpus is
  populated by untrusted/public submissions at volume.
- Don't silently drop flagged documents. Flag-and-queue, same principle as
  the runtime skill: a human decides, the system surfaces information.
- Don't scrub only once. If you add a new pattern to `scrub_document_for_ingest`,
  re-scan the existing corpus — old documents don't retroactively benefit
  from a new check.

## Checklist

- [ ] Every document is scrubbed (zero-width Unicode, HTML tags, markdown image exfil) before embedding
- [ ] Flags are stored as chunk metadata, not just logged
- [ ] Retrieval path re-applies `prompt-injection-defense`'s baseline to retrieved chunks (scrubbing at ingest alone is not enough)
- [ ] Oversized documents are capped, not silently truncated without a flag
- [ ] PII redaction is added only if the corpus actually needs it, scoped to the specific PII types present
- [ ] A corpus re-scan path exists for when scrub rules change
