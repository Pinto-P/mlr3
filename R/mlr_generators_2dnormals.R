#' @title 2d Normals Classification Task Generator
#'
#' @name mlr_generators_2dnormals
#' @format [R6::R6Class] inheriting from [Generator].
#' @include Generator.R
#'
#' @description
#' A [Generator] for the 2d normals task in [mlbench::mlbench.2dnormals()].
#' @export
Generator2DNormals = R6Class("Generator2DNormals",
  inherit = Generator,
  public = list(
    initialize = function(...) {
      param_set = ParamSet$new(list(
        ParamInt$new("cl", lower = 2L),
        ParamDbl$new("r", lower = 1L),
        ParamDbl$new("sd", lower = 0L)
      ))
      super$initialize(id = "2dnormals", "classif", "mlbench", param_set, list(...))
    }
  ),

  private = list(
    .generate = function(n) {
      data = invoke(mlbench::mlbench.2dnormals, n = n, .args = self$param_set$values)
      data = insert_named(as.data.table(data$x), list(class = data$classes))
      TaskClassif$new(sprintf("%s_%i", self$id, n), as_data_backend(data), target = "class")
    }
  )
)
