# Ticket Template Reference

This document defines the structure every generated Linear ticket must follow. Each section is mandatory unless marked optional.

## Title

Imperative verb + specific component or action. Keep it under 80 characters.

Examples:
- "Add JWT validation middleware to API gateway"
- "Create database migration for user_preferences table"
- "Fix race condition in WebSocket reconnection logic"

## Description

1-2 paragraphs covering what this ticket accomplishes and why.

Must include:
- Reference to the spec file: `Spec: path/to/spec.md`
- Reference to the plan file (if one exists): `Plan: path/to/plan.md`
- Brief context on where this fits in the overall work

## Acceptance Criteria

Checkbox format. Every criterion must be **autonomously verifiable** -- an unattended AI agent must be able to confirm completion without human judgment. Each criterion specifies a concrete check: a command to run, an output to observe, or a condition to assert.

```
- [ ] Criterion with verification method
- [ ] Criterion with verification method
```

### Good vs Bad Criteria

**BAD -- not verifiable by an agent:**
- "Authentication is implemented"
- "Error handling is robust"
- "Code is clean and well-structured"
- "Performance is acceptable"

**GOOD -- agent can verify by running a command or checking a concrete outcome:**
- "When POST /api/login with valid credentials, response is 200 with JWT token; verify with `curl -X POST localhost:8000/api/login -d '{\"user\":\"test\",\"pass\":\"test\"}'`"
- "When POST /api/login with invalid credentials, response is 401 with error message; verify with `curl -s -o /dev/null -w '%{http_code}' -X POST localhost:8000/api/login -d '{\"user\":\"test\",\"pass\":\"wrong\"}'` returns 401"
- "`pytest tests/test_auth.py -k test_jwt_expiry` passes (token expires after 3600 seconds)"
- "File `src/middleware/auth.py` exists and contains a class `JWTValidator`; verify with `grep -q 'class JWTValidator' src/middleware/auth.py`"
- "`mypy src/middleware/auth.py` exits with no errors"

### Writing Verifiable Criteria

For each criterion, ask: "Can an agent confirm this by running a single command and checking the exit code or output?" If not, rewrite it until it can.

Patterns that work:
- **Command produces expected output:** "`<command>` outputs `<expected>`"
- **Command exits cleanly:** "`<command>` exits 0"
- **File contains expected content:** "`grep -q '<pattern>' <file>` succeeds"
- **HTTP endpoint returns expected response:** "`curl ...` returns status `<code>` with body containing `<substring>`"
- **Test suite passes:** "`<test command>` passes with no failures"

## Testing Guidance

Specific commands the implementing agent should run to validate its work. Not generic advice -- exact invocations.

```
Run: pytest tests/test_auth.py -k test_jwt_validation
Run: pytest tests/test_auth.py -k test_token_expiry
Edge cases to cover:
- Expired token returns 401
- Malformed token returns 400
- Missing Authorization header returns 401
```

## File Scope

List of file paths this ticket is expected to create or modify. Helps the agent understand boundaries and helps reviewers scope their review.

```
Creates: src/middleware/auth.py
Modifies: src/app.py (register middleware)
Modifies: tests/test_auth.py (add test cases)
Creates: src/schemas/auth.py (request/response models)
```

## Blocked By

Ticket identifiers this ticket depends on, or "None" if it can start immediately.

```
Blocked By: PROJ-101 (database migration must exist first)
```

or

```
Blocked By: None
```

## Full Example

```markdown
Title: Add JWT validation middleware to API gateway

Description:
Implement middleware that validates JWT tokens on protected endpoints.
Tokens are issued by the auth service (PROJ-101) and use RS256 signing.
Spec: docs/specs/authentication.md
Plan: docs/plans/auth-middleware-plan.md

Acceptance Criteria:
- [ ] `pytest tests/test_auth.py -k test_valid_token_passes` passes
- [ ] `pytest tests/test_auth.py -k test_expired_token_returns_401` passes
- [ ] `pytest tests/test_auth.py -k test_malformed_token_returns_400` passes
- [ ] `pytest tests/test_auth.py -k test_missing_header_returns_401` passes
- [ ] `grep -q 'class JWTValidator' src/middleware/auth.py` succeeds
- [ ] `mypy src/middleware/auth.py` exits with no errors
- [ ] `ruff check src/middleware/auth.py` exits with no errors

Testing Guidance:
Run: pytest tests/test_auth.py -v
Edge cases:
- Token signed with wrong key returns 401
- Token with future nbf (not-before) claim returns 401
- Token missing required claims (sub, exp) returns 400

File Scope:
Creates: src/middleware/auth.py
Modifies: src/app.py (register middleware)
Modifies: tests/test_auth.py (add test cases)

Blocked By: PROJ-101 (auth service must issue tokens first)
```
