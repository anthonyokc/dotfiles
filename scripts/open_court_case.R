#!/usr/bin/env -S R_PROFILE_USER=/dev/null ir run --vanilla
#| packages:
#|   - purrr
#| isolated: true

oklahoma_counties <- c(
  "Adair",
  "Alfalfa",
  "Atoka",
  "Beaver",
  "Beckham",
  "Blaine",
  "Bryan",
  "Caddo",
  "Canadian",
  "Carter",
  "Cherokee",
  "Choctaw",
  "Cimarron",
  "Cleveland",
  "Coal",
  "Comanche",
  "Cotton",
  "Craig",
  "Creek",
  "Custer",
  "Delaware",
  "Dewey",
  "Ellis",
  "Garfield",
  "Garvin",
  "Grady",
  "Grant",
  "Greer",
  "Harmon",
  "Harper",
  "Haskell",
  "Hughes",
  "Jackson",
  "Jefferson",
  "Johnston",
  "Kay",
  "Kingfisher",
  "Kiowa",
  "Latimer",
  "Le Flore",
  "Lincoln",
  "Logan",
  "Love",
  "Major",
  "Marshall",
  "Mayes",
  "McClain",
  "McCurtain",
  "McIntosh",
  "Murray",
  "Muskogee",
  "Noble",
  "Nowata",
  "Okfuskee",
  "Oklahoma",
  "Okmulgee",
  "Osage",
  "Ottawa",
  "Pawnee",
  "Payne",
  "Pittsburg",
  "Pontotoc",
  "Pottawatomie",
  "Pushmataha",
  "Roger Mills",
  "Rogers",
  "Seminole",
  "Sequoyah",
  "Stephens",
  "Texas",
  "Tillman",
  "Tulsa",
  "Wagoner",
  "Washington",
  "Washita",
  "Woods",
  "Woodward"
)

print_usage <- function() {
  writeLines(
    c(
      "Open an Oklahoma CF, CM, or TR court case in a browser.",
      "",
      "Usage:",
      "  open_court_case.R CASE --website WEBSITE [--county COUNTY]",
      "",
      "Arguments:",
      "  CASE                 Case number, such as CF-2018-422.",
      "  --website WEBSITE    One of: oscn, odcr, both.",
      "  --county COUNTY      Oklahoma county. If omitted, select with gum.",
      "  -h, --help           Show this help."
    )
  )
}

stop_cli <- function(message) {
  writeLines(
    paste0("Error: ", message),
    con = stderr()
  )
  quit(status = 2L)
}

parse_cli_arguments <- function(arguments) {
  if (length(arguments) == 0L || any(
    arguments %in% c(
      "-h",
      "--help"
    )
  )) {
    print_usage()
    quit(status = 0L)
  }

  values_list <- list(
    case_number = NULL,
    website = NULL,
    county = NULL
  )
  argument_index <- 1L

  while (argument_index <= length(arguments)) {
    argument <- arguments[[argument_index]]

    if (argument %in% c(
      "--website",
      "--county"
    )) {
      if (argument_index == length(arguments)) {
        stop_cli(
          paste0(argument, " requires a value.")
        )
      }

      option_name <- argument |>
        substring(3L)
      values_list[[option_name]] <- arguments[[argument_index + 1L]]
      argument_index <- argument_index + 2L
      next
    }

    if (startsWith(argument, "--")) {
      stop_cli(
        paste0("Unknown option: ", argument)
      )
    }

    if (!is.null(values_list$case_number)) {
      stop_cli("Provide exactly one case number.")
    }

    values_list$case_number <- argument
    argument_index <- argument_index + 1L
  }

  values_list
}

