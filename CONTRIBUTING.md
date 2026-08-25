# Contributing

Thanks for wanting to help. This repo is a teaching resource, so the bar is
simple: **would this have helped you when you were stuck?**

## Ways to contribute

- **Fix an error.** A wrong directive in a tutorial teaches the wrong thing to
  everyone who copies it. These are the most valuable PRs.
- **Improve an explanation.** If a paragraph confused you, it confused others.
- **Add a real-world config.** Something you actually run in production, with
  comments explaining *why* — not just what.
- **Report a problem.** [Open an issue](https://github.com/codewithmuh/nginx-tutorial-series/issues)
  with your OS, `nginx -v`, what you expected, and what happened.

## Before you open a pull request

**1. Validate your configs.** Every `.conf` in this repo passes:

```bash
./scripts/validate-configs.sh
```

A PR that breaks this can't be merged. The script uses Docker when it's
available and a local `nginx` otherwise.

**2. Match the house style.** Configs here are teaching material, so comments
carry the weight:

```nginx
# --- Required for upstream keepalive to actually work ---------------------
proxy_http_version 1.1;
proxy_set_header Connection "";     # clears the default "close"
```

- Explain **why**, not just what — the directive name already says what.
- Flag the traps (`⚠️`) where a wrong choice bites: `add_header` not merging,
  `root` vs `alias`, `last` vs `break`.
- Keep example hostnames as `example.com` and backends on `127.0.0.1`.
- No secrets, no real IPs, no real certificates.

**3. Keep chapter READMEs consistent.** Table of contents, numbered sections,
a troubleshooting table, and a "Files" + "Next" section at the end.

## Steps

```bash
git clone https://github.com/codewithmuh/nginx-tutorial-series.git
cd nginx-tutorial-series
git checkout -b fix/proxy-timeout-explanation

# make your changes
./scripts/validate-configs.sh

git commit -m "Explain why proxy_read_timeout matters for slow endpoints"
git push origin fix/proxy-timeout-explanation
```

Then open a pull request describing what changed and why. Small, focused PRs
get merged fastest.

## Code of Conduct

Be decent to each other. Assume the person asking the "obvious" question is
learning something you already had the luck to be taught. Harassment or
dismissiveness isn't welcome here.
