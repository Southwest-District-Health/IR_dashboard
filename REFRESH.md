# Updating the incidence rate chart

This page shows completed years only, so the main update happens once a year.
It uses the same case export as the case counts page, so you can also rebuild
it whenever you refresh that page to pick up any corrections to past years.

Project folder: `Documents\R\Incidence_Map` (in R, `~/R/Incidence_Map`).

---

## Any time: rebuild with the latest case data

1. Make sure the newest `Case_data.csv` is in `~/R/Cases_Dashboard`.
   This script reads it from there, so there's only one copy to keep current.
2. Run:
   ```r
   source("build_rates.R", echo = TRUE)
   ```
3. Open `index.html` and check a few condition and county combinations.
4. Upload the new `index.html` to this repo.
   Commit message: `Rebuild with case data through MM/DD/YYYY`.

## Once a year: add the year that just ended

Do this early in the year, once the previous year's case data is complete
(for example, add 2026 in early 2027).

1. In `build_rates.R`, extend `YEARS`, e.g. `2018:2026`.
2. Check population coverage. The Census Bureau releases each year's county
   estimates the following March. Until then, the script will stop and say
   that year has no population estimate.
3. When the new vintage is out, update the second entry in `POP_SOURCES`:
   change the label, the years, and the URL. For Vintage 2026 that would be:
   ```r
   list(
     label = "Vintage 2026",
     years = 2020:2026,
     url   = "https://www2.census.gov/programs-surveys/popest/datasets/2020-2026/counties/totals/co-est2026-alldata.csv"
   )
   ```
   Confirm the exact address on census.gov before running; the pattern has
   been stable but it's worth a look.
4. Delete `population_cache.csv` so the script pulls the new estimates.
5. Run the script, check the population table it prints, and publish as above.

A new vintage revises every year back to 2020, so rates for 2020 onward may
shift slightly after this update. That's expected.

## Good to know

**Population.** The script reads county estimates directly from census.gov
the first time and saves them to `population_cache.csv`, so later runs don't
need the internet and the numbers don't change underneath you. No API key is
needed.

**Suppression.** Years with 1 to 4 cases show an amber "<5" marker with no
rate, the same rule as the case counts page. Conditions that never reach 5
cases in any county and year are left off entirely, because their chart would
only show which county had a handful of cases in which year. `published_rates.csv` is an exact copy of what the page
shows.

**Never commit** `Case_data.csv` or any other case-level file. The
`.gitignore` blocks CSVs.
