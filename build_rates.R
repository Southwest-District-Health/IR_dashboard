# build_rates.R -------------------------------------------------------------
# Yearly incidence rate per 100,000 by county and condition, 2018-2025.
# Reads the case export, pulls county population straight from the Census
# Bureau's published estimates, suppresses small counts, and writes
# index.html: a standalone bar chart page with no Shiny server behind it.
#
# Author: Lekshmi Rita-Venugopal, Southwest District Health
#
# Run:  source("build_rates.R", echo = TRUE)
#
# Needs in the project folder:
#   rates_template.html
# ---------------------------------------------------------------------------

PROJECT_DIR <- "~/R/IR_Dashboard"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(jsonlite)
})

# --- Settings --------------------------------------------------------------
# Same case export the case counts page uses, so both pages always agree.
IN_CSV <- "~/R/Cases_Dashboard/Case_data.csv"

TEMPLATE  <- "rates_template.html"
OUT_HTML  <- "index.html"
OUT_AUDIT <- "published_rates.csv"      # exact copy of what goes public
POP_CACHE <- "population_cache.csv"     # delete to re-pull from Census

YEARS     <- 2018:2025
THRESHOLD <- 5                          # counts below this are suppressed

DEFAULT_CONDITION <- "Campylobacteriosis"
DEFAULT_COUNTY    <- "Canyon"

# Conditions that never reach THRESHOLD cases in any county-year are listed
# under "Rarely reported" and shown for the whole district, not by county,
# the same rule as the case counts page.
DISTRICT_LABEL <- "Health District 3"

STATE_FIPS <- "16"
COUNTIES   <- c("Adams", "Canyon", "Gem", "Owyhee", "Payette", "Washington")

# Census Bureau county population estimates, read directly from census.gov.
# Each new vintage revises every year back to the last census, so use the
# newest vintage that covers a year.
POP_SOURCES <- list(
  list(
    label = "Vintage 2019",
    years = 2018:2019,
    url   = "https://www2.census.gov/programs-surveys/popest/datasets/2010-2019/counties/totals/co-est2019-alldata.csv"
  ),
  list(
    label = "Vintage 2025",
    years = 2020:2025,
    url   = "https://www2.census.gov/programs-surveys/popest/datasets/2020-2025/counties/totals/co-est2025-alldata.csv"
  )
)

DROP_CONDITIONS <- c(
  "2019-nCoV", "Amebiasis, NOS", "Congenital hypothyroidism",
  "Encephalitis, viral or aseptic", "Foodborne Illness, NOS",
  "Influenza Outbreak", "Streptococcal toxic-shock syndrome",
  "Waterborne Illness", "Aseptic meningitis",
  "Extraordinary occurrence of illness",
  "Hemolytic uremic synd,postdiarrheal", "Influenza",
  "Multisystem Inflammatory Syndrome in Children"
)

for (f in c(IN_CSV, TEMPLATE)) {
  if (!file.exists(f)) stop(f, " not found.", call. = FALSE)
}

# --- 1. County population from the Census Bureau ---------------------------
fetch_population <- function(src) {
  message("Reading ", src$label, " county estimates from census.gov...")
  raw <- read_csv(src$url, col_types = cols(.default = "c"),
                  locale = locale(encoding = "latin1"), progress = FALSE)

  cols <- paste0("POPESTIMATE", src$years)
  missing <- setdiff(cols, names(raw))
  if (length(missing)) {
    stop(src$label, " file is missing: ", paste(missing, collapse = ", "),
         call. = FALSE)
  }

  raw %>%
    filter(SUMLEV == "050", STATE == STATE_FIPS) %>%
    transmute(GEOID  = paste0(STATE, COUNTY),
              County = str_remove(CTYNAME, " County$"),
              across(all_of(cols))) %>%
    pivot_longer(all_of(cols), names_to = "Year",
                 names_prefix = "POPESTIMATE", values_to = "Population") %>%
    mutate(Year = as.integer(Year),
           Population = as.numeric(Population),
           Source = src$label)
}

