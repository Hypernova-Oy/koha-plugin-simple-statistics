h1. Koha::Plugin::Fi::Hypernova::SimpleStatistics

A Koha plugin that deploys and manages a curated set of SQL reports.

h3. Koha's source code

Koha's source code is available at /usr/share/koha (lib at /usr/share/koha/lib).

h1. Purpose

We deploy a curated list of SQL reports that are useful for most libraries.
The list is maintained in a single, easy-to-edit YAML file bundled with the
plugin. When the plugin is installed (or upgraded), the full set of reports is
installed to Koha's saved_sql table. The plugin's configuration view shows the
full list and lets a librarian re-deploy individual reports.

h1. Functional requirements

* On install/upgrade, every non-public report that has not yet been deployed is
  installed to koha.saved_sql.
* Public reports are never auto-deployed (security decision).
* The configuration view shows all available reports (name, description, group,
  subgroup, public) with a Deploy button per row.
* A row has a reddish background when the report is not deployed (i.e. missing
  from koha.saved_sql - for example after a librarian deleted it).
* Deleting a report from Koha's SQL reports masks it: the plugin remembers the
  code -> saved_sql.id mapping, and a report whose saved_sql.id no longer
  exists is considered masked. Masked reports are skipped on future upgrades.
* Editing the YAML file on disk and reloading the configuration view refreshes
  the list of available reports. It does not auto-deploy them.

h1. Architecture

* Model/service - Store.pm: loads the bundled YAML, reads/writes the
  code -> saved_sql.id mapping table, deploys reports, seeds REPORT_GROUP /
  REPORT_SUBGROUP authorised values, and detects masked reports.
* Lifecycle - Install.pm: install / upgrade / uninstall.
* Transport - Controller.pm: the configure() view (GET table, POST deploy).

h1. Data

* One plugin table (koha_plugin_fi_hypernova_simplestatistics_*): the
  code -> saved_sql.id mapping.
* Report definitions: Koha/Plugin/Fi/Hypernova/SimpleStatistics/sql-reports.yaml

h1. Configuration

None - the report list is the YAML file, deployment state is the mapping table.

h1. Delivery plan

* Stage 1 - scaffold
* Stage 2 - YAML + Store (model/service)
* Stage 3 - Install (lifecycle)
* Stage 4 - Controller + configure.tt
* Stage 5 - tests, build, validation
