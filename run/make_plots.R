# ============================================================================
# make_plots.R — Visualization suite for the Monopoly policy study
# ----------------------------------------------------------------------------
# Reads the per-game results CSV (from run_simulations.R) and produces one
# publication-style figure per research question, plus a combined dashboard.
# Outputs PNG + PDF into results/figures/.
#
# Figures:
#   fig1_inequality.png      Gini coefficient by scenario (distribution + mean)
#   fig2_concentration.png   HHI / property-ownership concentration
#   fig3_bankruptcy.png      Bankruptcy frequency & timing
#   fig4_social_mobility.png Wealth-ranking fluidity over time
#   fig5_capital_formation.png Capital formation (houses/hotels built)
#   fig6_rent_burden.png     Rent burden by scenario
#   fig7_dashboard.png       Combined multi-panel overview
#   fig8_wealth_distribution.png Final net-worth distributions (box/violin)
#
# Usage:
#   Rscript run/make_plots.R --input results/games_prod4p_....csv
#   Rscript run/make_plots.R            # auto-picks newest games_*.csv
# ============================================================================

suppressMessages({
  library(data.table)
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(patchwork)
  library(scales)
})

# ---- Args -------------------------------------------------------------------
get_arg <- function(flag, default = NULL) {
  args <- commandArgs(trailingOnly = TRUE)
  i <- match(flag, args)
  if (!is.na(i) && i < length(args)) args[i + 1] else default
}

find_latest_games_csv <- function(dir = "results") {
  f <- list.files(dir, pattern = "^games_.*\\.csv$", full.names = TRUE)
  if (length(f) == 0) stop("No games_*.csv found in ", dir)
  f[order(file.info(f)$mtime)][1]
}

INPUT   <- get_arg("--input", find_latest_games_csv())
OUTDIR  <- get_arg("--outdir", file.path(dirname(INPUT), "figures"))
TAG     <- basename(sub("\\.csv$", "", INPUT))

dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)
cat("Reading:", INPUT, "\nWriting figures to:", OUTDIR, "\n\n")

dt <- fread(INPUT)

# Consistent scenario ordering & labels. Raw keys -> human display names.
RAW_KEY  <- c("Baseline", "Extreme_Capitalism", "Democratic_Socialism",
              "Rent_Control_Only", "UBI_Only")
DISPLAY  <- c("Baseline", "Extreme Capitalism", "Democratic Socialism",
              "Rent Control Only", "UBI Only")
KEY_TO_DISPLAY <- stats::setNames(DISPLAY, RAW_KEY)

# Relabel the column once; every plot inherits readable x-axis labels.
dt$scenario <- factor(KEY_TO_DISPLAY[as.character(dt$scenario)],
                      levels = DISPLAY)

# Color palette keyed by raw scenario key.
PAL_RAW <- c(Baseline = "#7f7f7f",
             Extreme_Capitalism = "#d95f02",
             Democratic_Socialism = "#1b9e77",
             Rent_Control_Only = "#abdda4",
             UBI_Only = "#7570b3")
PAL <- PAL_RAW[names(PAL_RAW)[match(DISPLAY, RAW_KEY)]]

theme_study <- theme_minimal(base_size = 13) +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold", size = 15, hjust = 0),
        legend.position = "none")

save_fig <- function(pgt, name, w = 8, h = 5.5) {
  png_path <- file.path(OUTDIR, paste0(name, ".png"))
  pdf_path <- file.path(OUTDIR, paste0(name, ".pdf"))
  ggsave(png_path, pgt, width = w, height = h, dpi = 150)
  ggsave(pdf_path, pgt, width = w, height = h)
  cat("  wrote", name, "(png+pdf)\n")
  invisible(list(png = png_path, pdf = pdf_path))
}

