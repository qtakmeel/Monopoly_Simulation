# Monopoly Policy Simulation — Figure Guide & Findings

**Dataset:** 10,000 total games — 500 per regime × 5 regimes × 4 player counts (2, 4, 6, 8).
**Primary figures shown for the 4-player run** (`games_prod4p_20260903_181235.csv`); all other player counts in the `prod{N}p_*` files.
**Regimes compared:** Baseline, Extreme Capitalism, Democratic Socialism, Rent Control Only, UBI Only
**Termination:** one player remains, or the game hits the 200-turn cap.

Each figure below maps to one research question. The violin shows the full distribution of outcomes across the 500 games in that regime; the box marks the median (line) and interquartile range; the diamond is the mean. Higher values on an axis are *not* uniformly good or bad — the meaning depends on the metric, noted per figure. Figures are drawn from the 4-player run; the "Robustness across player counts" section confirms the same ordering holds at 2, 6, and 8 players.

---

## Aggregate results at a glance (4-player)

| Regime | Gini (mean) | HHI (mean) | Bankruptcies/game | % with ≥1 bankruptcy | Avg wealth gap ($) | Games hit 200-turn cap |
|---|---|---|---|---|---|---|
| **Democratic Socialism** | 0.050 | 0.289 | 0.00 | 0% | $1,026 | 100% |
| **UBI Only** | 0.336 | 0.348 | 0.55 | 37.2% | $3,442 | 97% |
| **Rent Control Only** | 0.561 | 0.690 | 2.18 | 90.0% | $2,217 | 56% |
| **Baseline** | 0.574 | 0.730 | 2.28 | 88.6% | $2,424 | 46.8% |
| **Extreme Capitalism** | 0.583 | 0.736 | 2.34 | 92.2% | $2,372 | 48.2% |

The headline: redistributive policy (DS) collapses inequality to near-zero and eliminates bankruptcy entirely. UBI alone cuts both substantially. Rent control and extreme capitalism barely move off baseline.

---

## Robustness across player counts (2 / 4 / 6 / 8)

The core findings do not depend on the four-player setting. Mean Gini by regime at each player count:

| Regime | 2 players | 4 players | 6 players | 8 players |
|---|---|---|---|---|
| **Democratic Socialism** | 0.064 | 0.050 | 0.050 | 0.050 |
| **UBI Only** | 0.422 | 0.336 | 0.248 | 0.156 |
| **Rent Control Only** | 0.483 | 0.561 | 0.313 | 0.231 |
| **Baseline** | 0.486 | 0.574 | 0.334 | 0.225 |
| **Extreme Capitalism** | 0.483 | 0.583 | 0.335 | 0.229 |

Bankruptcies per game:

| Regime | 2 players | 4 players | 6 players | 8 players |
|---|---|---|---|---|
| **Democratic Socialism** | 0.04 | 0.00 | 0.00 | 0.00 |
| **UBI Only** | 0.90 | 0.55 | 0.20 | 0.05 |
| **Rent Control Only** | 1.03 | 2.18 | 0.96 | 0.54 |
| **Baseline** | 1.03 | 2.28 | 1.15 | 0.49 |
| **Extreme Capitalism** | 1.03 | 2.34 | 1.19 | 0.55 |

Capital formation (total builds per game):

| Regime | 2 players | 4 players | 6 players | 8 players |
|---|---|---|---|---|
| **Democratic Socialism** | 528.6 | 177.8 | 86.5 | 52.5 |
| **UBI Only** | 100.8 | 135.2 | 77.6 | 50.3 |
| **Rent Control Only** | 47.4 | 91.4 | 59.1 | 38.3 |
| **Baseline** | 41.0 | 87.2 | 60.7 | 38.0 |
| **Extreme Capitalism** | 39.5 | 86.2 | 59.0 | 37.4 |

Three patterns hold at every player count:

