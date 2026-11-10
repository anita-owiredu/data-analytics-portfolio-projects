# Data Analytics Portfolio Projects

Three end-to-end analyses, each answering a business question with data: where patients wait longest, how an online retailer is performing, and how hospital clinics perform against their targets. Each project includes its data, SQL, a Tableau dashboard and a written report with recommendations, and two also include an Excel workbook.

## Projects

| Project | Business question | Tools |
|---|---|---|
| [**Healthcare Visits Analytics**](healthcare-visits-analytics/) | Where do patients wait longest, and what should the hospital do first? | Excel, PostgreSQL, Tableau |
| [**UK E-Commerce Analytics**](uk-ecommerce-analytics/) | How are sales, customers, marketing, returns and website conversion performing? | PostgreSQL, Tableau |
| [**Hospital Operations Analytics**](hospital-operations-project/) | How are the clinics performing against their targets, and where are visits being lost? | Excel, PostgreSQL, Tableau |

More projects will be added here as they are completed.

### Healthcare Visits Analytics at a glance
- Every one of 6 departments misses a 20-minute wait target; Emergency averages 55.4 minutes, twice Outpatients.
- Waits are persistent across 20 months while demand is stable (+2.2% over the last 6 months).
- Includes a formula-based Excel workbook, a Tableau dashboard with adjustable targets, statistic and comparison period, and a SQL query for every dashboard element.

### UK E-Commerce Analytics at a glance
- 15,000 orders from 5,000 customers brought in £1.46M, and revenue is flat (+1.1% in 2025), with Books the top category at 17.9% of sales.
- Customers are worth about the same from every acquisition channel (£283 to £309), reorder about 141 days apart, and 27% have not ordered for a year or more.
- 7.4% of website visits end in a purchase and 60.1% of shopping carts are abandoned; 7.9% of orders are returned, and about half of the reasons are the retailer's to fix.
- Includes eight business questions answered in SQL, with a query for every dashboard tile and chart, an entity relationship diagram and a four-page Tableau dashboard.

### Hospital Operations Analytics at a glance
- Across 10 clinics and 80,000 booked appointments in 2025, net revenue reached 88.9% of target (£9.87M against £11.10M), and no clinic met its revenue target in any month.
- 13.7% of bookings were lost to cancellations and no-shows, most often for online bookings and long waits, and clinicians' time was used at 56.6% against a target of about 82%.
- Includes a formula-based Excel workbook with a what-if estimate, PostgreSQL scripts for the data checks and nine business questions, and a three-page Tableau dashboard.

## Repository structure

```
data-analytics-portfolio-projects/
├── README.md                        # this page
├── healthcare-visits-analytics/
│   ├── README.md                    # findings report
│   └── data/   excel/   sql/   dashboard/   images/
├── uk-ecommerce-analytics/
│   ├── README.md
│   └── data/   sql/   dashboard/   images/
└── hospital-operations-project/
    ├── README.md
    └── data/   excel/   sql/   dashboard/   images/
```

## Skills

- **Excel:** Formulas, summary tables, conditional formatting, charts and data validation checks
- **PostgreSQL:** Joins, aggregation, CTEs, window functions, percentiles and data validation
- **Tableau:** Parameters, calculated fields and dashboards
- **Data Storytelling:** Translating results into business recommendations

## Adding a project
Create a folder named `<project-name>/` with its own `README.md`, `data/`, `sql/` and `dashboard/`, then add a row to the table above.

> Each project is a complete analysis, from raw data to recommendations; the data is synthetic, created for these projects, and describes no real patient, customer or organisation.

---

Author: Anita Owiredu · [LinkedIn](https://www.linkedin.com/in/anitaowiredu-data)