# ============================================================================
# FIG 1 — Inequality: Gini coefficient by scenario
# ============================================================================
cat("[1/8] Inequality (Gini)...\n")
fig1 <- dt %>%
  ggplot(aes(x = reorder(scenario, -gini_final), y = gini_final, fill = scenario)) +
  geom_violin(scale = "width", alpha = 0.55, na.rm = TRUE) +
  geom_boxplot(width = 0.15, outlier.size = 0, fill = "white", alpha = 0.8) +
  stat_summary(fun = mean, geom = "point", shape = 18, size = 3, color = "black") +
  labs(title = "Wealth Inequality Across Policy Regimes",
       subtitle = "Final Gini coefficient of net worth (lower = more equal)",
       x = NULL, y = "Gini coefficient") +
  scale_fill_manual(values = PAL) +
  theme_study
save_fig(fig1, "fig1_inequality")

# ============================================================================
# FIG 2 — Concentration: HHI of property ownership
# ============================================================================
cat("[2/8] Concentration (HHI)...\n")
fig2 <- dt %>%
  ggplot(aes(x = reorder(scenario, -hhi_final), y = hhi_final, fill = scenario)) +
  geom_violin(scale = "width", alpha = 0.55, na.rm = TRUE) +
  geom_boxplot(width = 0.15, outlier.size = 0, fill = "white", alpha = 0.8) +
  stat_summary(fun = mean, geom = "point", shape = 18, size = 3, color = "black") +
  geom_hline(yintercept = 0.25, linetype = "dashed", color = "grey40") +
  labs(title = "Property-Ownership Concentration",
       subtitle = "Herfindahl–Hirschman Index of property shares (higher = more concentrated)\nDashed line = perfectly even split across players (reference)",
       x = NULL, y = "HHI") +
  scale_fill_manual(values = PAL) +
  coord_cartesian(ylim = c(0, NA)) +
  theme_study
save_fig(fig2, "fig2_concentration")

# ============================================================================
# FIG 3 — Bankruptcy: frequency and timing
# ============================================================================
cat("[3/8] Bankruptcy frequency & timing...\n")
bk_freq <- dt %>%
  group_by(scenario) %>%
  summarise(mean_nk = mean(n_bankruptcies),
            pct_any = 100 * mean(n_bankruptcies > 0), .groups = "drop") %>%
  mutate(scenario = factor(scenario, levels = DISPLAY))

bk_timing <- dt %>% filter(!is.na(first_bankruptcy_turn)) %>%
  mutate(scenario = factor(scenario, levels = DISPLAY))

# Two-line short labels so the side-by-side panels don't collide.
FIG3_LAB <- c("Baseline" = "Baseline", "Extreme Capitalism" = "Extreme\nCapitalism",
              "Democratic Socialism" = "Democratic\nSocialism",
              "Rent Control Only" = "Rent Control\nOnly", "UBI Only" = "UBI Only")

fig3a <- bk_freq %>%
  arrange(desc(mean_nk)) %>%
  mutate(scenario = factor(scenario, levels = rev(DISPLAY))) %>%
  ggplot(aes(x = scenario, y = mean_nk, fill = scenario)) +
  geom_col(alpha = 0.85, width = 0.6) +
  geom_text(aes(label = sprintf("%.2f", mean_nk)), vjust = -0.6, size = 4) +
  labs(title = "Average Bankruptcies Per Game",
       subtitle = "Mean number of players driven out of the game",
       x = NULL, y = "Avg bankruptcies / game") +
  scale_x_discrete(labels = FIG3_LAB) +
  scale_fill_manual(values = PAL) +
  theme_study

fig3b <- bk_timing %>%
  ggplot(aes(x = scenario, y = first_bankruptcy_turn, fill = scenario)) +
  geom_violin(scale = "width", alpha = 0.55, na.rm = TRUE) +
  geom_boxplot(width = 0.15, outlier.size = 0.5, fill = "white", alpha = 0.8) +
  labs(title = "Timing of First Bankruptcy",
       subtitle = "Turn on which the first player goes bust (earlier = harsher regime)",
       x = NULL, y = "Turn of first bankruptcy") +
  scale_x_discrete(labels = FIG3_LAB) +
  scale_fill_manual(values = PAL) +
  theme_study

fig3 <- (fig3a | fig3b) + plot_annotation(tag_levels = "A")
save_fig(fig3, "fig3_bankruptcy", w = 12, h = 6)

