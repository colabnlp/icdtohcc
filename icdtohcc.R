# ICD to HCC

### Generate Medicare Hierchical Condition Categories (HCC) based on ICD codes

### Introduction
# many to many relationship
# ICD9/10 are mapped to Condition Categories (CC), and a hierarchy based on disease severity is applied to the CCs to generate HCCs. 

### Data
# The ICD/HCC mappings were obtained from CMS (https://www.cms.gov/Medicare/Health-Plans/MedicareAdvtgSpecRateStats/Risk-Adjustors.html). CMS provides SAS macros for assigning HCCs and HCC scores based on ICDs, adjusted annually
#  Here we have implemented assigning HCCs (but not scores) in R. 
# The original data is available from CMS, or in the github repository at /crosswalks/originalCMS_xw

### Packages
library(stringr)
library(icd)
library(lintr)

#############################################
######### Import ICD9 - CC crosswalks
#############################################

# Import the ICD9 and ICD10 HCC crosswalks, one per year, into a list of dataframes
icd9cc <- apply(data.frame(paste("crosswalks/importable_xw/icd9/",list.files("crosswalks/importable_xw/icd9/"),sep = "")), 1, FUN = read.fwf, width = c(7, 4), header = F, stringsAsFactors = F)
icd10cc <- apply(data.frame(paste("crosswalks/importable_xw/icd10/",list.files("crosswalks/importable_xw/icd10/"),sep = "")), 1, FUN = read.fwf, width = c(7, 4), header = F, stringsAsFactors = F)

# Create a vector of year names based on the file names in the icd folders
years <- list()
years$icd9 <- as.numeric(substr(list.files("crosswalks/importable_xw/icd9/"), 0, 4))
years$icd10 <- as.numeric(substr(list.files("crosswalks/importable_xw/icd10/"), 0, 4))

# assign year to each dataframe within the list of dataframes
icd9cc <- mapply(cbind, icd9cc, "year" = years$icd9, SIMPLIFY = F)
icd10cc <- mapply(cbind, icd10cc, "year" = years$icd10, SIMPLIFY = F)

# Row bind icd9 and icd10 from different years into despective dataframes
icd9cc <- do.call(rbind, icd9cc)
icd10cc <- do.call(rbind, icd10cc)

# Assign ICD version (9 or 10) and combine into single dataframe
icd9cc$icdversion <- 9
icd10cc$icdversion <- 10
icdcc <- rbind(icd9cc, icd10cc)

rm(icd9cc, icd10cc, years)

# add variable names
colnames(icdcc) <- c("icd_code", "cc", "year", "icdversion")

# Remove whitespace from codes
icdcc$icd_code <- trimws(icdcc$icd_code)
icdcc$cc <- trimws(icdcc$cc)

#############################################
######### Edit ICD9/10s
#############################################

# Per CMS instructions, certain ICD9s have to be manually assigned additional CCs

# icd9 40403, 40413, and 40493 are assigned to CC 80 in 2007-2012
extracodes <- list()
extracodes$e1 <- c("40403", "40413", "40493")
extracodes$e1 <- expand.grid(extracodes$e1, "80", 2007:2012, 9, stringsAsFactors = F)

# icd9 40401, 40403, 40411, 40413, 40491, 40493 are assigned to CC85 in 2013
extracodes$e2 <- c("40401","40403","40411","40413","40491","40493")
extracodes$e2 <- expand.grid(extracodes$e2, "85", 2013, 9, stringsAsFactors = F)

# icd9 40403, 40413, 40493 are assigned to CC85 in 2014-2015
extracodes$e3 <- c("40403","40413","40493")
extracodes$e3 <- expand.grid(extracodes$e3, "85", 2014:2015, 9, stringsAsFactors = F)

# icd9 3572 and 36202 are assigned to CC18 in 2013
extracodes$e4 <- c("3572", "36202")
extracodes$e4 <- expand.grid(extracodes$e4, "18", 2013, 9, stringsAsFactors = F)

# icd9 36202 is assigned to CC18 in 2014-2015
extracodes$e5 <- "36202"
extracodes$e5 <- expand.grid(extracodes$e5, "18", 2014:2015, 9, stringsAsFactors = F)

# combine into one DF
extracodes <- do.call(rbind, extracodes)

# add variable names
colnames(extracodes) <- c("icd_code", "cc", "year", "icdversion")

# combine with full icdcc listing
icdcc <- rbind(icdcc, extracodes)
rm(extracodes)

#############################################
######### Import Labels
#############################################
# Import HCC labels from all years
labels <- apply(data.frame(paste("crosswalks/importable_xw/labels/",list.files("crosswalks/importable_xw/labels/"),sep = "")), 1, FUN = readLines)

# Convert a single dataframe
labels <- lapply(labels, as.data.frame, stringsAsFactors = F)
labels <- do.call(rbind, labels)

# Extract HCC numbers
hccnum <- str_match(labels[,1], "HCC([:digit:]*)")[,2]

# Extract HCC names
hccname <- substr(labels[,1], regexpr("=", labels[,1])+2, nchar(labels[,1])-1)

# Combine numbers and names into dataframe of labels
labels <- data.frame(hccnum, hccname, stringsAsFactors = F, row.names = NULL)
rm(hccnum, hccname)

