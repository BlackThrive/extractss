
analyse_records <- function(data_file,
                            geography = c("la","region"),
                            ethnicity_definition = c("self","officer"),
                            comparison = c("White","Black"),
                            date = c("by_year", "by_month","12_month_periods")){
  # load stop records
  # check if data file is an object in environ or a csv
  data <- if(is.object(data_file)) data_file else read.csv(data_file)
  # subset to England & Wales
  data <- data %>%
    subset(., country != "Northern Ireland" & country != "Scotland")

  # load population estimates
  if(geography == "la"){
    population_ests <- read.csv("./data/la_pop_estimates_2021_2.csv")
    population_ests <- population_ests %>%
      # translate ONS missing estimate characters to NAs
      dplyr::mutate(across(ncol(population_ests)), dplyr::na_if(., "!")) %>%
      dplyr::mutate(across(ncol(population_ests)), dplyr::na_if(., "-")) %>%
      dplyr::mutate(across(ncol(population_ests)), dplyr::na_if(., "~"))
  }
  else if(geography == "region"){
    population_ests <- read.csv("./data/regional_pop_ests_sep_21.csv")
  }

  # set region of all Welsh LAs to 'Wales' and of Scottish LAs to 'Scotland'
  data$region[which(data$country == "Wales")] <- "Wales"
  #data$region[which(data$country == "Scotland")] <- "Scotland"

  # collapse self-defined ethnicity (not necessary for officer-defined)
  data$self_defined_ethnicity <- as.factor(data$self_defined_ethnicity)
  data$self_defined_ethnicity <-
    forcats::fct_collapse(data$self_defined_ethnicity,
      Asian = c("Asian/Asian British - Any other Asian background",
                "Asian/Asian British - Bangladeshi",
                "Asian/Asian British - Chinese",
                "Asian/Asian British - Indian",
                "Asian/Asian British - Pakistani"),
      Black = c("Black/African/Caribbean/Black British - African",
                "Black/African/Caribbean/Black British - Any other Black/African/Caribbean background",
                "Black/African/Caribbean/Black British - Caribbean"),
      Mixed = c("Mixed/Multiple ethnic groups - Any other Mixed/Multiple ethnic background",
                "Mixed/Multiple ethnic groups - White and Asian",
                "Mixed/Multiple ethnic groups - White and Black African",
                "Mixed/Multiple ethnic groups - White and Black Caribbean"),
      Other = c("Other ethnic group - Any other ethnic group",
                "Other ethnic group - Not stated"),
      White = c("White - Any other White background",
                "White - English/Welsh/Scottish/Northern Irish/British",
                "White - Irish")
  )

  # define ethnicity as either self-defined or officer-defined
  if(ethnicity_definition == "self"){
    data <- data %>%
      dplyr::mutate(
        ethnicity = self_defined_ethnicity
      )
  }
  else if(ethnicity_definition == "officer"){
    data <- data %>%
      dplyr::mutate(
        ethnicity = officer_defined_ethnicity
      )
  }

  ethnicity_1 <- comparison[1]
  ethnicity_2 <- comparison[2]

  # subset to ethnicities to compare
  data_subset <- subset(data, ethnicity == ethnicity_1 | ethnicity == ethnicity_2)
  # refactor. First in comparison is reference, second is treatment
  data_subset$ethnicity <- factor(data_subset$ethnicity, levels = comparison)

  # separate date into separate columns
  data_subset$year <- as.numeric(substr(data_subset$date, 1, 4))
  data_subset$month <- as.numeric(substr(data_subset$date, 6, 7))
  data_subset$day <- as.numeric(substr(data_subset$date, 9, 10))

  # make year_month variable for indexing
  data_subset$year_month <-
    as.Date(paste(
      as.character(data_subset$year),
      as.character(data_subset$month),"01", sep= "-"))

  # if date by year, take sequence from min to max
  if(date == "by_year"){
    dates <- min(data_subset$year):max(data_subset$year)
  }
  # if date by month, take sequence of each month from start
  else if(date == "by_month"){
    date_set <- unique(data_subset$year_month)
    dates <- date_set[order(date_set)]
  }
  # if date by 12 months, define oldest year and month and create boundaries
  # for each 12 months
  else if(date == "12_month_periods"){
    oldest_year <- min(data_subset$year)
    oldest_month <- as.numeric(substr(min(data_subset$year_month), 6, 7))

    # does the 12 months cross to a new year?
    passes_year <- if(oldest_month + 11 > 12) TRUE else FALSE

    # calculate start month for next 12 months
    next_month <- if(oldest_month > 1) oldest_month - 1 else 12

    # create list to be indexed for defining 12 month boundary
    dates <- list(
      # first 12 months
      c(as.Date(paste(oldest_year, oldest_month, "01", sep = "-"), format = "%Y-%m-%d"),
        as.Date(paste(if(passes_year) oldest_year + 1 else oldest_year,
                      next_month, "01", sep = "-"),format = "%Y-%m-%d")),
      # second 12 months
      c(as.Date(paste(if(passes_year) oldest_year + 2 else oldest_year + 1,
                      oldest_month, "01", sep = "-"),  format = "%Y-%m-%d"),
        as.Date(paste(if(passes_year) oldest_year + 2 else oldest_year + 1,
                      next_month, "01", sep = "-"),  format = "%Y-%m-%d")),
      # third 12 months
      c(as.Date(paste(if(passes_year) oldest_year + 3 else oldest_year + 2,
                      oldest_month, "01", sep = "-"),  format = "%Y-%m-%d"),
        as.Date(paste(if(passes_year) oldest_year + 3 else oldest_year + 2,
                      next_month, "01", sep = "-"),  format = "%Y-%m-%d")))

  }

  # Summarisation starts here

  # The code below creates a contingency table for each LAD and runs chi-square
  # and Fisher's exact tests on it.
  # It also creates an overall contingency table on which to base combined statistics.

  data_subset$la_name[which(data_subset$la_name == "Rhondda Cynon Taf")] <- "Rhondda Cynon Taff"
  data_subset$region[which(data_subset$region == "Yorkshire and The Humber")] <- "Yorkshire and the Humber"

  if(geography == "la"){

    las <- unique(data_subset$la_name) # get la names from the dataset
    all_results <- data.frame() # initialise
    all_mats <- matrix(data = c(0,0,0,0), ncol = 2, nrow = 2)
    all_dfs <- data.frame()
    count <- 0

    # regional fork would be here

    for(i in 1:length(las)){
      results_df <- data.frame() # initialise

      # get data for la
      la <- unique(data_subset[which(data_subset$la_name == las[i]), "la_name"])
      county <- unique(data_subset[which(data_subset$la_name == las[i]), "county"])
      region <- unique(data_subset[which(data_subset$la_name == las[i]), "region"])
      country <- unique(data_subset[which(data_subset$la_name == las[i]), "country"])
      force <- unique(data_subset[which(data_subset$la_name == las[i]), "force"])

      for(j in 1:length(dates)){
        if(date == "by_year"){
          this_date <- dates[j]
          temp_df <- data_subset %>% # subset to la
            subset(., la_name == la & year == this_date)
        }
        else if(date == "by_month"){
          this_date <- dates[j]
          temp_df <- data_subset %>% # subset to la
            subset(., la_name == la & year_month == this_date)
        }
        else if(date == "12_month_periods"){
          this_date <- dates[[j]]
          temp_df <- data_subset %>% # subset to la
            subset(., la_name == la & year_month >= this_date[1] & year_month <= this_date[2])
          # rename this date for variable name later
          this_date <- paste0("12 months to ", substr(dates[[j]][2], 1, 7))
        }

        if(length(unique(temp_df$ethnicity)) == 2){ # &
          # !is.na(population_ests[which(population_ests$LAD == la), ethnicity_1]) &
          # !is.na(population_ests[which(population_ests$LAD == la), ethnicity_2])){ # check that there are stops for both white and black individuals

          # collect stats
          temp_df <- temp_df %>%
            dplyr::group_by(ethnicity) %>%
            dplyr::summarise(
              stopped = dplyr::n()
            ) %>%
            dplyr::mutate(
              pop = c(as.numeric(population_ests[which(population_ests$LAD == la), "White"]),
                      as.numeric(population_ests[which(population_ests$LAD == la), "Black"])),
              percentage = 100 * (stopped/pop),
              not_stopped = pop - stopped
            ) %>%
            as.data.frame()

          row.names(temp_df) <- temp_df$ethnicity

          black <- data.frame("Black" = c("stopped" = temp_df["Black", "stopped"], "not_stopped" = temp_df["Black", "not_stopped"]))

          white <- data.frame("White" = c("stopped" = temp_df["White", "stopped"], "not_stopped" = temp_df["White", "not_stopped"]))

          bw_mat <- as.matrix(cbind(black, white)) # matrix for crosstable
          bw_df <- as.data.frame(bw_mat) # df for custom rr function


          if(sum(is.na(bw_mat)) == 0){ # if there are figures for all cells, run stats
            # use tryCatch to collect warning messages
            xtab <- tryCatch(gmodels::CrossTable(bw_mat, chisq = T, fisher = T, expected = T),
                             warning = function(w) return(list(gmodels::CrossTable(bw_mat, chisq = T, fisher = T, expected = T), w)))
            rr <- riskratio_from_df(bw_df, "Stop & Search")
            results_df <- data.frame(
              "date" = this_date,
              "la" = la,
              "county" = county,
              "region" = region,
              "country" = country,
              "force" = force,
              "black_stopped" = temp_df["Black", "stopped"],
              "black_not_stopped" = temp_df["Black", "not_stopped"],
              "black_population" = temp_df["Black", "pop"],
              "black_stop_rate" = temp_df["Black", "percentage"],
              "white_stopped" = temp_df["White", "stopped"],
              "white_not_stopped" = temp_df["White", "not_stopped"],
              "white_population" = temp_df["White", "pop"],
              "white_stop_rate" = temp_df["White", "percentage"],
              "or" = ifelse(is.list(xtab[[1]]),
                            xtab[[1]][["fisher.ts"]][["estimate"]][["odds ratio"]],
                            xtab[["fisher.ts"]][["estimate"]][["odds ratio"]]),
              "or_ci_low" = ifelse(is.list(xtab[[1]]),
                                   xtab[[1]][["fisher.ts"]][["conf.int"]][1],
                                   xtab[["fisher.ts"]][["conf.int"]][1]),
              "or_ci_upp" = ifelse(is.list(xtab[[1]]),
                                   xtab[[1]][["fisher.ts"]][["conf.int"]][2],
                                   xtab[["fisher.ts"]][["conf.int"]][2]),
              "rr" = rr$rr,
              "rr_ci_low" = rr$ci_low,
              "rr_ci_upp" = rr$ci_upp,
              "warning" = ifelse(is.list(xtab[[1]]), xtab[[2]][["message"]], NA))

            all_mats <- all_mats + bw_mat
            count <- count + 1 # increase count of areas for which stats have been acquired

          }
          else{ # if there are missing values, don't run stats but still add frequency data
            results_df <- data.frame(
              "date" = this_date,
              "la" = la,
              "county" = county,
              "region" = region,
              "country" = country,
              "force" = force,
              "black_stopped" = temp_df["Black", "stopped"],
              "black_not_stopped" = temp_df["Black", "not_stopped"],
              "black_population" = temp_df["Black", "pop"],
              "black_stop_rate" = temp_df["Black", "percentage"],
              "white_stopped" = temp_df["White", "stopped"],
              "white_not_stopped" = temp_df["White", "not_stopped"],
              "white_population" = temp_df["White", "pop"],
              "white_stop_rate" = temp_df["White", "percentage"],
              "or" = NA,
              "or_ci_low" = NA,
              "or_ci_upp" = NA,
              "rr" = NA,
              "rr_ci_low" = NA,
              "rr_ci_upp" = NA,
              "warning" = NA)
          }

        }
        # if there is not data for both black and white, and/or there are missing values
        else{
          results_df <- data.frame(
            "date" = this_date,
            "la" = la,
            "county" = county,
            "region" = region,
            "country" = country,
            "force" = force,
            "black_stopped" = NA,
            "black_not_stopped" = NA,
            "black_population" = NA,
            "black_stop_rate" = NA,
            "white_stopped" = NA,
            "white_not_stopped" = NA,
            "white_population" = NA,
            "white_stop_rate" = NA,
            "or" = NA,
            "or_ci_low" = NA,
            "or_ci_upp" = NA,
            "rr" = NA,
            "rr_ci_low" = NA,
            "rr_ci_upp" = NA,
            "warning" = NA)
        }


        all_results <- rbind(all_results, results_df) # add results to all results
        all_dfs <- as.data.frame(all_mats)
        cat("\014")
        print(paste0(i, " of ", length(las), " complete (", round(100 * (i / length(las)),2 ), "%)"))
      }
    }
  }
  else if(geography == "region"){

    regions <- unique(subset_df$region) # get la names from the dataset
    all_results <- data.frame() # initialise
    all_mats <- matrix(data = c(0,0,0,0), ncol = 2, nrow = 2)
    all_dfs <- data.frame()
    count <- 0


    for(i in 1:length(regions)){
      results_df <- data.frame() # initialise

      # get data for la
      #la <- unique(subset_df[which(subset_df$la_name == las[i]), "la_name"])
      #county <- unique(subset_df[which(subset_df$la_name == las[i]), "county"])
      this_region <- unique(subset_df[which(subset_df$region == regions[i]), "region"]) # need to use different name to that in subset_df
      country <- unique(subset_df[which(subset_df$region == regions[i]), "country"])
      #force <- unique(subset_df[which(subset_df$region == regions[i]), "force"])

      for(j in 1:length(dates)){
        if(date == "by_year"){
          this_date <- dates[j]
          temp_df <- data_subset %>% # subset to la
            subset(., region == this_region & year == this_date)
        }
        else if(date == "by_month"){
          this_date <- dates[j]
          temp_df <- data_subset %>% # subset to la
            subset(., region == this_region & year_month == this_date)
        }
        else if(date == "12_month_periods"){
          this_date <- dates[[j]]
          temp_df <- data_subset %>% # subset to la
            subset(., region == this_region & year_month >= this_date[1] & year_month <= this_date[2])
          # rename this date for variable name later
          this_date <- paste0("12 months to ", substr(dates[[j]][2], 1, 7))
        }

        if(length(unique(temp_df$ethnicity)) == 2){ # check that there are stops for both white and black individuals

          # collect stats
          temp_df <- temp_df %>%
            dplyr::group_by(ethnicity) %>%
            dplyr::summarise(
              stopped = n()
            ) %>%
            dplyr::mutate(
              pop = c(as.numeric(population_ests[which(population_ests$Region == this_region), "White"]),
                      as.numeric(population_ests[which(population_ests$Region == this_region), "Black"])),
              percentage = 100 * (stopped/pop),
              not_stopped = pop - stopped
            ) %>%
            as.data.frame()

          row.names(temp_df) <- temp_df$ethnicity

          black <- data.frame("Black" = c("stopped" = temp_df["Black", "stopped"], "not_stopped" = temp_df["Black", "not_stopped"]))

          white <- data.frame("White" = c("stopped" = temp_df["White", "stopped"], "not_stopped" = temp_df["White", "not_stopped"]))

          bw_mat <- as.matrix(cbind(black, white)) # matrix for crosstable
          bw_df <- as.data.frame(bw_mat) # df for custom rr function


          if(sum(is.na(bw_mat)) == 0){ # if there are figures for all cells, run stats
            # use tryCatch to collect warning messages
            xtab <- tryCatch(gmodels::CrossTable(bw_mat, chisq = T, fisher = T, expected = T),
                             warning = function(w) return(list(gmodels::CrossTable(bw_mat, chisq = T, fisher = T, expected = T), w)))
            rr <- riskratio_from_df(bw_df, "Stop & Search")
            results_df <- data.frame(
              # "la" = la,
              # "county" = county,
              "date" = this_date,
              "region" = this_region,
              "country" = country,
              #"force" = force,
              "black_stopped" = temp_df["Black", "stopped"],
              "black_not_stopped" = temp_df["Black", "not_stopped"],
              "black_population" = temp_df["Black", "pop"],
              "black_stop_rate" = temp_df["Black", "percentage"],
              "white_stopped" = temp_df["White", "stopped"],
              "white_not_stopped" = temp_df["White", "not_stopped"],
              "white_population" = temp_df["White", "pop"],
              "white_stop_rate" = temp_df["White", "percentage"],
              "or" = ifelse(is.list(xtab[[1]]),
                            xtab[[1]][["fisher.ts"]][["estimate"]][["odds ratio"]],
                            xtab[["fisher.ts"]][["estimate"]][["odds ratio"]]),
              "or_ci_low" = ifelse(is.list(xtab[[1]]),
                                   xtab[[1]][["fisher.ts"]][["conf.int"]][1],
                                   xtab[["fisher.ts"]][["conf.int"]][1]),
              "or_ci_upp" = ifelse(is.list(xtab[[1]]),
                                   xtab[[1]][["fisher.ts"]][["conf.int"]][2],
                                   xtab[["fisher.ts"]][["conf.int"]][2]),
              "rr" = rr$rr,
              "rr_ci_low" = rr$ci_low,
              "rr_ci_upp" = rr$ci_upp,
              "warning" = ifelse(is.list(xtab[[1]]), xtab[[2]][["message"]], NA))

            all_mats <- all_mats + bw_mat
            count <- count + 1 # increase count of areas for which stats have been acquired

          }
          else{ # if there are missing values, don't run stats but still add frequency data
            results_df <- data.frame(
              # "la" = la,
              # "county" = county,
              "date" = this_date,
              "region" = this_region,
              "country" = country,
              #"force" = force,
              "black_stopped" = temp_df["Black", "stopped"],
              "black_not_stopped" = temp_df["Black", "not_stopped"],
              "black_population" = temp_df["Black", "pop"],
              "black_stop_rate" = temp_df["Black", "percentage"],
              "white_stopped" = temp_df["White", "stopped"],
              "white_not_stopped" = temp_df["White", "not_stopped"],
              "white_population" = temp_df["White", "pop"],
              "white_stop_rate" = temp_df["White", "percentage"],
              "or" = NA,
              "or_ci_low" = NA,
              "or_ci_upp" = NA,
              "rr" = NA,
              "rr_ci_low" = NA,
              "rr_ci_upp" = NA,
              "warning" = NA)
          }

        }
        # if there is not data for both black and white, and/or there are missing values
        else{
          results_df <- data.frame(
            # "la" = la,
            # "county" = county,
            "date" = this_date,
            "region" = this_region,
            "country" = country,
            #"force" = force,
            "black_stopped" = NA,
            "black_not_stopped" = NA,
            "black_population" = NA,
            "black_stop_rate" = NA,
            "white_stopped" = NA,
            "white_not_stopped" = NA,
            "white_population" = NA,
            "white_stop_rate" = NA,
            "or" = NA,
            "or_ci_low" = NA,
            "or_ci_upp" = NA,
            "rr" = NA,
            "rr_ci_low" = NA,
            "rr_ci_upp" = NA,
            "warning" = NA)
        }


        all_results <- rbind(all_results, results_df) # add results to all results
        all_dfs <- as.data.frame(all_mats)
        cat("\014")
        print(paste0(i, " of ", length(regions), " complete (", round(100 * (i / length(regions)),2 ), "%)"))
      }
    }
  }
  return(all_results)
}

test <- analyse_records("./data/data_36_months_to_dec_21.csv",
                        geography = "region",
                        ethnicity_definition = "self",
                        comparison = c("White","Black"),
                        date = "by_month")

saveRDS(test,file="./data/ss_by_month_region.rds")