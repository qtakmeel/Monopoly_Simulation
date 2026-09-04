# Monopoly Economic-Policy Monte Carlo Study

A deterministic-agent Monte Carlo simulation of classic American Monopoly used to
compare five economic-policy regimes on wealth concentration, solvency, capital
formation, and social mobility. Built in R (4.4.x) with `R6` game objects,
`data.table` logging, and base-R `parallel` for transparent multi-core execution.

## Research question

How do different fiscal/institutional policy levers — universal basic income,
progressive taxation, rent control, deregulation, and public housing — reshape the
distribution of wealth and the frequency of bankruptcy that emerge from an
otherwise identical market process?

Monopoly is a convenient laboratory: the underlying stochastic process (dice,
cards, chance squares) is fixed and well-understood, so any differences in
outcomes across arms can be attributed to the policy levers we switch on, not to
changes in the "economy" itself.

## The five scenarios

Each arm modifies a shared baseline ruleset by toggling a small set of levers.
Redistributive amounts scale linearly with player count (`n_players / 4`) so the
per-capita fiscal load stays comparable across 2/4/6/8-player games.

| Scenario | Levers switched on |
|---|---|
| **Baseline** | Standard Monopoly rules. No intervention. |
| **Extreme_Capitalism** | Money-granting cards voided (no windfalls); more aggressive buying (`ai_buy_ratio = 1.2`); insolvency ⇒ immediate exit. Maximizes exposure to pure market forces. |
| **Democratic_Socialism** | UBI per turn; 5% progressive income tax on passing GO (capped $200); Luxury Tax capped at $25; free housing construction; soft jail penalty ($50); rent cap $75. Strong redistribution + public goods. |
| **Rent_Control_Only** | Sole lever: hard cap of $50 on any single rent payment. |
| **UBI_Only** | Sole lever: unconditional basic income each turn. |

Full parameter definitions live in [`policy/scenarios.R`](policy/scenarios.R).

## Metrics captured per game

- **Gini coefficient** of final net worth across all players (inequality).
- **Herfindahl–Hirschman Index (HHI)** of property-ownership shares (concentration).
- **Bankruptcy timing**: count of bankruptcies and the turn of the first one.
- **Social mobility**: number of times any player crosses between the bottom and top wealth halves between consecutive periodic snapshots (fluidity of the ranking).
- **Capital formation**: total house/hotel placements over the whole game.
- **Rent burden**: mean rent paid relative to a $1,500 reference income.

Plus descriptive stats: game length, whether the turn cap was hit, winner
identity, and final wealth spread (min/max/mean/sd).

Net worth is valued as `cash + Σ(base price) + Σ(improvement value) − Σ(mortgage
liability)`, where a hotel counts as four house-costs and a mortgaged property
carries a half-price liability. See [`utils/metrics.R`](utils/metrics.R).

## Architecture

```
Monopoly_Simulation/
├── main.R                 # CLI entry point
├── data/
│   └── board.R            # Official US board layout, prices, Chance/Chest decks
├── game/
│   ├── player.R           # Player R6 class (movement, holdings, net worth)
│   ├── bank.R             # Bank R6 class (ownership ledger, card draws)
│   └── engine.R           # Engine R6 class (turn loop, AI, settlement, bankruptcy)
├── policy/
│   └── scenarios.R        # The five scenario configs + player-count scaling
├── utils/
│   └── metrics.R          # Gini, HHI, net-worth valuation, aggregation helpers
├── run/
│   └── run_simulations.R  # Parallel Monte Carlo driver + output writers
├── inst/
│   ├── rulebook/          # (reserved) formal rules specification
│   └── tests/             # (reserved) unit tests
└── results/               # CSV + markdown outputs (timestamped)
```

### Game mechanics implemented

Standard American Monopoly: 40-space board, 22 streets in 8 color groups, 4
railroads, 2 utilities, 3 Chance and 3 Community Chest squares, Income Tax ($200),
Luxury Tax ($100), Go To Jail, Free Parking. Dice with doubles (roll again, three
in a row → jail), jail resolution in priority order (get-out card → pay fine →
forced payment → roll for doubles), auctions on unowned properties, group-complete
building with even distribution, voluntary mortgages, and utility-based trading.

Termination: one player remains **or** the turn count exceeds `max_turns`
(default 200). A configurable `allow_liquidation` flag (default off) controls
whether insolvent players sell assets before going bankrupt; keeping it off makes
"bankruptcy timing" a meaningful metric rather than an artifact of asset dumping.

Deterministic agent AI: buy when `cash > ai_buy_ratio × price`; build evenly on
complete groups; mortgage lowest-rent properties first when short; trade only when
it completes a group for both parties.

### Parallelism

[`run/run_simulations.R`](run/run_simulations.R) spawns a PSOCK cluster via
`parallel::makeCluster` (portable across Windows/macOS/Linux). Each worker sources
the full project so the R6 classes are available in child sessions; the per-game
worker function is exported with `clusterExport`. With `--workers 1` (or omitted
on a single-core box) it falls back to sequential `lapply`. One cluster is reused
across all five scenarios to amortize spawn cost.

## Running

From the project root:

```sh
# Quick smoke test (4 players, 10 sims, 2 workers)
Rscript main.R --players 4 --sims 10 --workers 2

# Full study: 4 players, 500 sims per scenario, all-but-one core
Rscript main.R --players 4 --sims 500

# 8-player variant, tagged for comparison
Rscript main.R --players 8 --sims 200 --tag eightp

# Only two arms, quieter output
Rscript main.R --scenarios Baseline,Democratic_Socialism --quiet
```

Options:

```
--players N      players per game (2/4/6/8)        [default 4]
--sims N         replications per scenario          [default 100]
--max-turns N    turn cap per game                  [default 200]
--workers N      parallel workers (<=1 sequential)  [default cores-1]
--scenarios L    comma-separated scenario subset    [default all]
--out DIR        output directory                   [default results]
--tag STR        filename tag                       [default '']
--quiet          suppress progress
--help           show help
```

Outputs (written to `results/`, timestamped):

- `games_<tag>_<stamp>.csv` — one row per simulated game (all metrics).
- `summary_<tag>_<stamp>.csv` — aggregate statistics per scenario.
- `summary_<tag>_<stamp>.md` — human-readable markdown table.

## Early observations (small samples, n≈4–5)

Directionally, the arms behave as the theory predicts, though larger samples are
needed for inference: Democratic Socialism collapses inequality (Gini ≈ 0.05) with
zero bankruptcies and games that run to the turn cap; UBI compresses inequality
moderately; Extreme Capitalism produces the most mobility churn alongside high
volatility. Rent Control Only showed unexpectedly *high* concentration in tiny
samples — capping rents starves landlords of cash flow, which can accelerate a
single player's dominance of property ownership while tenants stay poor. This is
exactly the kind of counterintuitive interaction the simulation is meant to surface;
confirm with adequate replication before drawing conclusions.

## Notes & limitations

Agents are deliberately simple heuristics, not optimal strategists; results reflect
a stylized economy, not expert play. The board uses official US pricing. Card decks
are drawn without replacement and reshuffled when exhausted. Because games are
long-tailed (many hit the 200-turn cap), variance across seeds is high — report
means with standard deviations and use several hundred simulations per arm for any
claim you intend to defend.
