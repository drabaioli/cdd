# Security Policy

CDD is a workflow project — process documentation, a copy-paste template, and a
handful of shell scripts (the bootstrap, the worktree helpers, the CI smoke and
drift checks). Most "vulnerabilities" here would be in that shell tooling rather
than in a running service, but we take reports seriously regardless.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately through GitHub's **private vulnerability reporting**:

1. Go to the [Security tab](https://github.com/drabaioli/cdd/security) of this
   repository.
2. Click **Report a vulnerability**.
3. Fill in the advisory form.

This keeps the report confidential until a fix is available.

## What to include

- A clear description of the issue and why it's a security concern.
- Steps to reproduce — the command(s) you ran and the affected file(s)
  (for example, a script in `tools/`, `scripts/`, or `template/`).
- The impact you believe it has.

## What to expect

This is a small, single-maintainer project, so responses are best-effort rather
than bound to a formal SLA. You can expect an initial acknowledgement, a
discussion of the issue through the private advisory, and — once a fix lands —
credit in the advisory if you'd like it.

Thanks for helping keep CDD and the projects built on it safe.
