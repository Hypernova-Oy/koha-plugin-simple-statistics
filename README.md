# koha-plugin-simple-statistics

A Koha plugin that deploys and manages a curated set of SQL reports.

## What it does

* On install/upgrade, installs the bundled SQL reports (defined in
  `Koha/Plugin/Fi/Hypernova/SimpleStatistics/sql-reports.yaml`) into Koha's
  `saved_sql` table.
* Public reports are never auto-deployed.
* The configuration view lists every report and lets you re-deploy one with a
  single click. Rows are highlighted red when a report is missing from Koha.

## Adding a report

Edit `Koha/Plugin/Fi/Hypernova/SimpleStatistics/sql-reports.yaml` and add an
entry:

```yaml
    - code: my-report
      name: "My report"
      description: "What it shows"
      group: ""          # optional
      subgroup: ""       # optional
      public: false      # public reports are never auto-deployed
      sql: |
        SELECT ...
        FROM ...
```

Then rebuild the plugin (`./build.sh`) and install/upgrade it. Reports you
already have will not be overwritten; new ones are deployed on upgrade.

## Building

```bash
./build.sh
```

This produces `koha-plugin-simple-statistics-<version>.kpz`, ready to upload
via Koha's plugin management page.
