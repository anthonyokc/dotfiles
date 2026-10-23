suppressPackageStartupMessages(library(jsonlite))

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

stdin_con <- file("stdin", open = "rb")
stdout_con <- file("stdout", open = "wb")

send_message <- function(message) {
  body <- toJSON(message, auto_unbox = TRUE, null = "null", digits = NA)
  bytes <- charToRaw(enc2utf8(body))
  header <- sprintf("Content-Length: %d\r\n\r\n", length(bytes))
  writeBin(charToRaw(header), stdout_con)
  writeBin(bytes, stdout_con)
  flush(stdout_con)
}

read_message <- function() {
  content_length <- NULL

  repeat {
    line <- readLines(stdin_con, n = 1, warn = FALSE)
    if (length(line) == 0) return(NULL)

    line <- sub("\r$", "", line)
    if (line == "") break

    parts <- strsplit(line, ":", fixed = TRUE)[[1]]
    if (length(parts) >= 2 && tolower(parts[[1]]) == "content-length") {
      content_length <- as.integer(trimws(paste(parts[-1], collapse = ":")))
    }
  }

  if (is.null(content_length) || is.na(content_length)) return(NULL)

  body <- readChar(stdin_con, nchars = content_length, useBytes = TRUE)
  fromJSON(body, simplifyVector = FALSE)
}

make_text_result <- function(text, is_error = FALSE) {
  list(content = list(list(type = "text", text = text)), isError = is_error)
}

format_r_value <- function(value) {
  paste(capture.output(str(value, max.level = 2, give.attr = FALSE, vec.len = 20)), collapse = "\n")
}

run_r_code <- function(code) {
  warnings <- character()

  result <- tryCatch(
    withCallingHandlers(
      {
        output <- capture.output({
          visible <- withVisible(eval(parse(text = code), envir = .GlobalEnv))
        })
        list(ok = TRUE, output = output, visible = visible)
      },
      warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) list(ok = FALSE, error = conditionMessage(e))
  )

  sections <- character()

  if (length(warnings) > 0) {
    sections <- c(sections, "Warnings:", paste(sprintf("- %s", warnings), collapse = "\n"))
  }

  if (!isTRUE(result$ok)) {
    sections <- c(sections, "Error:", result$error)
    return(make_text_result(paste(sections, collapse = "\n"), is_error = TRUE))
  }

  if (length(result$output) > 0) {
    sections <- c(sections, "Output:", paste(result$output, collapse = "\n"))
  }

  if (isTRUE(result$visible$visible)) {
    sections <- c(sections, "Value:", format_r_value(result$visible$value))
  }

  if (length(sections) == 0) sections <- "OK"
  make_text_result(paste(sections, collapse = "\n"))
}

inspect_global_env <- function(pattern = NULL, all_names = FALSE) {
  names <- ls(envir = .GlobalEnv, all.names = isTRUE(all_names))
  if (!is.null(pattern) && nzchar(pattern)) {
    names <- names[grepl(pattern, names)]
  }

  if (length(names) == 0) return(make_text_result("No objects found in .GlobalEnv."))

  entries <- vapply(names, function(name) {
    value <- get(name, envir = .GlobalEnv)
    dims <- dim(value)
    dim_text <- if (is.null(dims)) "" else sprintf(", dim=%s", paste(dims, collapse = "x"))
    preview <- format_r_value(value)
    sprintf(
      "%s: class=%s, typeof=%s, length=%s, size=%s%s\n%s",
      name,
      paste(class(value), collapse = "/"),
      typeof(value),
      length(value),
      format(object.size(value), units = "auto"),
      dim_text,
      preview
    )
  }, character(1))

  make_text_result(paste(entries, collapse = "\n\n"))
}

tools <- list(
  list(
    name = "r_eval",
    description = "Evaluate R code in a persistent R session's .GlobalEnv and return output, warnings, errors, and visible value structure.",
    inputSchema = list(
      type = "object",
      properties = list(
        code = list(type = "string", description = "R code to evaluate.")
      ),
      required = list("code")
    )
  ),
  list(
    name = "r_global_env",
    description = "Inspect objects currently stored in the persistent R session's .GlobalEnv.",
    inputSchema = list(
      type = "object",
      properties = list(
        pattern = list(type = "string", description = "Optional regular expression used to filter object names."),
        all_names = list(type = "boolean", description = "Include names that begin with a dot.")
      )
    )
  )
)

handle_request <- function(message) {
  id <- message$id
  method <- message$method
  params <- message$params %||% list()

  if (is.null(id)) return(NULL)

  result <- switch(
    method,
    initialize = list(
      protocolVersion = params$protocolVersion %||% "2024-11-05",
      capabilities = list(tools = list()),
      serverInfo = list(name = "r-session", version = "0.1.0"),
      instructions = "Use r_eval to run R code and r_global_env to inspect .GlobalEnv in this persistent R session."
    ),
    `tools/list` = list(tools = tools),
    `tools/call` = {
      name <- params$name
      arguments <- params$arguments %||% list()

      if (identical(name, "r_eval")) {
        run_r_code(arguments$code %||% "")
      } else if (identical(name, "r_global_env")) {
        inspect_global_env(arguments$pattern %||% NULL, arguments$all_names %||% FALSE)
      } else {
        return(list(jsonrpc = "2.0", id = id, error = list(code = -32602, message = sprintf("Unknown tool: %s", name))))
      }
    },
    ping = list(),
    return(list(jsonrpc = "2.0", id = id, error = list(code = -32601, message = sprintf("Method not found: %s", method))))
  )

  list(jsonrpc = "2.0", id = id, result = result)
}

repeat {
  message <- read_message()
  if (is.null(message)) break

  response <- tryCatch(
    handle_request(message),
    error = function(e) list(jsonrpc = "2.0", id = message$id %||% NULL, error = list(code = -32603, message = conditionMessage(e)))
  )

  if (!is.null(response) && !is.null(response$id)) send_message(response)
}
