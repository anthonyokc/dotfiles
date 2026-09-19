if (is.null(getOption("anthony.profile.loaded"))) {
  rprofile_packages_file <- path.expand("~/.Rprofile_packages")
  if (file.exists(rprofile_packages_file)) {
    anthony_rprofile_packages_available <- TRUE
    source(rprofile_packages_file)
  } else {
    anthony_rprofile_packages_available <- FALSE
    warning("R profile package configuration does not exist at ", rprofile_packages_file)
    anthony_rprofile_packages <- character()
    anthony_rprofile_default_packages <- character()
    anthony_validate_rprofile_packages <- function() invisible(character())
  }
  rm(rprofile_packages_file)

  if (interactive()) {
    cat("⚙️ Loading Interactive .Rprofile Settings...\n")
    cat("--------------------------------------------\n")
    q <- function(save = "no", ...) {
      quit(save = save, ...)
    }

    # Keep renv's project library first when a project is active.
    user_library <- Sys.getenv("R_LIBS_USER")

    if (!dir.exists(user_library)) {
      dir.create(user_library, recursive = TRUE, showWarnings = FALSE)
    }

    if (!nzchar(Sys.getenv("RENV_PROJECT"))) {
      .libPaths(c(user_library, .libPaths()))
    }

    # Setup renv
    cat("📦 Setting up renv...\n")
    if (!requireNamespace("renv", quietly = TRUE)) utils::install.packages("renv")

    cat("🌐 Setting CRAN mirror to Posit Package Manager with Linux binaries...\n")
    r_version <- paste(R.version$major, strsplit(R.version$minor, ".", fixed = TRUE)[[1]][1], sep = ".")
    r_arch <- R.version$arch
    p3m_repo <- sprintf(
      "https://p3m.dev/cran/latest/bin/linux/noble-%s/%s",
      r_arch,
      r_version
    )
    options(repos = c(CRAN = p3m_repo))
    options(renv.config.repos.override = getOption("repos"))

    if (Sys.getenv("RNVIM_TMPDIR") != "" && !requireNamespace("nvimcom", quietly = TRUE)) {
      nvimcom_path <- "~/.local/share/nvim/lazy/R.nvim/nvimcom"

      if (dir.exists(path.expand(nvimcom_path))) {
        renv::install(nvimcom_path, prompt = FALSE)
      } else {
        warning("R.nvim started R, but bundled nvimcom source was not found at: ", nvimcom_path)
      }

      rm(nvimcom_path)
    }

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

    # Install, validate, and load default add-on packages
    packages <- anthony_rprofile_packages
    if (anthony_rprofile_packages_available) {
      installer <- path.expand("~/scripts/install_rprofile_packages")
      active_project <- Sys.getenv("RENV_PROJECT")
      installer_args <- if (nzchar(active_project)) {
        c("--project", shQuote(active_project))
      } else {
        character()
      }
      install_status <- system2(installer, args = installer_args)
      if (!identical(install_status, 0L)) {
        stop("R profile package installation or validation failed.", call. = FALSE)
      }
      anthony_validate_rprofile_packages()
      rm(active_project, install_status, installer, installer_args)
    }

    for (package in packages) {
      # If package is from github, keeps only the package name
      if (grepl("/", package)) {
        package_clean <- gsub(".*/(.*)", "\\1", package)
      } else {
        package_clean <- package
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
    packages_to_default_load <- anthony_rprofile_default_packages

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

    # Configure httpgd over Tailscale Serve
    httpgd_tailscale <- "~/.Rprofile_tailscale"
    if (file.exists(httpgd_tailscale)) {
      source(httpgd_tailscale)
    }

    # Use custom script to open with default Windows browser within WSL
    options(browser = function(url) {
      system2("brave_wsl_open.sh", url, wait = FALSE)
    })
  }

  cat("\n⚙️ Loading Non-Interactive .Rprofile Settings...\n")
  cat("--------------------------------------------------\n")

  source("~/.Rprofile_helpers")

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
