if (getOption("mlr3.debug", FALSE)) {
  options(
    warnPartialMatchAttr = TRUE,
    warnPartialMatchDollar = TRUE
  )
}

`[[.R6` = function(x, i, ...) {
  if (exists(i, envir = x, inherits = FALSE))
    return(get(i, envir = x))
  stop("R6 class ", paste0(class(x), collapse = "/") ," does not have slot '", i, "'!")
}

`$.R6` = function(x, name) {
  if (exists(name, envir = x, inherits = FALSE))
    return(get(name, envir = x))
  stop("R6 class ", paste0(class(x), collapse = "/") ," does not have slot '", name, "'!")
}

private = function(x) {
  if (!R6::is.R6(x))
    stop("Expected R6 class")
  x$.__enclos_env__[["private"]]
}
