## Application service: validate, snapshot-before-write, merge with the
## latest registry state, then apply only the delta.

import nimi/core/environment

import ./[model, storage]

type
  ApplyResult* = object
    snapshot*: Snapshot
    notified*: bool
    upserts*: int
    deletions*: int

  Service* = ref object
    environment*: EnvironmentStore
    backups*: Store

proc newService*(environment: EnvironmentStore, backups: Store): Service =
  Service(environment: environment, backups: backups)

proc loadVariables*(service: Service, scope: Scope): seq[Variable] =
  toVariables(service.environment.list(scope))

proc snapshot*(service: Service, scope: Scope, note: string): Snapshot =
  let variables = service.loadVariables(scope)
  service.backups.saveSnapshot(scope, note, variables)

proc apply*(service: Service, scope: Scope, before, desired: seq[Variable],
            note: string, fullReplace = false): ApplyResult =
  let problem = validate(desired)
  if problem.len > 0:
    raise newException(EnvironmentError, problem)
  let latest = service.loadVariables(scope)
  result.snapshot = service.backups.saveSnapshot(scope, note, latest)
  let merged =
    if fullReplace: clone(desired)
    else: mergeChanges(latest, before, desired)
  var previous, entries: seq[EnvironmentEntry]
  for value in latest:
    previous.add EnvironmentEntry(name: value.name,
                                  data: toEnvironmentValue(value))
  for value in merged:
    entries.add EnvironmentEntry(name: value.name,
                                 data: toEnvironmentValue(value))
  let applied = service.environment.applyEnvironmentChanges(
    scope, previous, entries)
  result.notified = applied.notified
  result.upserts = applied.upserts
  result.deletions = applied.deletions
