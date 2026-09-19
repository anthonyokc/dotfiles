args <- commandArgs(trailingOnly = TRUE)
project <- if (length(args) == 1L) args[[1]] else NULL

if (!is.null(project)) {
  renv::load(project = project)
} else {
  user_library <- Sys.getenv("R_LIBS_USER")
  .libPaths(c(user_library, .libPaths()))
}

profile_packages_file <- file.path(Sys.getenv("HOME"), ".Rprofile_packages")
if (!file.exists(profile_packages_file)) {
  stop(
    "R profile package configuration does not exist at ",
    profile_packages_file,
    call. = FALSE
  )
}

source(profile_packages_file)
package_names <- anthony_validate_rprofile_packages()
namespace_errors <- vapply(
  package_names,
  function(package) {
    tryCatch(
      {
        loadNamespace(package)
        ""
      },
      error = conditionMessage
    )
  },
  character(1)
)
namespace_errors <- namespace_errors[nzchar(namespace_errors)]

if (length(namespace_errors) > 0L) {
  details <- paste0(
    names(namespace_errors),
    ": ",
    namespace_errors,
    collapse = "\n"
  )
  stop("R profile namespace validation failed:\n", details, call. = FALSE)
}
