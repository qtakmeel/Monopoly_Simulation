# ============================================================================
# board.R — Static Monopoly board definition (standard US edition)
# ----------------------------------------------------------------------------
# A single authoritative positional table defines all 40 squares (pos 1..40).
# Property rows carry purchase price, color group, base rent, full house/hotel
# rent schedule, and per-house improvement cost. Railroads/utilities have no
# color group. Chance / Community Chest decks are effect descriptors interpreted
# by the engine's apply_card(); scenario filtering of money-granting cards is
# done at draw time via CARD_GRANTS_MONEY().
#
# Official US Monopoly board anchor positions (verified against the physical
# game layout, counting clockwise from GO=1):
#   GO=1 | Income Tax=5 ($200) | Luxury Tax=39 ($100)
#   Just Visiting Jail=11 | Free Parking=21 | Go To Jail=31
#   Chance = {8,23,37} ; Community Chest = {3,18,34}
# ============================================================================

# --- Space types -------------------------------------------------------------
TYPE_GO         <- "GO"
TYPE_PROPERTY   <- "PROPERTY"
TYPE_RAILROAD   <- "RAILROAD"
TYPE_UTIL       <- "UTILITY"
TYPE_TAX        <- "TAX"
TYPE_CHANCE     <- "CHANCE"
TYPE_CHEST      <- "CHEST"
TYPE_JAIL       <- "JAIL"
TYPE_PARKING    <- "PARKING"
TYPE_GOTO       <- "GOTO"

# --- Color groups ------------------------------------------------------------
GROUP_BROWN  <- "brown"; GROUP_LIGHT <- "lightblue"; GROUP_PINK <- "pink"
GROUP_ORANGE <- "orange"; GROUP_RED <- "red"; GROUP_YELLOW <- "yellow"
GROUP_GREEN  <- "green"; GROUP_DARK <- "darkblue"

# Base-rent vector per group: [1]=base, [2..5]=1-4 houses, [6]=hotel.
PROP_RENT_BASE <- list(
  brown    = c( 2, 10, 30, 90, 160, 250),
  lightblue= c( 4, 20, 60, 180, 320, 450),
  pink     = c( 6, 30, 90, 270, 400, 550),
  orange   = c( 6, 30, 90, 270, 400, 550),
  red      = c( 8, 40, 100, 300, 450, 600),
  yellow   = c(10, 50, 150, 450, 625, 750),
  green    = c(12, 60, 180, 500, 700, 900),
  darkblue = c(20,100, 300, 900,1100,1200)
)
IMPROVE_COST <- c(brown=50, lightblue=50, pink=100, orange=100,
                  red=150, yellow=150, green=200, darkblue=200)

# ---------------------------------------------------------------------------
# Authoritative 40-square table. Each row: pos, name, type, group, price, tax.
# Streets get their rent schedule from PROP_RENT_BASE[group].
# ---------------------------------------------------------------------------
.SQ <- function(pos, name, type, group="", price=NA_real_, tax=0L, goto_pos=NA_integer_)
  data.frame(pos=pos, name=name, type=type, group=group,
             price=price, tax=tax, goto_pos=goto_pos, stringsAsFactors=FALSE)

