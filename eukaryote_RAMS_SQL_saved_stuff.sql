####
#this file contains the SQL code I used to create tables in DuckDB from the text files downloaded from WoRMS/DarwinCore, and to run queries to filter for marine species with GenBank IDs, and to export the results to CSV files for further analysis in Python. The code includes comments explaining each step of the process.
## set the file search path to the directory where the text files downloaded from WoRMS are saved. This allows us to easily reference the files when creating tables and importing data.
SET file_search_path = 'C:/Users/davisee/OneDrive - University of Tasmania/Documents/chapter2/raw data/RAMS_alleukaryote_taxlist_20260224/WoRMS_RAMS_2026-02-01';

## creating tables and importing data from the text files downloaded from WoRMS, which I have saved in the above directory. I have used the read_csv function to read in the data and create tables in DuckDB. The delim parameter specifies that the data is tab-delimited, header=true indicates that the first row contains column names, and quote='' specifies that there are no quoted fields in the data.
CREATE TABLE taxon AS SELECT * FROM read_csv('taxon.txt', delim='\t', header=true, quote='');
CREATE TABLE distribution AS SELECT * FROM read_csv('distribution.txt', delim='\t', header=true, quote='');
CREATE TABLE speciesprofile AS SELECT * FROM read_csv('speciesprofile.txt', delim='\t', header=true, quote='');
CREATE TABLE vernacularname AS SELECT * FROM read_csv('vernacularname.txt', delim='\t', header=true, quote='');
CREATE TABLE identifier AS SELECT * FROM read_csv('identifier.txt', delim='\t', header=true, quote='');
CREATE TABLE reference AS SELECT * FROM read_csv('reference.txt', delim='\t', header=true, quote='');

### some example initial queries to check the data and join tables together to get the desired output. The first query selects the scientific name, taxon rank, locality, and GenBank ID for species that are marine, not terrestrial, not freshwater, and have a present occurrence status. The second query does the same but also includes subspecies and uses a left join to include all localities and occurrence statuses, even if they are null.
SELECT COUNT(*) FROM taxon;
SELECT COUNT(*) FROM distribution;
SELECT DISTINCT taxonRank FROM taxon;


## get a view of the data to check the joins and filters are working as expected, and to see what the output looks like before exporting to CSV. This query selects the scientific name, taxon rank, locality, and GenBank ID for species that are marine, not terrestrial, not freshwater, and have a present occurrence status.
SELECT
             t.scientificName,
             t.taxonRank,
             d.locality,
             i.identifier AS genbank_id
         FROM taxon t
         JOIN speciesprofile s ON t.taxonID = s.taxonID
         JOIN identifier i ON t.taxonID = i.taxonID
         JOIN distribution d ON t.taxonID = d.taxonID
         WHERE t.taxonRank = 'Species'
           AND i.datasetID = 'ncbi'
           AND s.isMarine = 1 
           AND s.isTerrestrial = 0
           AND s.isFreshwater = 0
           AND d.occurrenceStatus = 'present';



COPY (
SELECT
    t.scientificName,
    t.taxonRank,
    d.locality,
    regexp_replace(MIN(i.identifier), 'NCBI:txid', '')  AS genbank_id
FROM taxon t
JOIN speciesprofile s ON t.taxonID = s.taxonID
JOIN identifier i ON t.taxonID = i.taxonID
JOIN distribution d ON t.taxonID = d.taxonID
WHERE i.datasetID = 'ncbi'
  AND s.isMarine = 1
  AND s.isTerrestrial = 0
  AND s.isFreshwater = 0
  AND d.occurrenceStatus = 'present'
GROUP BY t.scientificName, t.taxonRank, d.locality
) TO 'C:/Users/davisee/OneDrive - University of Tasmania/Documents/chapter2/raw data/RAMS_alleukaryote_taxlist_20260224/WoRMS_RAMS_2026-02-01/marineNterrestrial_all_export.csv' (HEADER, DELIMITER ',');


##### what I am using going forward to export the species and subspecies with the left join to locality and occurrence status, 
#####so I can then filter for match to taxonomy + cross-reference with other databases in Python scripts.
COPY (
         SELECT
             t.scientificName,
             t.taxonRank,
             d.locality,
             d.occurrenceStatus,
             regexp_replace(MIN(i.identifier), 'NCBI:txid', '') AS genbank_id
         FROM taxon t
         JOIN speciesprofile s ON t.taxonID = s.taxonID
         JOIN identifier i ON t.taxonID = i.taxonID
         LEFT JOIN distribution d ON t.taxonID = d.taxonID
         WHERE i.datasetID = 'ncbi'
           AND t.taxonRank IN ('Species', 'Subspecies')
         GROUP BY t.scientificName, t.taxonRank, d.locality, d.occurrenceStatus
         ) TO 'C:/Users/davisee/OneDrive - University of Tasmania/Documents/chapter2/raw data/RAMS_alleukaryote_taxlist_20260224/WoRMS_RAMS_2026-02-01/RAMSncbi_speciesNsub_leftjoinLocalityexport.csv' (HEADER, DELIMITER ','); 


#reviewing algal representation in the dataset, to see if there are any major groups that are underrepresented in the GenBank data. This query counts the number of records for each phylum in the taxon table, filtering for specific algal groups that are relevant to my research.
COPY (
          SELECT phylum, COUNT(*)
         FROM taxon
         WHERE phylum IN (
           'Chlorophyta','Rhodophyta','Phaeophyta','Bacillariophyta',
           'Xanthophyta','Ochrophyta','Heterokontophyta',
           'Dinophyta','Dinomastigota','Cryptophyta','Haptophyta','Haptomonada'
         )
         GROUP BY phylum
         ) TO 'C:/Users/davisee/OneDrive - University of Tasmania/Documents/chapter2/raw data/RAMS_alleukaryote_taxlist_20260224/WoRMS_RAMS_2026-02-01/Algal_Phyla_Count.csv' (HEADER, DELIMITER ',');



#reviewing difference between total records per phylum vs species count for that phylum, to see if there are any major groups that are underrepresented in the GenBank data. This query counts the total number of records for each phylum in the taxon table, and also counts the number of unique species for each phylum, filtering for specific algal groups that are relevant to my research.
COPY (
SELECT phylum,
                SUM(CASE WHEN taxonRank IN ('Species', 'Subspecies') THEN 1 ELSE 0 END) AS species_count,
                SUM(CASE WHEN taxonRank = 'Genus' THEN 1 ELSE 0 END) AS genus_count,
                SUM(CASE WHEN taxonRank = 'Family' THEN 1 ELSE 0 END) AS family_count,
                SUM(CASE WHEN taxonRank = 'Order' THEN 1 ELSE 0 END) AS order_count,
                SUM(CASE WHEN taxonRank = 'Class' THEN 1 ELSE 0 END) AS class_count
         FROM taxon
         GROUP BY phylum ORDER BY species_count DESC
         ) TO 'C:/Users/davisee/OneDrive - University of Tasmania/Documents/chapter2/raw data/RAMS_alleukaryote_taxlist_20260224/WoRMS_RAMS_2026-02-01/Algal_Phyla_SpeciesVsTotalCount.csv' (HEADER, DELIMITER ',');