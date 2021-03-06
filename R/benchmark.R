#' @title Benchmark Multiple Learners on Multiple Tasks
#'
#' @description
#' Runs a benchmark of the cross-product of learners, tasks, and resampling strategies (possibly in parallel).
#'
#' Resamplings which are not already instantiated will be instantiated automatically.
#' Note that these auto-instantiated resamplings will not be synchronized per task, i.e. learners will
#' see different splits of the same task.
#'
#' To generate exhaustive designs and automatically instantiate resampling strategies per task, see [expand_grid()].
#'
#' @param design ([data.frame()]):
#'   Data frame (or [data.table()]) with three columns: "task", "learner", and "resampling".
#'   Each row defines a set of resampled experiments by providing a [Task], [Learner] and [Resampling] strategy.
#'   The helper function [expand_grid()] can assist in generating an exhaustive design (see examples).
#' @param ctrl (named `list` as returned by [mlr_control()]):
#'   Object to control experiment execution. See [mlr_control()].
#'
#' @return [BenchmarkResult].
#' @export
#' @examples
#' \dontshow{
#'    .threshold = logger::log_threshold(namespace = "mlr3")
#'    logger::log_threshold(logger::WARN, namespace = "mlr3")
#' }
#' tasks = mlr_tasks$mget(c("iris", "sonar"))
#' learners = mlr_learners$mget(c("classif.featureless", "classif.rpart"))
#' resamplings = mlr_resamplings$mget("holdout")
#'
#' design = expand_grid(tasks, learners, resamplings)
#' print(design)
#'
#' set.seed(123)
#' bmr = benchmark(design)
#'
#' # performance for all conducted experiments
#' head(as.data.table(bmr))
#'
#' # aggregated performance values
#' bmr$aggregated(objects = FALSE)
#'
#' # Overview of of resamplings that were conducted internally
#' rrs = bmr$resample_results
#' print(rrs)
#'
#' # Extract first ResampleResult
#' rr = bmr$resample_result(hash = rrs$hash[1])
#' print(rr)
#'
#' # Extract predictions of first experiment of this resampling
#' head(as.data.table(rr$experiment(1)$prediction))
#' \dontshow{
#'    logger::log_threshold(.threshold, namespace = "mlr3")
#' }
benchmark = function(design, ctrl = list()) {
  assert_data_frame(design, min.rows = 1L)
  assert_names(names(design), permutation.of = c("task", "learner", "resampling"))
  assert_list(design$task, "Task")
  assert_list(design$learner, "Learner")
  assert_list(design$resampling, "Resampling")
  design = as.data.table(design) # ensures that the table is copied
  ctrl = mlr_control(ctrl)

  # expand the design: add rows for each resampling iteration
  grid = pmap_dtr(design, function(task, learner, resampling) {
    instance = resampling$clone()
    if (!instance$is_instantiated)
      instance = instance$instantiate(task)
    hash = experiment_data_hash(list(task = task, learner = learner, resampling = resampling))
    data.table(task = list(task$clone(deep = TRUE)), learner = list(learner$clone(deep = TRUE)), resampling = list(instance), measures = list(task$measures),
      iter = seq_len(instance$iters), hash = hash)
  })

  log_info("Benchmarking %i experiments", nrow(grid), namespace = "mlr3")

  if (future_remote()) {
    log_debug("Running benchmark() via future", namespace = "mlr3")

    tmp = future.apply::future_mapply(experiment_worker,
      task = grid$task, learner = grid$learner, resampling = grid$resampling,
      iteration = grid$iter, measures = grid$measures,
      MoreArgs = list(ctrl = ctrl, remote = TRUE), SIMPLIFY = FALSE, USE.NAMES = FALSE,
      future.globals = FALSE, future.scheduling = structure(TRUE, ordering = "random"),
      future.packages = "mlr3"
    )
  } else {
    log_debug("Running benchmark() sequentially", namespace = "mlr3")
    tmp = mapply(experiment_worker,
      task = grid$task, learner = grid$learner, resampling = grid$resampling,
      iteration = grid$iter, measures = grid$measures,
      MoreArgs = list(ctrl = ctrl, remote = FALSE), SIMPLIFY = FALSE, USE.NAMES = FALSE
    )
  }

  remove_named(grid, c("iter", "learner"))
  grid = ref_cbind(grid, combine_experiments(tmp))

  log_info("Finished benchmark", namespace = "mlr3")
  BenchmarkResult$new(grid)
}

#' @title Generate a Benchmark Design
#'
#' @description
#' Takes a lists of [Task], a list of [Learner] and a list of [Resampling] to
#' generate a design in an [expand.grid()] fashion (a.k.a. cross join or Cartesian product).
#'
#' Resampling strategies must be uninstantiated, and will be instantiated per task.
#'
#' @param tasks (list of [Task]).
#'   Instead a [Task] object, it is also possible to provide a key to retrieve a task from the [mlr_tasks] dictionary.
#' @param learners (list of [Learner]).
#'   Instead if a [Learner] object, it is also possible to provide a key to retrieve a task from the [mlr_learners] dictionary.
#' @param resamplings (list of [Resampling]).
#'   Instead if a [Resampling] object, it is also possible to provide a key to retrieve a task from the [mlr_resamplings] dictionary.
#'
#' @return ([data.table()]) with the cross product of the input vectors.
#' @export
expand_grid = function(tasks, learners, resamplings) {
  tasks = get_tasks(tasks)
  learners = get_learners(learners)
  resamplings = get_resamplings(resamplings)
  map(resamplings, assert_resampling, instantiated = FALSE)

  grid = CJ(task = seq_along(tasks), resampling = seq_along(resamplings))
  instances = pmap(grid, function(task, resampling) resamplings[[resampling]]$clone()$instantiate(tasks[[task]]))
  grid$instance = seq_row(grid)
  grid = grid[CJ(task = seq_along(tasks), learner = seq_along(learners)), on = "task", allow.cartesian = TRUE]

  data.table(task = tasks[grid$task], learner = learners[grid$learner], resampling = instances[grid$instance])
}