BOARD_LAYOUT <- rbind(
  .SQ(1,  "Go",                     TYPE_GO,        "",               NA_real_),
  .SQ(2,  "Mediterranean Avenue",   TYPE_PROPERTY,  GROUP_BROWN,      60),
  .SQ(3,  "Community Chest",        TYPE_CHEST),
  .SQ(4,  "Baltic Avenue",          TYPE_PROPERTY,  GROUP_BROWN,      60),
  .SQ(5,  "Income Tax",             TYPE_TAX,        "",              NA_real_, 200),
  .SQ(6,  "Reading Railroad",       TYPE_RAILROAD,   "",              200),
  .SQ(7,  "Oriental Avenue",        TYPE_PROPERTY,  GROUP_LIGHT,      60),
  .SQ(8,  "Chance",                 TYPE_CHANCE),
  .SQ(9,  "Vermont Avenue",         TYPE_PROPERTY,  GROUP_LIGHT,     100),
  .SQ(10, "Connecticut Avenue",     TYPE_PROPERTY,  GROUP_LIGHT,     100),
  .SQ(11, "Just Visiting Jail",     TYPE_JAIL),
  .SQ(12, "St. Charles Place",      TYPE_PROPERTY,  GROUP_PINK,      120),
  .SQ(13, "Electric Company",       TYPE_UTIL,       "",              150),
  .SQ(14, "States Avenue",          TYPE_PROPERTY,  GROUP_PINK,      120),
  .SQ(15, "Virginia Avenue",        TYPE_PROPERTY,  GROUP_PINK,      120),
  .SQ(16, "Pennsylvania Railroad",  TYPE_RAILROAD,   "",              200),
  .SQ(17, "St. James Place",        TYPE_PROPERTY,  GROUP_ORANGE,    140),
  .SQ(18, "Community Chest",        TYPE_CHEST),
  .SQ(19, "Tennessee Avenue",       TYPE_PROPERTY,  GROUP_ORANGE,    140),
  .SQ(20, "New York Avenue",        TYPE_PROPERTY,  GROUP_ORANGE,    140),
  .SQ(21, "Free Parking",           TYPE_PARKING),
  .SQ(22, "Kentucky Avenue",        TYPE_PROPERTY,  GROUP_RED,       160),
  .SQ(23, "Chance",                 TYPE_CHANCE),
  .SQ(24, "Indiana Avenue",         TYPE_PROPERTY,  GROUP_RED,       160),
  .SQ(25, "Illinois Avenue",        TYPE_PROPERTY,  GROUP_RED,       160),
  .SQ(26, "B&O Railroad",           TYPE_RAILROAD,   "",              200),
  .SQ(27, "Atlantic Avenue",        TYPE_PROPERTY,  GROUP_YELLOW,    180),
  .SQ(28, "Ventnor Avenue",         TYPE_PROPERTY,  GROUP_YELLOW,    180),
  .SQ(29, "Water Works",            TYPE_UTIL,       "",              150),
  .SQ(30, "Marvin Gardens",         TYPE_PROPERTY,  GROUP_YELLOW,    180),
  .SQ(31, "Go To Jail",             TYPE_GOTO,       "",              NA_real_, 0, 11),
  .SQ(32, "Pacific Avenue",         TYPE_PROPERTY,  GROUP_GREEN,     200),
  .SQ(33, "Nevada Avenue",          TYPE_PROPERTY,  GROUP_GREEN,     200),
  .SQ(34, "Community Chest",        TYPE_CHEST),
  .SQ(35, "Pennsylvania Avenue",    TYPE_PROPERTY,  GROUP_GREEN,     200),
  .SQ(36, "Short Line",             TYPE_RAILROAD,   "",              200),
  .SQ(37, "Chance",                 TYPE_CHANCE),
  .SQ(38, "Park Place",             TYPE_PROPERTY,  GROUP_DARK,      220),
  .SQ(39, "Luxury Tax",             TYPE_TAX,        "",              NA_real_, 100),
  .SQ(40, "Boardwalk",              TYPE_PROPERTY,  GROUP_DARK,      220)
)

# Attach rent schedules + improve cost for streets; set rail base rent.
.fr <- vector("list", nrow(BOARD_LAYOUT))
.br <- rep(NA_real_, nrow(BOARD_LAYOUT)); .ic <- rep(NA_real_, nrow(BOARD_LAYOUT))
for (i in seq_len(nrow(BOARD_LAYOUT))) {
  if (BOARD_LAYOUT$type[i] == TYPE_PROPERTY) {
    g <- BOARD_LAYOUT$group[i]
    .br[i] <- PROP_RENT_BASE[[g]][1]; .fr[[i]] <- PROP_RENT_BASE[[g]]; .ic[i] <- IMPROVE_COST[g]
  } else if (BOARD_LAYOUT$type[i] == TYPE_RAILROAD) {
    .br[i] <- 25; .fr[[i]] <- NULL; .ic[i] <- NA_real_
  } else if (BOARD_LAYOUT$type[i] == TYPE_UTIL) {
    .br[i] <- 0; .fr[[i]] <- NULL; .ic[i] <- NA_real_
  } else {
    .br[i] <- NA_real_; .fr[[i]] <- NULL; .ic[i] <- NA_real_
  }
}
BOARD_LAYOUT$base_rent    <- .br
BOARD_LAYOUT$full_rents   <- .fr
BOARD_LAYOUT$improve_cost <- .ic
stopifnot(nrow(BOARD_LAYOUT) == 40, !any(duplicated(BOARD_LAYOUT$pos)))

