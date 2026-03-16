# Pre-existing pattern_match_cov warnings for defensive catch-all function clauses.
# These clauses exist to guard against unexpected call sites at runtime even though
# dialyzer can statically prove they are unreachable given current callers.
[
  {"lib/symphony_elixir/claude/app_server.ex", :pattern_match_cov},
]