if (file.exists(POP_CACHE)) {
  population <- read_csv(POP_CACHE, col_types = cols(
    GEOID = "c", County = "c", Year = "i", Population = "d", Source = "c"))
} else {
  population <- map_dfr(POP_SOURCES, fetch_population)
  write_csv(population, POP_CACHE)
  message("Saved ", POP_CACHE, ". Delete it to pull fresh estimates.")
}

population <- population %>% filter(County %in% COUNTIES, Year %in% YEARS)

gaps <- expand_grid(County = COUNTIES, Year = YEARS) %>%
  anti_join(population, by = c("County", "Year"))
if (nrow(gaps)) {
  stop("No population estimate for: ",
       paste(gaps$County, gaps$Year, collapse = ", "),
       ". If YEARS was extended, add the new vintage to POP_SOURCES and ",
       "delete ", POP_CACHE, ".", call. = FALSE)
}

hd3 <- distinct(population, GEOID, County)

# --- 2. Read and clean the case data (same rules as the original app) ------
raw <- read_csv(IN_CSV, show_col_types = FALSE)

needed <- c("Condition", "Date", "County_Code")
if (length(setdiff(needed, names(raw)))) {
  stop(IN_CSV, " is missing: ", paste(setdiff(needed, names(raw)), collapse = ", "),
       call. = FALSE)
}

cases <- raw %>%
  mutate(Condition = case_when(
    Condition == "Tuberculosis (2020 RVCT)" ~ "Tuberculosis",
    Condition %in% c("Salmonellosis (excl S. Typhi and S. Paratyphi)",
                     "Salmonellosis 2018 (excl paratyphoid and typhoid)",
                     "Salmonellosis - prior to 2018") ~ "Salmonellosis",
    TRUE ~ Condition
  )) %>%
  filter(!Condition %in% DROP_CONDITIONS) %>%
  mutate(Date = mdy_hm(Date), Year = year(Date),
         GEOID = as.character(County_Code)) %>%
  filter(!is.na(Year), Year %in% YEARS)

unmatched <- setdiff(unique(cases$GEOID), hd3$GEOID)
if (length(unmatched)) {
  stop("County_Code values not matching an HD3 county: ",
       paste(unmatched, collapse = ", "),
       ". Expected 5-digit FIPS codes like 16027.", call. = FALSE)
}

counts <- cases %>% count(Condition, Year, GEOID, name = "Incidence")

complete <- expand_grid(Condition = sort(unique(counts$Condition)),
                        Year = YEARS, hd3) %>%
  left_join(counts, by = c("Condition", "Year", "GEOID")) %>%
  mutate(Incidence = replace_na(Incidence, 0L)) %>%
  left_join(population, by = c("GEOID", "County", "Year"))

# --- 3. Rarely reported conditions: district-wide only ---------------------
# If a condition never reaches THRESHOLD in any county-year, a county chart
# would only show which county had 1-4 cases in which year. For those, the
# county detail is dropped here and only the district total is published.
rare_conditions <- complete %>%
  group_by(Condition) %>%
  summarise(ever = any(Incidence >= THRESHOLD), .groups = "drop") %>%
  filter(!ever) %>%
  pull(Condition)

by_geography <- bind_rows(
  complete %>%
    filter(!Condition %in% rare_conditions) %>%
    transmute(Condition, Year, Geography = County, GEOID,
              Incidence, Population, Source),
  complete %>%
    filter(Condition %in% rare_conditions) %>%
    group_by(Condition, Year) %>%
    summarise(Incidence  = sum(Incidence),
              Population = sum(Population),
              Source     = first(Source), .groups = "drop") %>%
    transmute(Condition, Year, Geography = DISTRICT_LABEL, GEOID = NA_character_,
              Incidence, Population, Source)
)