# Drop lines with NA/out of range HCC numbers
labels$hccnum <- as.numeric(labels$hccnum)
labels <- labels[!is.na(labels$hccnum),]

# Drop duplicated HCC numbers
labels <- labels[!duplicated(labels$hccnum),]

# Remove whitespace from hccnames
labels$hccname <- trimws(labels$hccname)

# Order in ascending order of HCC number
labels <- labels[order(labels$hccnum),]

#############################################
######### Define Hierarchy
#############################################

# import raw hierarchy files from CMS
hierarchy <- apply(data.frame(paste("crosswalks/importable_xw/hierarchy/",list.files("crosswalks/importable_xw/hierarchy/"),sep = "")), 1, FUN = readLines)

# Create a vector of year names based on the file names in the icd folders
years <- substr(list.files("crosswalks/importable_xw/hierarchy/"), 0,4)

# Add year variable to each dataframe
hierarchy <- mapply(cbind, hierarchy, "year" = years, SIMPLIFY = F)
rm(years)

# convert each item in the list of hierarchy objects into a data.frame and combine into a single DF
hierarchy <- lapply(hierarchy, as.data.frame, stringsAsFactors = F)
hierarchy <- do.call(rbind, hierarchy)

# convert years to numeric
hierarchy$year <- as.numeric(hierarchy$year)

# only keep the lines that are logical hierarchy statements (removes comments, empty lines, additional code) and rename variable
hierarchy <- hierarchy[grepl("if hcc|%SET0", hierarchy$V1),]
colnames(hierarchy)[1] <- "condition"

# Extract the HCC that is used in the if condition statement
hierarchy$ifcc <- as.numeric(str_extract(hierarchy$condition, "(?<=hcc)([0-9]*)|(?<=CC\\=)([0-9]*)"))

# Extract the HCCs that should be set to zero if the above condition is met
todrop <- str_extract(hierarchy$condition, 
                      "(?<=i\\=)([:print:]*)(?=;hcc)|(?<=STR\\()([:print:]*)(?= \\)\\);)")

# convert it to a dataframe and bind it with the original hierarchy data
todrop <- as.data.frame(str_split_fixed(todrop, ",", n = 10), stringsAsFactors = F)
# convert to numeric
todrop <- as.data.frame(lapply(todrop, as.numeric))

# combine CC requirements with CCs to zero
hierarchy <- cbind(hierarchy[,c("year", "ifcc")], todrop)
rm(todrop)

# remove columns that are completely NA
# intially, set up hiearchy to allow for up to 10 possible conditions, now will remove extra columns
# In current data, maximum is 6 conditions to zero, however leaving room in case these are expanded in the future
hierarchy <- hierarchy[, colSums(is.na(hierarchy)) < nrow(hierarchy)]

#############################################
######### save data files
#############################################
save(labels, hierarchy, icdcc, file = "data/icd_hcc.RData")

#############################################
######### Apply CCs
#############################################
# load CMS ICD/HCC crosswalks, labels, hierarchy rules
load(file = "data/icd_hcc.RData")

# Will apply this hierarchy to sample (random) patient data in wide format, with up to 25 diagnoses per patient

# Import sample data
pt <- readRDS("data/sampleptdata.rds")

# convert all fields to characters (no factors)
pt <- data.frame(lapply(pt, as.character), stringsAsFactors = F)

# reshape to long format
pt <- icd_wide_to_long(pt)

# add column for ICD (all data in this example are ICD9)
pt$icdversion <- 9

# Convert date and add column for year
pt$admtdate <- as.Date(pt$admtdate)
pt$year <- as.numeric(format(pt$admtdate, '%Y'))

# merge CCs to patient data based on ICD/year/version, and drop ICD info
pt <- merge(pt, icdcc, all.x = T)
rm(icdcc)

# Convert CC to numeric and drop those with missing CC (not all ICDs resolve to a CC by definition)
pt <- pt[!is.na(pt$cc),]
pt$cc <- as.numeric(pt$cc)

# keep id, admtdate, and cc columns only
pt <- pt[,c("id", "admtdate", "year", "cc")]

# Keep only unique records (multiple ICDs for a patient can resolve to same CC)
pt <- unique(pt)

#############################################
######### Apply Hierarchies
#############################################

# Duplicate ifcc column into CC column to merge with pt data, keep dup column
hierarchy$cc <- hierarchy$ifcc

# Merge hierarchy rules with patient data
pt <- merge(pt, hierarchy, all.x = TRUE)

todrop <- list()

# create a list of dataframes that contain the CCs that will be zero'd out
for (i in 1:6) {
  todrop[[i]] <- pt[!is.na(pt$ifcc),c(3, 4, 5 + i)]
}
rm(i)

# rename all dfs in list to same column names, rbind into one df
todrop <- lapply(1:length(todrop), function(x) {
  names(todrop[[x]]) <- c("id", "admtdate", "cc")
  return(todrop[[x]])
  }
)

todrop <- do.call(rbind, todrop)

# remove all NAs from CC field
todrop <- todrop[!is.na(todrop$cc),]

# set flag, all of these CCs will be dropped
todrop$todrop <- T

# merge drop flags with pt data
pt <- merge(pt, todrop, all.x = T)
rm(todrop)

# drop flagged patients and keep columns of interest
pt <- pt[is.na(pt$todrop), ]
pt <- pt[,c("id", "admtdate", "cc")]