# ============================================================================
# FIG 4 — Social mobility: wealth-ranking fluidity
# ============================================================================
cat("[4/8] Social mobility...\n")
fig4 <- dt %>%
  ggplot(aes(x = reorder(scenario, -social_mobility), y = social_mobility, fill = scenario)) +
  geom_violin(scale = "width", alpha = 0.55, na.rm = TRUE) +
  geom_boxplot(width = 0.15, outlier.size = 0, fill = "white", alpha = 0.8) +
  stat_summary(fun = mean, geom = "point", shape = 18, size = 3, color = "black") +
  labs(title = "Social Mobility: Fluidity of Wealth Rankings",
       subtitle = "Crossings between top/bottom wealth halves across snapshots (higher = more mobile)",
       x = NULL, y = "Mobility transitions") +
  scale_fill_manual(values = PAL) +
  theme_study
save_fig(fig4, "fig4_social_mobility")

# ============================================================================
# FIG 5 — Capital formation: houses/hotels built
# ============================================================================
cat("[5/8] Capital formation...\n")
fig5 <- dt %>%
  ggplot(aes(x = reorder(scenario, -capital_formation), y = capital_formation, fill = scenario)) +
  geom_violin(scale = "width", alpha = 0.55, na.rm = TRUE) +
  geom_boxplot(width = 0.15, outlier.size = 0, fill = "white", alpha = 0.8) +
  stat_summary(fun = mean, geom = "point", shape = 18, size = 3, color = "black") +
  labs(title = "Capital Formation Over the Game",
       subtitle = "Total house/hotel placements made (proxy for investment activity)",
       x = NULL, y = "Build actions") +
  scale_fill_manual(values = PAL) +
  theme_study
save_fig(fig5, "fig5_capital_formation")

# ============================================================================
# FIG 6 — Rent burden
# ============================================================================
cat("[6/8] Rent burden...\n")
fig6 <- dt %>%
  ggplot(aes(x = reorder(scenario, -rent_burden_mean), y = rent_burden_mean, fill = scenario)) +
  geom_violin(scale = "width", alpha = 0.55, na.rm = TRUE) +
  geom_boxplot(width = 0.15, outlier.size = 0, fill = "white", alpha = 0.8) +
  stat_summary(fun = mean, geom = "point", shape = 18, size = 3, color = "black") +
  labs(title = "Tenant Rent Burden",
       subtitle = "Mean rent paid relative to a $1,500 reference income",
       x = NULL, y = "Rent burden (rent / $1500)") +
  scale_fill_manual(values = PAL) +
  theme_study
save_fig(fig6, "fig6_rent_burden")

# ============================================================================
# FIG 7 — Dashboard: combined multi-panel overview
# ============================================================================
cat("[7/8] Dashboard...\n")
# Short x-axis labels for the compact dashboard panels (keyed by display name).
DASH_SHORT <- c("Baseline" = "Base", "Extreme Capitalism" = "ExtCap",
                "Democratic Socialism" = "DemSoc", "Rent Control Only" = "RentCtrl",
                "UBI Only" = "UBI")
DASH_XSCALE <- scale_x_discrete(labels = DASH_SHORT)
DASH_XTHEME <- theme(axis.text.x = element_text(size = 9))

dash_gini <- dt %>%
  ggplot(aes(x = scenario, y = gini_final, fill = scenario)) +
  geom_boxplot(width = 0.5, outlier.size = 0.4, alpha = 0.7) +
  stat_summary(fun = mean, geom = "point", shape = 18, size = 2.5, color = "black") +
  labs(title = "A · Inequality (Gini)", x = NULL, y = "Gini") +
  scale_fill_manual(values = PAL) + DASH_XSCALE + DASH_XTHEME + theme_study

dash_hhi <- dt %>%
  ggplot(aes(x = scenario, y = hhi_final, fill = scenario)) +
  geom_boxplot(width = 0.5, outlier.size = 0.4, alpha = 0.7) +
  stat_summary(fun = mean, geom = "point", shape = 18, size = 2.5, color = "black") +
  labs(title = "B · Concentration (HHI)", x = NULL, y = "HHI") +
  scale_fill_manual(values = PAL) + DASH_XSCALE + DASH_XTHEME + theme_study

