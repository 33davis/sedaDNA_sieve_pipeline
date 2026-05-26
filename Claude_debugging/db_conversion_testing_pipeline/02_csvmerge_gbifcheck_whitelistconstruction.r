# =============================================================================
# RAMS Southern Ocean Whitelist Construction
# =============================================================================
# INPUTS:
#   RAMSncbi_speciesNsub_leftjoinLocalityexport.csv
#   RAMS_to_NCBI_taxa_with_lineage_ids.txt
#
# OUTPUT:
#   RAMS_SO_whitelist_final.tsv        — clean whitelist for Rmd input
#   RAMS_SO_whitelist_flagged.tsv      — uncertain taxa for manual review
#
# REQUIRES:
#   install.packages(c("tidyverse", "rgbif"))
# =============================================================================

library(tidyverse)
library(rgbif)

# -----------------------------------------------------------------------------
# STEP 1: Join CSV and lineage file
# -----------------------------------------------------------------------------

rams_csv <- read_csv("RAMSncbi_speciesNsub_leftjoinLocalityexport.csv") %>%
  mutate(genbank_id = as.character(genbank_id))

lineage <- read_delim("RAMS_to_NCBI_taxa_with_lineage_ids.txt", delim = "\t") %>%
  mutate(tax_id = as.character(tax_id))

rams_joined <- rams_csv %>%
  left_join(lineage, by = c("genbank_id" = "tax_id"))

cat("Joined table dimensions:", nrow(rams_joined), "rows,", ncol(rams_joined), "cols\n")

# -----------------------------------------------------------------------------
# STEP 2: Locality keyword flag
# -----------------------------------------------------------------------------

SO_keywords <- paste0(
  "antarct|southern ocean|ross sea|weddell|amundsen|bellingshausen|",
  "scotia|south georgia|south sandwich|south orkney|south shetland|",
  "bouvet|heard|macquarie|kerguelen|crozet|prince edward|marion|",
  "subantarct|sub-antarct|circumpolar|polar front"
)

rams_joined <- rams_joined %>%
  mutate(
    locality_SO_match = case_when(
      str_detect(str_to_lower(locality), SO_keywords) ~ TRUE,
      is.na(locality)                                  ~ NA,
      TRUE                                             ~ FALSE
    )
  )

cat("Locality SO match breakdown:\n")
print(table(rams_joined$locality_SO_match, useNA = "always"))

# -----------------------------------------------------------------------------
# STEP 3: occurrenceStatus flag
# -----------------------------------------------------------------------------

rams_joined <- rams_joined %>%
  mutate(
    status_flag = case_when(
      str_to_lower(occurrenceStatus) == "present" ~ "confirmed",
      is.na(occurrenceStatus)                     ~ "uncertain_NA",
      TRUE                                        ~ "other"
    )
  )

cat("occurrenceStatus flag breakdown:\n")
print(table(rams_joined$status_flag, useNA = "always"))

# -----------------------------------------------------------------------------
# STEP 4: GBIF cross-reference via occ_count()
# Southern Ocean bounding box: lat -90 to -40, lon -180 to 180
# -----------------------------------------------------------------------------

# Southern Ocean / Subantarctic bounding box
# latitude:  -90 to -40 (covers Antarctica + all Subantarctic islands)
# longitude: -180 to 180 (full circumpolar)
SO_bbox <- "POLYGON((-180 -90, 180 -90, 180 -40, -180 -40, -180 -90))"

# get unique taxon IDs to avoid redundant queries
unique_taxa <- rams_joined %>%
  distinct(genbank_id, ncbi_scientific_name) %>%
  filter(!is.na(genbank_id))

cat("\nQuerying GBIF for", nrow(unique_taxa), "unique taxa...\n")
cat("This may take several minutes.\n")

# query GBIF with a small pause to respect rate limits
gbif_results <- unique_taxa %>%
  mutate(
    gbif_SO_count = map_int(genbank_id, function(tid) {
      tryCatch({
        Sys.sleep(0.2)   # 200ms pause between queries
        n <- occ_count(
          taxonKey  = as.integer(tid),
          geometry  = SO_bbox
        )
        as.integer(n)
      }, error = function(e) {
        NA_integer_
      })
    }),
    gbif_SO_confirmed = case_when(
      gbif_SO_count > 0  ~ TRUE,
      gbif_SO_count == 0 ~ FALSE,
      is.na(gbif_SO_count) ~ NA
    )
  )

cat("GBIF SO confirmed breakdown:\n")
print(table(gbif_results$gbif_SO_confirmed, useNA = "always"))

# join GBIF results back onto main table
rams_final <- rams_joined %>%
  left_join(
    gbif_results %>% select(genbank_id, gbif_SO_count, gbif_SO_confirmed),
    by = "genbank_id"
  )

# -----------------------------------------------------------------------------
# STEP 5: Classify and split into whitelist vs flagged
# -----------------------------------------------------------------------------

rams_final <- rams_final %>%
  mutate(
    whitelist_decision = case_when(
      # confirmed present + locality match → keep
      status_flag == "confirmed" & locality_SO_match == TRUE  ~ "whitelist",
      # confirmed present + GBIF confirmed → keep
      status_flag == "confirmed" & gbif_SO_confirmed == TRUE  ~ "whitelist",
      # GBIF confirmed even if occurrenceStatus NA → keep
      gbif_SO_confirmed == TRUE                               ~ "whitelist",
      # uncertain: NA status, no locality match, no GBIF hit → flag
      status_flag == "uncertain_NA" & 
        (is.na(locality_SO_match) | locality_SO_match == FALSE) &
        (is.na(gbif_SO_confirmed) | gbif_SO_confirmed == FALSE) ~ "flag_for_review",
      # everything else → flag
      TRUE                                                    ~ "flag_for_review"
    )
  )

cat("\nWhitelist decision breakdown:\n")
print(table(rams_final$whitelist_decision, useNA = "always"))

# -----------------------------------------------------------------------------
# STEP 6: Save outputs
# -----------------------------------------------------------------------------

# clean whitelist — unique tax_ids, ready for Rmd
whitelist <- rams_final %>%
  filter(whitelist_decision == "whitelist") %>%
  distinct(genbank_id, .keep_all = TRUE) %>%
  select(
    rams_scientificName, tax_id = genbank_id, ncbi_scientific_name,
    taxon_rank_ncbi, rams_taxonRank, lineage,
    kingdom, phylum, class, order, family, genus, species,
    locality_SO_match, status_flag, gbif_SO_count, gbif_SO_confirmed,
    whitelist_decision
  )

# flagged taxa for manual review
flagged <- rams_final %>%
  filter(whitelist_decision == "flag_for_review") %>%
  distinct(genbank_id, .keep_all = TRUE) %>%
  select(
    rams_scientificName, tax_id = genbank_id, ncbi_scientific_name,
    taxon_rank_ncbi, rams_taxonRank,
    locality, locality_SO_match, status_flag,
    gbif_SO_count, gbif_SO_confirmed,
    whitelist_decision
  )

write_tsv(whitelist, "RAMS_SO_whitelist_final.tsv")
write_tsv(flagged,   "RAMS_SO_whitelist_flagged.tsv")

cat("\n=== Summary ===\n")
cat("Whitelist taxa:       ", nrow(whitelist), "\n")
cat("Flagged for review:   ", nrow(flagged),   "\n")
cat("\nOutputs saved:\n")
cat("  RAMS_SO_whitelist_final.tsv\n")
cat("  RAMS_SO_whitelist_flagged.tsv\n")