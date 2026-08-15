---
name: security-audit
description: >-
  OWASP Top 10 checks, SQL injection prevention, XSS/CSRF protection, secrets
  management, dependency vulnerability scanning, and secure coding practices.
trigger:
  - "security audit"
  - "vulnerability scan"
  - "security review"
---

# Security Audit

Walk the codebase against OWASP Top 10 (2021): broken access control, cryptographic failures, injection, insecure design, security misconfiguration, vulnerable/outdated components, auth failures, data integrity failures, logging/monitoring failures, SSRF. Standard secure-coding practice (parameterized queries, output encoding, bcrypt for passwords, CSP/CSRF/rate-limit middleware, secrets in env vars not code) applies without needing examples spelled out.

Non-obvious parts specific to this harness: if the code under audit builds prompts from untrusted text (chat input, RAG chunks, scraped content, third-party API data), that is a prompt-injection surface, hand off to skill `prompt-injection-defense` and, for ingested documents, `ingest-scrubbing`. These are not standard OWASP categories and won't get caught by a generic pass.

Run `npm audit` / `snyk test` (or the project's equivalent) for dependency CVEs. Report findings by severity, with the fix, not just the flag.