dash_bk <- dt %>%
  ggplot(aes(x = scenario, y = n_bankruptcies, fill = scenario)) +
  geom_boxplot(width = 0.5, outlier.size = 0.4, alpha = 0.7) +
  stat_summary(fun = mean, geom = "point", shape = 18, size = 2.5, color = "black") +
  labs(title = "C · Bankruptcies / game", x = NULL, y = "Count") +
  scale_fill_manual(values = PAL) + DASH_XSCALE + DASH_XTHEME + theme_study

dash_mob <- dt %>%
  ggplot(aes(x = scenario, y = social_mobility, fill = scenario)) +
  geom_boxplot(width = 0.5, outlier.size = 0.4, alpha = 0.7) +
  stat_summary(fun = mean, geom = "point", shape = 18, size = 2.5, color = "black") +
  labs(title = "D · Social mobility", x = NULL, y = "Transitions") +
  scale_fill_manual(values = PAL) + DASH_XSCALE + DASH_XTHEME + theme_study

dash_cap <- dt %>%
  ggplot(aes(x = scenario, y = capital_formation, fill = scenario)) +
  geom_boxplot(width = 0.5, outlier.size = 0.4, alpha = 0.7) +
  stat_summary(fun = mean, geom = "point", shape = 18, size = 2.5, color = "black") +
  labs(title = "E · Capital formation", x = NULL, y = "Builds") +
  scale_fill_manual(values = PAL) + DASH_XSCALE + DASH_XTHEME + theme_study

dash_len <- dt %>%
  ggplot(aes(x = scenario, y = game_length, fill = scenario)) +
  geom_boxplot(width = 0.5, outlier.size = 0.4, alpha = 0.7) +
  stat_summary(fun = mean, geom = "point", shape = 18, size = 2.5, color = "black") +
  labs(title = "F · Game length (turns)", x = NULL, y = "Turns") +
  scale_fill_manual(values = PAL) + DASH_XSCALE + DASH_XTHEME + theme_study

n_per_regime <- nrow(dt) / length(unique(dt$scenario))
n_players_val <- as.integer(as.character(unique(dt$n_players)))

dashboard <- ((dash_gini | dash_hhi | dash_bk) / (dash_mob | dash_cap | dash_len)) +
  plot_annotation(
    title = "Monopoly Policy Simulation — Six-Metric Overview",
    subtitle = sprintf("%d games per regime · %d-player games",
                       round(n_per_regime), n_players_val),
    theme = theme(plot.title = element_text(face = "bold", size = 16),
                  plot.subtitle = element_text(size = 11, color = "grey40"))
  )
save_fig(dashboard, "fig7_dashboard", w = 13, h = 8)

# ============================================================================
# FIG 8 — Final wealth distribution (raw dollars)
# ============================================================================
cat("[8/8] Final wealth distributions...\n")
# Reconstruct final wealth vectors isn't stored per-player; use min/max/mean/sd
# band chart as a robust alternative showing spread + central tendency.
band <- dt %>%
  group_by(scenario) %>%
  summarise(lo = quantile(wealth_min, 0.5), hi = quantile(wealth_max, 0.5),
             mid = mean(wealth_mean), sd = mean(wealth_sd), .groups = "drop") %>%
  mutate(scenario = factor(scenario, levels = DISPLAY))

fig8 <- band %>%
  ggplot(aes(x = reorder(scenario, -mid), y = mid, fill = scenario)) +
  geom_pointrange(aes(ymin = lo, ymax = hi), colour = "grey30", fatten = 2) +
  geom_point(size = 4, shape = 18) +
  labs(title = "Final Wealth Spread by Regime",
       subtitle = "Median of per-game [poorest richest] range; dot = mean final wealth",
       x = NULL, y = "Net worth ($)") +
  scale_fill_manual(values = PAL) +
  scale_y_continuous(labels = function(v) paste0("$", formatC(v, big.mark = ","))) +
  theme_study
save_fig(fig8, "fig8_wealth_distribution")

cat("\nAll figures written to:", OUTDIR, "\n")
