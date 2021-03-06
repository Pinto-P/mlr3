train_worker = function(e, ctrl) {
  # This wrapper calls learner$train, and additionally performs some basic
  # checks that the training was successful.
  # Exceptions here are possibly encapsulated, so that they get captured
  # and turned into log messages.
  wrapper = function(learner, task) {
    result = learner$train(task)

    if (is.null(result))
     stopf("Learner '%s' returned NULL during train", learner$id)

    if (!inherits(result, "Learner"))
      stopf("Learner '%s' returned '%s' during train(), but needs to return a Learner", learner$id, as_short_string(result))

    if (is.null(result$model))
      stopf("Learner '%s' did not store a model during train", learner$id)

    result
  }

  data = e$data

  # we are going to change learner$model, so make sure we clone it first
  learner = data$learner$clone(deep = TRUE)

  # subset task
  task = data$task$clone(deep = TRUE)$filter(e$train_set)

  log_debug("train_worker: Learner '%s', task '%s' [%ix%i]", learner$id, task$id, task$nrow, task$ncol, namespace = "mlr3")

  # call wrapper with encapsulation
  enc = encapsulate(ctrl$encapsulate_train)
  res = set_names(enc(wrapper, list(learner = learner, task = task), learner$packages, seed = e$seeds[["train"]]),
    c("learner", "train_log", "train_time"))

  # Raise the exception if we have no encapsulation enabled
  # Restore the learner to the untrained learner otherwise
  if (!is.null(res$train_log)) {
    errors = res$train_log[get("class") == "error", get("msg")]
    if (length(errors) > 0L) {
      if (ctrl$encapsulate_train == "none")
        stopf(paste(errors, sep = "\n"))
      res$learner = data$learner$clone(deep = TRUE)
    }
  }

  # if there is a fallback learner defined, also fit fallback learner
  fb = learner$fallback
  if (!is.null(fb)) {
    log_debug("train_worker: Training fallback learner '%s' on task '%s'", fb$id, task$id, namespace = "mlr3")
    require_namespaces(fb$packages, sprintf("The following packages are required for fallback learner %s: %%s", fb$id))

    ok = try(fb$train(task))
    if (inherits(ok, "try-error"))
      stopf("Fallback learner '%s' failed during train() with error: %s", fb$id, as.character(ok))
    if (!inherits(ok, "Learner"))
      stopf("Fallback-Learner '%s' returned '%s' during train(), but needs to return a Learner",
        fb$id, as_short_string(res))
    if (is.null(ok$model))
      stopf("Fallback learner '%s' did not store a model during train", fb$id)

    res$learner$fallback = ok
  }

  # result is list(learner, train_log, train_time)
  return(res)
}


predict_worker = function(e, ctrl) {
  # This wrapper calls learner$predict, and additionally performs some basic
  # checks that the prediction was successful.
  # Exceptions here are possibly encapsulated, so that they get captured
  # and turned into log messages.
  wrapper = function(learner, task) {
    if (is.null(learner$model))
      stopf("No model available")

    result = learner$predict(task)

    if (is.null(result))
      stopf("Learner '%s' returned NULL during predict()", learner$id)

    if (!inherits(result, "Prediction"))
      stopf("Learner '%s' returned '%s' during predict(), but needs to return a Prediction", learner$id, as_short_string(result))

    result
  }

  data = e$data
  task = data$task$clone(deep = TRUE)$filter(e$test_set)
  learner = data$learner
  if (is.null(learner$model))
    learner = learner$fallback

  # call predict with encapsulation
  enc = encapsulate(ctrl$encapsulate_predict)
  res = set_names(enc(wrapper, list(learner = learner, task = task), learner$packages, seed = e$seeds[["predict"]]),
    c("prediction", "predict_log", "predict_time"))

  if (!is.null(res$predict_log) && res$predict_log[get("class") == "error", .N] > 0L) {
    fb = learner$fallback
    if (!is.null(fb)) {
      log_debug("predict_worker: Predicting fallback learner '%s' on task '%s'", fb$id, task$id, namespace = "mlr3")
      require_namespaces(fb$packages, sprintf("The following packages are required for fallback learner %s: %%s", fb$id))

      ok = try(fb$predict(task))
      if (inherits(ok, "try-error"))
        stopf("Fallback learner '%s' failed during predict() with error: %s", fb$id, as.character(ok))
      if (!inherits(ok, "Prediction"))
        stopf("Fallback-Learner '%s' returned '%s' during predict(), but needs to return a Prediction",
          fb$id, as_short_string(res))

      res$prediction = ok
    }
  }

  # result is list(prediction, predict_log, predict_time)
  return(res)
}


score_worker = function(e, ctrl) {
  data = e$data
  measures = data$measures
  pkgs = unique(unlist(map(measures, "packages")))

  log_debug("score_worker: Learner '%s' on task '%s' [%ix%i]", data$learner$id, data$task$id, data$task$nrow, data$task$ncol, namespace = "mlr3")

  # call m$score with local encapsulation
  score = function() { set_names(lapply(measures, function(m) m$calculate(experiment = e)), ids(measures)) }
  enc = encapsulate("none")
  res = enc(score, list(), pkgs, seed = e$seeds[["score"]])

  return(list(performance = res$result, score_time = res$elapsed))
}


experiment_worker = function(iteration, task, learner, resampling, measures, ctrl, remote = FALSE) {
  if (remote) {
    # restore the state of the master session
    # currently, this only affects logging as we do not use any global options
    logger::log_threshold(ctrl$log_threshold, namespace = "mlr3")
  }

  # Create a new experiment
  # Results will be inserted into e$data in a piecemeal fashion
  e = as_experiment(task = task, learner = learner, resampling = resampling, iteration = iteration, measures = measures)

  log_info("Running learner '%s' on task '%s' (iteration %i/%i)'", learner$id, task$id, iteration, resampling$iters, namespace = "mlr3")

  tmp = train_worker(e, ctrl)
  e$data = insert_named(e$data, tmp)

  tmp = predict_worker(e, ctrl)
  e$data = insert_named(e$data, tmp)

  tmp = score_worker(e, ctrl)
  e$data = insert_named(e$data, tmp)

  if (!ctrl$store_prediction)
    e$data["prediction"] = list(NULL)

  if (!ctrl$store_model) {
    e$data$learner$model = NULL
  }

  # Remove slots which are already known by the calling function and return data slot
  remove_named(e$data, c("task", "resampling", "measures"))
}