# --- 4. Rates, suppressed before anything leaves this script ---------------
published <- by_geography %>%
  mutate(
    Suppressed = Incidence > 0 & Incidence < THRESHOLD,
    Rate       = if_else(Suppressed, NA_real_,
                         round(Incidence / Population * 1e5, 2)),
    Status     = case_when(Incidence == 0 ~ "No cases reported",
                           Suppressed     ~ "Fewer than 5 cases (suppressed)",
                           TRUE           ~ "Reported")
  ) %>%
  select(Condition, Year, Geography, GEOID, Population, PopSource = Source,
         Rate, Status) %>%
  arrange(Condition, Geography, Year)

write_csv(published, OUT_AUDIT)

if (!DEFAULT_CONDITION %in% published$Condition) {
  warning("DEFAULT_CONDITION '", DEFAULT_CONDITION,
          "' is not on the page. It will open on the first condition.",
          call. = FALSE)
}
if (!DEFAULT_COUNTY %in% COUNTIES) {
  warning("DEFAULT_COUNTY '", DEFAULT_COUNTY,
          "' is not an HD3 county. The page will open on the first county.",
          call. = FALSE)
}

# --- 5. Assemble the payload ----------------------------------------------
# One series per condition and county (or district, for rarely reported
# conditions), in year order. Each value is the rate, "<5" when suppressed,
# or 0 when no cases were reported.
series <- published %>%
  arrange(Condition, Geography, Year) %>%
  mutate(key = paste(Condition, Geography, sep = "||"),
         val = map2(Rate, Status, function(r, s) {
           if (s == "Fewer than 5 cases (suppressed)") "<5"
           else if (s == "No cases reported") 0
           else r
         })) %>%
  group_by(key) %>%
  summarise(v = list(val), .groups = "drop") %>%
  deframe()

pop_note <- map_chr(POP_SOURCES, function(s) {
  yrs <- intersect(s$years, YEARS)
  paste0(s$label, " for ", min(yrs), if (length(yrs) > 1) paste0("\u2013", max(yrs)))
}) %>% paste(collapse = "; ")

payload <- list(
  title            = paste0("Yearly Incidence Rate per 100,000 population (",
                            min(YEARS), " - ", max(YEARS), ")"),
  conditions       = I(sort(unique(published$Condition))),
  rare             = I(sort(rare_conditions)),
  districtLabel    = DISTRICT_LABEL,
  rareNote         = paste0("This condition is rarely reported, so it is shown for ",
                            DISTRICT_LABEL, " as a whole. County-level rates are ",
                            "not published for conditions this uncommon."),
  counties         = I(COUNTIES),
  years            = I(as.character(YEARS)),
  defaultCondition = DEFAULT_CONDITION,
  defaultCounty    = DEFAULT_COUNTY,
  threshold        = THRESHOLD,
  popNote          = paste0("Population: U.S. Census Bureau county population ",
                            "estimates (", pop_note, ")."),
  series           = series
)

json <- toJSON(payload, auto_unbox = TRUE, na = "null", null = "null", digits = NA)

# --- 6. Inject into the template ------------------------------------------
tpl   <- paste(readLines(TEMPLATE, warn = FALSE), collapse = "\n")
parts <- strsplit(tpl, "/*__DATA__*/", fixed = TRUE)[[1]]
if (length(parts) != 2) {
  stop("Could not find the /*__DATA__*/ placeholder in ", TEMPLATE, call. = FALSE)
}
writeLines(paste0(parts[1], json, parts[2]), OUT_HTML, useBytes = TRUE)

# --- 7. Report -------------------------------------------------------------
message("\nWrote ", normalizePath(OUT_HTML), " (",
        round(file.size(OUT_HTML) / 1024), " KB)")
message("Conditions shown: ", length(unique(published$Condition)),
        " (", length(rare_conditions), " rarely reported, shown district-wide)")
message("Cells - reported: ", sum(published$Status == "Reported"),
        " | suppressed: ", sum(grepl("suppressed", published$Status)),
        " | no cases: ", sum(published$Status == "No cases reported"))

message("\nPopulation used:")
population %>%
  select(County, Year, Population) %>%
  pivot_wider(names_from = Year, values_from = Population) %>%
  print()
