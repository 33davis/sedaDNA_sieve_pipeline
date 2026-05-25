library(tidyverse)
library(readxl)
library(taxize)

#read in RAMS taxa list
rams <- read_xlsx("raw data/RAMS_taxlist_20251129/RAMS_taxlist_20251129.xlsx")

#create unique family based on class
ram_fam_unique <- rams %>%
  distinct(Family, Class)

#use taxize to get ncbi_taxa_id 
ram_fam_ncbi <- ram_fam_unique %>%
  mutate(ncbi_TaxaID = get_uid(Family))

need_taxid <- ram_fam_ncbi %>%
  filter(is.na(ncbi_TaxaID))

cross_ref_for_taxaid <- need_taxid %>%
  left_join(rams, by = c("Family", "Class"))
  


#try to find the taxa ids at species level for the "NA" family species

cross_for_species_taxaid <- cross_ref_for_taxaid %>%
  select(Family, Class, ScientificName_accepted, ScientificName) %>%
  mutate(accpeted_name_TaxaID = get_uid(ScientificName_accepted), 
         other_name_TaxaId = get_uid(ScientificName))
  #they match, so there are some families that might now currently have NCBI genetic data.
#try to get family TaxaID based on species queries that did work
# Sys.getenv()
Sys.getenv("ENTREZ_KEY")
use_entrez() ######## running into an issue here

# Starting from your existing cross_for_species_taxaid with species_taxid
# 1) Pull lineage per species TaxID

library(tidyverse)
library(taxize)

# Starting from your existing cross_for_species_taxaid with species_taxid
# 1) Pull lineage per species TaxID

if (!"species_taxid" %in% names(cross_for_species_taxaid)) {
  if (all(c("accpeted_name_TaxaID", "other_name_TaxaId") %in% names(cross_for_species_taxaid))) {
    cross_for_species_taxaid <- cross_for_species_taxaid %>%
      mutate(species_taxid = dplyr::coalesce(accpeted_name_TaxaID, other_name_TaxaId))
  } else {
    warning("species_taxid column not found and source columns accpeted_name_TaxaID/other_name_TaxaId are missing.")
    # Create a placeholder species_taxid to avoid downstream errors
    cross_for_species_taxaid <- cross_for_species_taxaid %>%
      mutate(species_taxid = NA_character_)
  }
}