normalize_case_number <- function(case_number) {
  if (is.null(case_number)) {
    stop_cli("CASE is required.")
  }

  normalized_case_number <- case_number |>
    trimws() |>
    toupper()
  case_parts <- regmatches(
    normalized_case_number,
    regexec("^(CF|CM|TR)-(\\d{4})-(\\d+)$", normalized_case_number)
  )[[1L]]

  if (length(case_parts) == 0L) {
    stop_cli("CASE must match CF-YYYY-N, CM-YYYY-N, or TR-YYYY-N.")
  }

  list(
    number = paste(
      case_parts[[2L]],
      case_parts[[3L]],
      as.integer(case_parts[[4L]]),
      sep = "-"
    ),
    type = case_parts[[2L]],
    year = as.integer(case_parts[[3L]]),
    sequence = as.integer(case_parts[[4L]])
  )
}

select_county <- function(county) {
  if (is.null(county) || !nzchar(
    trimws(county)
  )) {
    if (!nzchar(
      Sys.which("gum")
    )) {
      stop_cli("--county is required when gum is unavailable.")
    }

    county <- system2(
      "gum",
      c(
        "filter",
        "--placeholder",
        shQuote("Select an Oklahoma county")
      ),
      input = oklahoma_counties,
      stdout = TRUE
    )

    if (length(county) == 0L) {
      stop_cli("County selection was canceled.")
    }
  }

  county_index <- match(
    tolower(
      trimws(county[[1L]])
    ),
    tolower(oklahoma_counties)
  )
  if (is.na(county_index)) {
    stop_cli(
      paste0("Unknown Oklahoma county: ", county[[1L]])
    )
  }

  list(
    name = oklahoma_counties[[county_index]],
    odcr_code = sprintf("%03d", county_index)
  )
}

build_case_urls <- function(case_parts_list, county_parts_list, website) {
  if (is.null(website)) {
    stop_cli("--website is required.")
  }

  website <- website |>
    trimws() |>
    tolower()
  if (!website %in% c(
    "oscn",
    "odcr",
    "both"
  )) {
    stop_cli("--website must be oscn, odcr, or both.")
  }

  oscn_url <- paste0(
    "https://www.oscn.net/dockets/GetCaseInformation.aspx?db=",
    gsub(
      " ",
      "",
      tolower(county_parts_list$name),
      fixed = TRUE
    ),
    "&number=",
    utils::URLencode(case_parts_list$number, reserved = TRUE)
  )
  odcr_case_key <- paste0(
    county_parts_list$odcr_code,
    "-",
    case_parts_list$type,
    "++",
    substr(
      as.character(case_parts_list$year),
      3L,
      4L
    ),
    sprintf("%05d", case_parts_list$sequence)
  )
  odcr_url <- paste0(
    "https://odcr.com/detail?casekey=",
    odcr_case_key,
    "&court=",
    county_parts_list$odcr_code,
    "-"
  )

  switch(website,
    oscn = c(
      oscn_url
    ),
    odcr = c(
      odcr_url
    ),
    both = c(
      oscn_url,
      odcr_url
    )
  )
}

open_case_url <- function(case_url) {
  wsl_browser_command <- Sys.which("brave_wsl_open.sh")

  if (nzchar(wsl_browser_command)) {
    system2(
      wsl_browser_command,
      shQuote(case_url),
      stdout = FALSE,
      stderr = FALSE,
      wait = FALSE
    )
    return(
      invisible(NULL)
    )
  }

  utils::browseURL(case_url)
}

open_case_urls <- function(case_urls) {
  purrr::walk(case_urls, open_case_url)
}

run_open_court_case_cli <- function(
  arguments = commandArgs(trailingOnly = TRUE)
) {
  options_list <- parse_cli_arguments(arguments)
  case_list <- normalize_case_number(options_list$case_number)
  county_list <- select_county(options_list$county)
  selected_website <- options_list$website
  case_urls <- build_case_urls(case_list, county_list, selected_website)

  writeLines(
    paste("Opening", case_urls)
  )
  open_case_urls(case_urls)
}

if (sys.nframe() == 0L) {
  run_open_court_case_cli()
}
