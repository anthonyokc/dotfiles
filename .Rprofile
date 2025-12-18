if (is.null(getOption("anthony.profile.loaded"))) {
  if (interactive()) {
    cat("⚙️ Loading Interactive .Rprofile Settings...\n")
    cat("--------------------------------------------\n")
    q <- function(save = "no", ...) {
      quit(save = save, ...)
    }

    # Setup renv
    cat("📦 Setting up renv...\n")
    if (!requireNamespace("renv", quietly = TRUE)) utils::install.packages("renv")

    rs <- function() {
      renv::status()
    }
    ri <- function(package) {
      rlang::as_label(rlang::enexpr(package)) |>
        renv::install(prompt = FALSE)
    }
    ru <- function(package) {
      rlang::as_label(rlang::enexpr(package)) |>
        renv::update(prompt = FALSE)
    }
    retry_restore <- function() {
      repeat {
        logs <- capture.output(try(renv::restore(), silent = FALSE))
        print("Restoring packages...")
        fails <- grep("^- Installing ([^ ]+) .* FAILED$", logs, value = TRUE)
        if (length(fails) == 0) {
          print("All packages restored successfully.")
          break
        }
        print("Retrying failed packages...")
        pkg <- sub("^- Installing ([^ ]+) .* FAILED$", "\\1", fails[[1]])
        renv::install(pkg, prompt = FALSE)
      }
    }


    # Install and load default add-on packages
    packages <- c(
      "devtools",
      "gitcreds",
      "quarto",
      "targets",
      "nx10/httpgd",
      "styler",
      "reprex",
      "precommit",
      "lintr",
      "readr",
      "tidyr",
      "stringr",
      "lubridate",
      "tibble",
      "here",
      "future",
      "arrow"
    )

    for (package in packages) {
      # If package is from github, keeps only the package name
      if (grepl("/", package)) {
        package_clean <- gsub(".*/(.*)", "\\1", package)
      } else {
        package_clean <- package
      }

      # Checks if packages are installed, if not, installs with renv
      if (suppressMessages(!requireNamespace(package_clean))) {
        renv::install(package, prompt = FALSE)
        Sys.sleep(2)
      }

      suppressPackageStartupMessages(
        library(package_clean, character.only = TRUE)
      )
    }
    cat(paste0(" ✔️ Loaded ", packages[1], "\n"))
    cat(paste0(" ✔️ Loaded ", "usethis", "\n"))
    cat(paste0(" ✔️ Loaded ", packages[-1], "\n"), sep = "")

    rm(package, package_clean, packages) # Clean up namespace

    # Conflict preferences
    # WARNING: This actually doesn't fix anything yet
    # the options below do that. Hopefully future versions of conflicted will.
    # cat("\n⚔️ Setting conflict preferences...\n")
    # conflicted::conflicts_prefer(
    #   dplyr::filter
    # )

    # Install but don't load packages, so we can set them as default
    # This allows for loading after so their functions aren't masked
    cat("\n⚔️ Setting these to load after defaults so their functions aren't masked...\n")
    packages_to_default_load <- c(
      "dplyr"
    )

    for (package in packages_to_default_load) {
      # If package is from github, keeps only the package name
      if (grepl("/", package)) {
        package_clean <- gsub(".*/(.*)", "\\1", package)
      } else {
        package_clean <- package
      }

      if (suppressMessages(!requireNamespace(package))) {
        renv::install(package, prompt = FALSE)
        Sys.sleep(2)
      }
    }
    cat(paste0(" ✔️ Loaded ", packages_to_default_load, "\n"), sep = "")

    options(defaultPackages = c(
      getOption("defaultPackages"),
      packages_to_default_load
    ))

    # Custom utility functions
    mv <- function(old_name, new_name) {
      assign(new_name, get(old_name, envir = .GlobalEnv), envir = .GlobalEnv)
      rm(list = old_name, envir = .GlobalEnv)
    }

    # targets future make
    tmf <- function(names = NULL, ...) {
      future::plan(future::multisession, workers = max(1, future::availableCores() - 1))
      targets::tar_make_future(names = names, ...)
    }

    # Start httpgd server
    cat("\n📊 Starting httpgd server on port 3333...\n")
    options(
      httpgd.port = 3333,
      httpgd.token = FALSE
    )

    options(
      httpgd = list(
        zoom = 1.5,
        width = 1500,
        height = 1500
      )
    )
  }

  cat("\n⚙️ Loading Non-Interactive .Rprofile Settings...\n")
  cat("--------------------------------------------------\n")

  # If Linux Only

  cat("🌐 Setting CRAN mirror to Posit Package Manager with Linux binaries...\n")
  options(repos = c(CRAN = sprintf("https://p3m.dev/cran/latest/bin/linux/noble-%s/%s", R.version["arch"], substr(getRversion(), 1, 3))))
  options(renv.config.repos.override = getOption("repos"))

  cat("😪 Disabling completion from languageserver to allow cmp_r to handle those...\n")
  options(
    languageserver.server_capabilities =
      list(completionProvider = FALSE, completionItemResolve = FALSE)
  )

  cat("🧵 Setting lintr configuration file to ~/.lintr...\n")
  options(lintr.linter_file = "~/.lintr")

  cat("🗺️ Setting tigris to use cache...\n")
  options(tigris_use_cache = TRUE)

  cat("\n🤠 YEEHAW! Done loading Anthony's .Rprofile\n\n")

  options(anthony.profile.loaded = TRUE)
}