# Group membership lookup: positions belonging to each color group.
GROUP_POSITIONS <- list()
for (g in names(PROP_RENT_BASE)) GROUP_POSITIONS[[g]] <- which(BOARD_LAYOUT$group == g)

# Full board as a plain list keyed by position (string).
BUILD_BOARD <- function() {
  b <- lapply(seq_len(nrow(BOARD_LAYOUT)), function(i) {
    list(pos = BOARD_LAYOUT$pos[i], name = BOARD_LAYOUT$name[i],
         type = BOARD_LAYOUT$type[i], group = BOARD_LAYOUT$group[i],
         price = BOARD_LAYOUT$price[i], base_rent = BOARD_LAYOUT$base_rent[i],
         full_rents = BOARD_LAYOUT$full_rents[[i]],
         improve_cost = BOARD_LAYOUT$improve_cost[i],
         tax = BOARD_LAYOUT$tax[i], goto_pos = BOARD_LAYOUT$goto_pos[i])
  })
  names(b) <- as.character(BOARD_LAYOUT$pos)
  b
}

# ---------------------------------------------------------------------------
# Card decks. Effect vocabulary:
#   money(+/-amt) | inherit(amt) | goto(dest) | advance_go(collect $200)
#   next_rail | repair_houses(per_house,per_hotel) | get_out | pay_each(amt)
#   goto_jail
# The canonical deck preserves the classic card mix; scenario filtering of
# money-granting cards happens at draw time via CARD_GRANTS_MONEY().
# ---------------------------------------------------------------------------
CHANCE_DECK <- list(
  list(effect="money", amt=-50, label="Pay hospital fees $50"),
  list(effect="money", amt=20,  label="Get building loan $20"),
  list(effect="advance_go", label="Advance to Go (collect $200)"),
  list(effect="get_out", label="Get Out of Jail Free"),
  list(effect="goto", dest=12, label="Go to St. Charles Place"),
  list(effect="next_rail", label="Go forward to nearest Railroad"),
  list(effect="repair_houses", per_house=25, per_hotel=100, label="Make general repairs"),
  list(effect="goto", dest=25, label="Go to Illinois Avenue"),
  list(effect="goto_jail", label="Go to Jail"),
  list(effect="pay_each", amt=50, label="Speeding fine $50"),
  list(effect="goto", dest=32, label="Go to Pacific Avenue"),
  list(effect="goto", dest=38, label="Go to Park Place"),
  list(effect="goto", dest=36, label="Go to Short Line"),
  list(effect="goto", dest=3,  label="Take a ride to Mediterranean Ave"),
  list(effect="goto", dest=35, label="Go to Pennsylvania Avenue"),
  list(effect="goto", dest=11, label="You have been elected chairman")
)

CHEST_DECK <- list(
  list(effect="money", amt=50,  label="From sale of stock you get $50"),
  list(effect="money", amt=-15, label="Doctor's fee $15"),
  list(effect="money", amt=100, label="Life insurance matures $100"),
  list(effect="get_out", label="Get Out of Jail Free"),
  list(effect="money", amt=-50, label="Hospital fees $50"),
  list(effect="money", amt=20,  label="Income tax refund $20"),
  list(effect="inherit", amt=100, label="Inherit $100 from a distant relative"),
  list(effect="pay_each", amt=100, label="It is your birthday $100 to each"),
  list(effect="advance_go", label="Go back to Go (collect $200)"),
  list(effect="money", amt=-25, label="Street repairs $25 per house"),
  list(effect="money", amt=-10, label="Beauty contest second prize $10"),
  list(effect="money", amt=-150,label="You are assessed for school $150"),
  list(effect="money", amt=100, label="Sale of stock you get $100"),
  list(effect="get_out", label="Get Out of Jail Free"),
  list(effect="money", amt=-10, label="You pay poor tax $10"),
  list(effect="money", amt=100, label="Receive xmas dividends $100")
)

# A card grants money iff it puts cash into the player's pocket.
CARD_GRANTS_MONEY <- function(card) {
  e <- card$effect
  if (e %in% c("money","inherit")) return(!is.null(card$amt) && card$amt > 0)
  if (e == "get_out") return(TRUE)
  FALSE
}