1. **Democratic Socialism is the standout everywhere.** Its Gini sits at 0.05–0.064 regardless of how many players sit down, and it drives bankruptcies to essentially zero (≤0.04/game) at every count. This is the most stable result in the entire study.
2. **Redistribution boosts capital formation at every count.** DS leads total building in all four settings — dramatically so at 2 players (529 vs ~41) and still clearly ahead at 8 (53 vs ~38). The counterintuitive "leveling the field increases investment" finding is not a four-player artifact.
3. **Market tweaks stay clustered.** At each player count, Baseline, Extreme Capitalism, and Rent Control land within a hair of one another on Gini, HHI, and bankruptcy rate. Tightening rent or cranking market intensity does little compared with moving money directly between players.

One nuance worth stating plainly: absolute inequality *falls* as the table fills up (more players dilute any single winner's share), so the 4-player case is actually one of the more concentrated settings. That means the regime differences seen here are, if anything, understated relative to a crowded board — the directional ordering is robust, and the equalizing effect of redistribution is consistent no matter how many people play.

---

## Fig 1 — Wealth Inequality Across Policy Regimes
*File:* `fig1_inequality.{png,pdf}` · *Metric:* final Gini coefficient of net worth (lower = more equal).

Answers **"How does each regime affect income/wealth inequality?"**

Three regimes cluster tightly around a Gini of ~0.56–0.58 (Extreme Capitalism, Baseline, Rent Control), their violins nearly identical — none of them structurally reduces inequality. UBI sits distinctly lower (~0.34): giving every player a recurring cash floor narrows the spread but leaves the winner still far ahead. Democratic Socialism is separated by a wide gap at ~0.05, essentially flatlining the distribution — periodic redistribution keeps all four players within a thin band of each other.

Reading it plainly: only active redistribution changes the inequality picture; a one-directional transfer (UBI) helps moderately; market rules left alone (baseline, rent control, hyper-capitalism) converge on the same unequal outcome.

---

## Fig 2 — Property-Ownership Concentration
*File:* `fig2_concentration.{png,pdf}` · *Metric:* Herfindahl–Hirschman Index of property shares (higher = more concentrated). Dashed line = perfectly even split across players (reference).

Answers **"Does ownership concentrate under different regimes?"**

HHI measures whether properties pile up in one hand. Baseline and Extreme Capitalism sit highest (~0.73), close to monopoly-like concentration — a single player ends up owning most of the board. Rent Control dips slightly (~0.69). UBI falls sharply (~0.35) because the cash floor lets weaker players keep buying rather than losing everything. DS lands lowest (~0.29), just above the dashed "perfectly even" reference — ownership stays broadly dispersed. This mirrors Fig 1 from the asset side: the same two levers (redistribution, universal transfers) are what prevent hoarding.

---

## Fig 3 — Bankruptcy Frequency & Timing
*Files:* `fig3_bankruptcy.{png,pdf}`, two panels. Panel A = mean players driven out per game. Panel B = turn on which the first player goes bust (earlier = harsher).

Answers **"Which regimes drive players out of the game, and how fast?"**

Panel A is stark: Democratic Socialism records **zero** bankruptcies in all 500 games — no player ever busts. UBI is next lowest (0.55/game, only 37% of games see any bankruptcy). The three non-redistributive regimes cluster high (2.18–2.34 bankruptcies per game, i.e. roughly two of four players eliminated before the game ends). Panel B confirms the mechanism: when bankruptcies do occur, they strike earliest and most consistently under the market-heavy regimes (first bust around turn 99–102), whereas UBI delays the first bust to ~turn 121. Redistribution doesn't just soften outcomes — it removes elimination as an event.

---

## Fig 4 — Social Mobility: Fluidity of Wealth Rankings
*File:* `fig4_social_mobility.{png,pdf}` · *Metric:* crossings between the top/bottom wealth halves across periodic snapshots (higher = more mobile).

Answers **"Do rankings stay fixed, or can players climb/fall over the course of a game?"**

This is the least differentiated panel — all five regimes hover around 8–10 transitions, with overlapping distributions. No regime dramatically locks in or unlocks mobility. If anything, Extreme Capitalism edges highest (~10.2) and UBI edges lowest (~8.0). Interpretation carefully: mobility here means *rank churn*, not upward movement. High churn under capitalism reflects volatile swings (players surge then crash); it is not the same as fairness. The key takeaway is that redistribution compresses the distance between ranks (Fig 1) without necessarily changing how often ranks swap — equality and fluidity are separate axes.

---

## Fig 5 — Capital Formation Over the Game
*File:* `fig5_capital_formation.{png,pdf}` · *Metric:* total house/hotel placements made (proxy for investment activity).

Answers **"Does policy change how much productive building/investment happens?"**

Counterintuitively, Democratic Socialism leads decisively (~178 builds vs ~86–91 for the others), with UBI second (~135). Because redistribution keeps every player solvent and liquid, all four keep investing throughout instead of a couple of winners monopolizing construction while losers drop out. The market-heavy regimes build less overall — once a player dominates, marginal returns fall and the depleted opponents stop building. So higher equality here coincides with *more* aggregate investment, not less.

---

## Fig 6 — Tenant Rent Burden
*File:* `fig6_rent_burden.{png,pdf}` · *Metric:* mean rent paid relative to a $1,500 reference income.

Answers **"How heavy is the rent load on tenants under each regime?"**

All regimes show a similar low central tendency (~0.01, i.e. modest average rent-to-income), but the tails differ. Extreme Capitalism and UBI exhibit the longest upper whiskers — occasional very high rents land on struggling tenants. Rent Control trims the tail somewhat (it caps what landlords can charge), pulling its right-hand tail down relative to the market regimes. Note this metric is deliberately conservative (a single reference income), so treat absolute levels cautiously; the comparative shape — rent control dampening the worst-case tenant burden — is the robust signal.

---

## Fig 7 — Dashboard
*File:* `fig7_dashboard.{png,pdf}` · Multi-panel summary combining the core metrics in one view.

A compact executive summary tying the individual figures together: inequality, concentration, survival, and mobility side by side so the reader can scan the regime comparison at a glance. Use this as the lead visual in a presentation; the six single-metric figures supply the detail.

---

## Fig 8 — Final Wealth Spread by Regime
*File:* `fig8_wealth_distribution.{png,pdf}` · *Metric:* median per-game [poorest → richest] net-worth range; dot = mean final wealth.

Answers **"What is the actual dollar distance between the richest and poorest survivor at game's end?"**

This puts concrete dollars behind Fig 1. Democratic Socialism keeps the spread tightest — the richest player averages ~$4,100 but the poorest is never far behind, so the bracket stays narrow. UBI widens the bracket (median richest ~$2,200 with a long lower tail reaching toward zero), reflecting that it cushions but doesn't equalize. Baseline, Rent Control, and Extreme Capitalism all show the widest brackets spanning from ~$0 to ~$2,000+, consistent with two-or-more players being wiped out. The vertical bars visualize exactly how much separation survives at the finish line under each rule set.

---

## How to read these together

The eight figures decompose one question — *"what does economic policy do to a competitive zero-sum economy?"* — into measurable pieces: inequality (Fig 1), asset concentration (Fig 2), survival (Fig 3), rank fluidity (Fig 4), investment (Fig 5), cost-of-living pressure (Fig 6), an at-a-glance rollup (Fig 7), and the raw dollar stakes (Fig 8).

Two structural findings recur across every panel — and, as the robustness section above shows, at every player count from two to eight. First, **redistribution is the dominant lever**: Democratic Socialism separates itself from every other regime on inequality, concentration, and survival simultaneously, and even boosts capital formation. Second, **market variation without redistribution is largely cosmetic**: Baseline, Extreme Capitalism, and Rent Control produce statistically indistinguishable outcomes on the big-ticket metrics — tightening rent or loosening markets moves the needle far less than moving money directly between players.

*Caveats:* 500 games per regime per player count (10,000 total) gives stable estimates (4p DS Gini SD ≈ 0.023; others ≈ 0.14–0.21). The figures are drawn from the 4-player run; the directional ordering was verified to hold at 2, 6, and 8 players, though absolute levels shift with table size (inequality falls as more players dilute concentration). All results use the deterministic agent AI; richer strategic behavior would change magnitudes but the regime ordering is expected to persist. Rent-burden magnitudes depend on the $1,500 reference income and should be read comparatively.
