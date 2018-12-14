% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/mlr_resamplings_repeated_cv.R
\docType{data}
\name{mlr_resamplings_repeated_cv}
\alias{mlr_resamplings_repeated_cv}
\alias{ResamplingRepeatedCV}
\title{Repeated Cross Validation Resampling}
\format{\code{\link[R6:R6Class]{R6::R6Class()}} inheriting from \link{Resampling}.}
\usage{
ResamplingRepeatedCV
}
\description{
\code{repeats} times repeated \code{folds}-fold cross validation.
}
\examples{
# Create a task with 10 observations
task = mlr_tasks$get("iris")
task$filter(1:10)

# Instantiate Resampling
rrcv = mlr_resamplings$get("repeated_cv")
rrcv$param_vals = list(repeats = 2, folds = 3)
rrcv$instantiate(task)
rrcv$iters

# Individual sets:
rrcv$train_set(1)
rrcv$test_set(1)
intersect(rrcv$train_set(1), rrcv$test_set(1))

# Internal storage:
rrcv$instance # table
}
\keyword{datasets}