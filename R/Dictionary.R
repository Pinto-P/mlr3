#' @title Key-Value Storage
#'
#' @usage NULL
#' @name Dictionary
#' @format [R6::R6Class] object.
#'
#' @description
#' A simple key-value store for [R6::R6] generator objects.
#' On retrieval of an object, the following applies:
#'
#' * R6 Factories (objects of class `R6ClassGenerator`) are initialized (with additional arguments).
#' * Functions are called (with additional arguments) and must return an instance of a [R6::R6] object.
#' * Other objects are returned as-is.
#'
#' @section Construction:
#' ```
#' d = Dictionary$new()
#' ```
#'
#' @section Methods:
#' * `get(key, ...)`\cr
#'   (`character(1)`, ...) -> `any`\cr
#'   Retrieves object with key `key` from the dictionary.
#'
#' * `mget(keys, ...)`\cr
#'   (`character()`, ...) -> named `list()`\cr
#'   Retrieves objects with keys `keys` from the dictionary, returns them in a list named with `keys`.
#'
#' * `has(keys)`\cr
#'   `character()` -> `logical()`\cr
#'   Returns a logical vector with `TRUE` at its i-th position, if the i-th key exists.
#'
#' * `keys(pattern)`\cr
#'   `character(1)` -> `character()`\cr
#'   Returns all keys which comply to the regular expression `pattern`.
#'
#' * `add(key, value)`\cr
#'   (`character(1)`, `any`) -> `self`\cr
#'   Adds object `value` to the dictionary with key `key`, potentially overwriting a
#'   previously stored value.
#'
#' * `remove(key)`\cr
#'   `character()` -> `self`\cr
#'   Removes object with key `key` from the dictionary.
#'
#' @family Dictionary
#' @export
Dictionary = R6Class("Dictionary",
  cloneable = FALSE,
  public = list(
    items = NULL,

    # construct, set container type (string)
    initialize = function() {
      self$items = new.env(parent = emptyenv())
    },

    format = function() {
      sprintf("<%s>", class(self)[1L])
    },

    print = function() {
      keys = self$keys()
      catf(sprintf("%s with %i stored values", format(self), length(keys)))
      catf(str_indent("Keys:", keys))

      catf(str_indent("\nPublic:", str_r6_interface(self)))
    },

    keys = function(pattern = NULL) {
      keys = ls(self$items, all.names = TRUE)
      if (!is.null(pattern))
        keys = keys[grepl(assert_string(pattern), keys)]
      keys
    },

    has = function(keys) {
      assert_character(keys, any.missing = FALSE)
      set_names(map_lgl(keys, exists, envir = self$items, inherits = FALSE), keys)
    },

    get = function(key, ...) {
      dictionary_retrieve(self, key, ...)
    },

    mget = function(keys, ...) {
      set_names(lapply(keys, self$get, ...), keys)
    },

    add = function(key, value, ...) {
      assert_id(key)
      assign(x = key, value = list(value = value, pars = list(...)), envir = self$items)
      invisible(self)
    },

    remove = function(key) {
      if (!self$has(key))
        stopf("Element with key '%s' not found!%s", key, did_you_mean(key, self$keys()))
      rm(list = key, envir = self$items)
      invisible(self)
    }
  )
)

dictionary_retrieve = function(self, key, ...) {
  obj = get0(key, envir = self$items, inherits = FALSE, ifnotfound = NULL)
  if (is.null(obj))
    stopf("Element with key '%s' not found!%s", key, did_you_mean(key, self$keys()))

  value = obj$value
  pars = insert_named(obj$pars, list(...))

  if (inherits(value, "R6ClassGenerator")) {
    value = do.call(value$new, pars)
  } else if (is.function(value)) {
    value = assert_r6(do.call(value, pars))
  }
  return(value)
}

#' @export
as.data.table.Dictionary = function(x, ...) {
  setkeyv(as.data.table(list(key = x$keys())), "key")[]
}
