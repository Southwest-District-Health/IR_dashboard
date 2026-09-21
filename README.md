# Yearly Incidence Rates by County

Incidence rates per 100,000 people for reportable conditions in the six
counties of Health District 3: Adams, Canyon, Gem, Owyhee, Payette, and
Washington, from 2018 through the most recent complete year.

**Live page:** https://southwest-district-health.github.io/incidence-rates/

---

## What the page shows

Pick a condition and a county, and the chart shows how many new cases were
reported for every 100,000 residents in each year. A rate makes counties of
very different sizes comparable: ten cases means something quite different in
Canyon County than in Adams County.

Hover over or tap a bar to see the exact rate.

## Protecting privacy

- Years with fewer than 5 reported cases show an amber marker labeled "<5"
  instead of a bar, and no rate. Years with no cases show a grey marker.
- Conditions with fewer than 5 cases in every county and every year are not
  shown at all. District-wide counts for them are on the
  [case counts page](https://southwest-district-health.github.io/reportable-disease-counts/).
- Case counts and case-level records never leave the district. This repo
  holds only the finished page and the code that builds it.

## Where the numbers come from

- **Cases:** reportable disease records for Health District 3.
- **Population:** U.S. Census Bureau county population estimates, read
  directly from census.gov. Vintage 2019 is used for 2018 and 2019, and the
  latest vintage for 2020 onward.

## What's in this repo

| File | What it is |
|---|---|
| `index.html` | The published page. |
| `build_rates.R` | Pulls population, calculates rates, applies suppression, writes the page. |
| `rates_template.html` | Page layout and styling. |
| `REFRESH.md` | How to update the page. |

## Contact

Maintained by Lekshmi Rita-Venugopal, MD, MPH, Epidemiologist Program Manager,
Southwest District Health.
