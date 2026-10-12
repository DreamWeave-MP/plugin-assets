--!strict
--!native
-- SPDX-License-Identifier: MIT OR Apache-2.0

--[[
The files a load order's plugins refer to, looked up the way OpenMW looks them up, with every
model they lead to run through the NIF check: what `jess.plugin.assets` reported over a load
order, a port of jess-assets' plugin report.

`check` takes the load order's content files in load order, already read (a plugin `@load-order`
opened, an `.omwscripts` file's text, or why a file couldn't be read), and the VFS to look their
files up in, normally the load order's own (an `@openmw` Context's `vfs()`). A record a later
plugin overrides counts only in the later one, unless `winningOnly` is turned off for plugins
that are no load order: ones named on their own, each checked for everything it refers to. It
reports, per reference, what is missing or read wrong, and per model, what `@nif-assets` finds in
it, in the shapes jess's reports had: camelCase fields and codes.

Lookups follow `components/misc/resourcehelpers.cpp`: models are used as written under `meshes`,
icons, textures, and book images are searched for and prefer `.dds`, sounds fall back to `.mp3`.
The models are read through the VFS, and `usedFiles` says where each file is on disk, so a check
needs the `filesystem.read` capability.
]]

local bytes = require '@dream/bytes'
local data = require '@dream/data'
local fs = require '@dream/fs'
local nifAssets = require '@nif-assets'
local paths = require '@self/internal/paths'
local references = require '@self/internal/references'
local tes3 = require '@tes3'
local vfs = require '@vfs'

--- How much a finding matters, most severe first: OpenMW refuses the file; it loads, but
--- something is dropped or read differently than written; a file it refers to is missing;
--- collision differs from what a model seems to ask for; it costs time or memory for nothing
--- seen; or it's worth knowing but not a problem.
export type Severity = 'wontLoad' | 'broken' | 'missingAsset' | 'collision' | 'performance' | 'info'

export type Kind = references.Kind

--- A content file to check, by the name the load order gives it, as one of: a plugin that
--- opened (what `@load-order`'s `open` lists as `plugins`), the text of an `.omwscripts` file,
--- or why the file couldn't be read (what it lists as `failures`).
export type Input = {
  name: string,
  plugin: tes3.Plugin?,
  scripts: string?,
  problem: string?,
}

export type Options = {
  --- Whether the models the references lead to are run through the NIF check; true by default.
  meshes: boolean?,
  --- `false` leaves `references` and `usedFiles` empty, for a check that only wants the
  --- findings; the summary still counts them.
  references: boolean?,
  --- Leave out findings, and models' findings, less severe than this, and models left without
  --- any. The summary still counts everything.
  show: Severity?,
  --- Every finding and every model, whatever `show` says.
  verbose: boolean?,
  --- `false` counts every input's records, where a load order counts a record only in the last
  --- input to name a file in it: for plugins named on their own rather than read as a load
  --- order, as `jess plugin assets` read the ones it was given.
  winningOnly: boolean?,
}

--- A problem with a reference, or with a record's text.
export type Finding = {
  severity: Severity,
  code: string,
  message: string,
  --- The plugin, by name.
  plugin: string,
  --- The record's type, as its tag; `omwscripts` for a line of a script list, and empty for a
  --- plugin that couldn't be read.
  recordType: string,
  id: string,
  --- The path as the record spells it; empty for problems with the record itself.
  path: string,
}

--- A reference to a file, and where OpenMW finds it.
export type ResolvedReference = {
  plugin: string,
  recordType: string,
  id: string,
  kind: Kind,
  --- The path as the record spells it.
  path: string,
  --- The VFS path OpenMW loads; nil when it doesn't exist.
  resolved: string?,
  --- The loose file or archive it comes from.
  source: string?,
}

--- A model's NIF check, and `TYPE id` of each record using it.
export type MeshReport = nifAssets.FileReport & { usedBy: { string } }

--- A file the plugins load and where it is: the absolute path of the loose file, or of the
--- archive holding it, and its VFS path.
export type UsedFile = { file: string, path: string, inArchive: boolean }

export type Summary = {
  --- The content files checked, by name, unreadable ones included.
  plugins: { string },
  unreadablePlugins: number,
  --- References to files, counted whether or not they are listed.
  references: number,
  --- Distinct files referred to.
  files: number,
  --- Referred-to files that don't exist.
  missing: number,
  meshesChecked: number,
  --- Models OpenMW won't load.
  meshesWontLoad: number,
  --- Reference findings by code.
  byCode: { [string]: number },
  --- Models by the code of their findings.
  meshesByCode: { [string]: number },
}

export type Report = {
  --- Totals across every reference and model, whatever the report shows.
  summary: Summary,
  --- Problems with references, most severe first.
  findings: { Finding },
  --- Every reference and where it resolved.
  references: { ResolvedReference },
  --- The NIF check of every model the references lead to, by path.
  meshes: { MeshReport },
  --- Every file the plugins load, with the models' textures, sorted by where it is on disk.
  usedFiles: { UsedFile },
}

local Severities: { Severity } =
  table.freeze { 'wontLoad', 'broken', 'missingAsset', 'collision', 'performance', 'info' }

local SeverityRank: { [string]: number } = {}
for rank, severity in Severities do
  SeverityRank[severity] = rank
end

local OptionKeys: { [string]: boolean } =
  { meshes = true, references = true, show = true, verbose = true, winningOnly = true }

--- Record types whose models never collide as the NIF says: actors and their body parts
--- collide by their bounding box.
local Actors: { string } = table.freeze { 'CREA ', 'NPC_ ', 'BODY ' }

type Reference = references.Reference

--- A reference finding before it is told whose it is.
type Found = { severity: Severity, code: string, message: string }

--- Where one reference leads: the VFS path OpenMW loads, the NIF and KF files it loads for it,
--- and what is wrong with it.
type Resolution = { resolved: string?, models: { string }, findings: { Found } }

--- Where a reference led, kept for the next one that names the same file the same way: what the
--- summary counts the file by (its kind and normalized path), the loose file or archive what it
--- resolved to comes from, when the report lists references, and what the lookup read of the
--- reference beside its kind and path.
type Lead = {
  resolution: Resolution,
  file: string,
  source: string?,
  distant: string?,
  width: number?,
  height: number?,
}

--- What follows a distant model's name for each level of detail it can have: `_0.nif` to
--- `_15.nif`.
local DetailLevels: { string } = table.freeze([for level in range(0, 15) => `_{level}.nif`])

--- `correctMeshPath`, and `correctActorModelPath` for classes OpenMW animates.
local function resolveModel(reference: Reference, exists: (string) -> boolean, resolution: Resolution)
  local written = reference.path
  local models, findings = resolution.models, resolution.findings

  -- Bethesda's placeholder for items that never appear in the world.
  if string.lower(references.trim(written)) == 'add world art' then
    table.insert(findings, {
      severity = 'info',
      code = 'placeholderModel',
      message = 'the model is the "Add World Art" placeholder, so dropping this item shows the error marker',
    })
    return
  end

  -- Always under meshes, so a path that already starts there doubles it.
  local mesh = paths.meshPath(written)
  local found = exists(mesh)
  if found then
    table.insert(models, mesh)
    resolution.resolved = mesh
  elseif string.sub(mesh, 1, 14) == 'meshes/meshes/' and exists(string.sub(mesh, 8)) then
    table.insert(findings, {
      severity = 'broken',
      code = 'doubledMeshesPrefix',
      message = `model "{written}" starts with meshes\\, so OpenMW looks for {mesh}; drop the prefix`,
    })
  else
    table.insert(findings, {
      severity = 'missingAsset',
      code = 'missingMesh',
      message = `model "{written}" not found at {mesh}`,
    })
  end

  -- getLODMeshName: paged objects load `<name><suffix>_<lod>` (lod 0-15) or `<name><suffix>` in
  -- the distance when they exist.
  local suffix = reference.distant
  if suffix and found and string.sub(mesh, -4) == '.nif' then
    local distant = string.sub(mesh, 1, -5) .. suffix
    for _, level in DetailLevels do
      local variant = distant .. level
      if exists(variant) then table.insert(models, variant) end
    end

    local plain = distant .. '.nif'
    if exists(plain) then table.insert(models, plain) end
  end

  if reference.kind ~= 'animatedMesh' then return end

  -- With x<name>.kf, OpenMW loads x<name>.nif without checking it exists.
  local animated, hasAnimation = paths.actorModelPath(mesh, exists)
  if not hasAnimation then return end

  local animation = if string.sub(animated, -4) == '.nif'
    then string.sub(animated, 1, -5) .. '.kf'
    else animated
  table.insert(models, animation)
  if exists(animated) then
    table.insert(models, animated)
    return
  end

  table.insert(findings, {
    severity = 'broken',
    code = 'missingAnimatedModel',
    message = `{animated} is missing, but OpenMW loads it for "{written}" because its .kf exists`,
  })
end

type Lookup = { resolved: paths.Resolved, code: string, what: string }

--- Where an icon, texture, sound, or book image is searched for, with the code and the word a
--- missing one is reported by.
local function lookUp(reference: Reference, exists: (string) -> boolean): Lookup
  local written, kind = reference.path, reference.kind
  if kind == 'icon' or kind == 'effectIcon' then
    return { resolved = paths.iconPath(written, exists), code = 'missingIcon', what = 'icon' }
  end

  if kind == 'texture' then
    return {
      resolved = nifAssets.texturePath(written, exists),
      code = 'missingTexture',
      what = 'texture',
    }
  end

  if kind == 'sound' then
    return { resolved = paths.soundPath(written, exists), code = 'missingSound', what = 'sound' }
  end

  if kind == 'voice' then
    return { resolved = paths.soundPath(written, exists), code = 'missingVoice', what = 'voice file' }
  end

  -- correctMusicPath and WindowManager::playVideo: under their folder, with no search.
  if kind == 'music' then
    return {
      resolved = paths.direct(`music/{written}`, exists),
      code = 'missingMusic',
      what = 'music',
    }
  end

  if kind == 'video' then
    return {
      resolved = paths.direct(`video/{written}`, exists),
      code = 'missingVideo',
      what = 'video',
    }
  end

  local resolved = if string.sub(written, 1, 6) == 'img://'
    then paths.direct(string.sub(written, 7), exists)
    else paths.sizedBookartPath(written, reference.width or 0, reference.height or 0, exists)
  return { resolved = resolved, code = 'missingBookArt', what = 'book image' }
end

--- Icons, textures, sounds, and book images, which OpenMW searches for.
local function resolveFile(reference: Reference, exists: (string) -> boolean, resolution: Resolution)
  local written, findings = reference.path, resolution.findings
  local lookup = lookUp(reference, exists)
  local resolved = lookup.resolved
  if reference.kind == 'effectIcon' then
    local big = paths.bigIconPath(written, exists)
    if not big.found then
      table.insert(findings, {
        severity = 'missingAsset',
        code = 'missingBigIcon',
        message = `large icon for "{written}" not found (tried {table.concat(big.tried, ', ')})`,
      })
    end
  end

  if not resolved.found then
    table.insert(findings, {
      severity = 'missingAsset',
      code = lookup.code,
      message = `{lookup.what} "{written}" not found (tried {table.concat(resolved.tried, ', ')})`,
    })
    return
  end

  resolution.resolved = resolved.path
  if reference.kind ~= 'texture' or string.match(resolved.path, '%.([^./]*)$') == 'dds' then return end

  table.insert(findings, {
    severity = 'performance',
    code = 'uncompressedTexture',
    message = `"{resolved.path}" isn't a DDS file, so it loads uncompressed and has its mipmaps built at load time`,
  })
end

local function resolve(reference: Reference, exists: (string) -> boolean): Resolution
  local resolution: Resolution = { models = {}, findings = {} }
  local kind = reference.kind
  if kind == 'mesh' or kind == 'animatedMesh' then
    resolveModel(reference, exists, resolution)
  elseif kind ~= 'script' then
    resolveFile(reference, exists, resolution)
  else
    local path = nifAssets.normalize(reference.path)
    if exists(path) then
      resolution.resolved = path
    else
      table.insert(resolution.findings, {
        severity = 'missingAsset',
        code = 'missingScript',
        message = `script "{reference.path}" not found`,
      })
    end
  end

  local models = {}
  for _, model in resolution.models do
    if nifAssets.isNifPath(model) then table.insert(models, model) end
  end

  resolution.models = models
  return resolution
end

--- What every input refers to: its references and problems, the statics every plugin's magic
--- effects use as visuals, and the inputs that couldn't be read. With `winningOnly`, a record a
--- later input overrides counts only in the later one, as in a load order.
local function collect(inputs: { Input }, winningOnly: boolean): (references.Found, { Input })
  local collected: { references.Found } = {}
  local unreadable: { Input } = {}
  for _, input in inputs do
    if input.plugin then
      table.insert(collected, references.ofPlugin(input.plugin, input.name))
    elseif input.scripts then
      table.insert(collected, references.ofScriptList(input.scripts, input.name))
    elseif input.problem then
      table.insert(unreadable, input)
    else
      error(`plugin-assets: '{input.name}' has no plugin, scripts, or problem`, 0)
    end
  end

  -- The last input to name a file in a record, or to have a problem with one, is the record's.
  local winners: { [string]: number } = {}
  local function key(recordType: string, id: string): string
    return `{recordType}\0{string.lower(id)}`
  end

  for index, found in collected do
    for _, reference in found.references do
      winners[key(reference.recordType, reference.id)] = index
    end

    for _, problem in found.problems do
      winners[key(problem.recordType, problem.id)] = index
    end
  end

  -- Records without an id all apply rather than override each other.
  local function wins(index: number, recordType: string, id: string): boolean
    return not winningOnly or id == '' or winners[key(recordType, id)] == index
  end

  local merged: references.Found = { references = {}, problems = {}, effectVisuals = {} }
  for index, found in collected do
    for _, reference in found.references do
      if wins(index, reference.recordType, reference.id) then
        table.insert(merged.references, reference)
      end
    end

    for _, problem in found.problems do
      if wins(index, problem.recordType, problem.id) then table.insert(merged.problems, problem) end
    end

    table.move(found.effectVisuals, 1, #found.effectVisuals, #merged.effectVisuals + 1, merged.effectVisuals)
  end

  return merged, unreadable
end

--- Findings most severe first, the ones of a severity in the order they were found.
local function bySeverity(findings: { Finding }): { Finding }
  local count = #findings
  local ranks, order = buffer.create(count), buffer.create(count * 4)
  into(ranks, 'u8')[for finding in findings => SeverityRank[finding.severity]]

  -- The sort is stable: findings of one rank keep the places they had.
  data.argsort(ranks, 'u8', 0, count, order)
  return [for position in order[1:count, 'u32'] => findings[position + 1]]
end

--- Runs the NIF check on every model in `users`, keeping the collision findings that matter for
--- how each model is used.
local function checkMeshes(
  report: Report,
  models: { string },
  users: { [string]: { string } },
  effectVisuals: { [string]: boolean },
  lookup: vfs.VFS
)
  local sources = nifAssets.new(lookup)
  for _, model in models do
    nifAssets.addVfsTarget(sources, model)
  end

  local checked = nifAssets.check(sources)
  local summary = report.summary
  summary.meshesChecked = checked.summary.files
  summary.meshesWontLoad = checked.summary.wontLoad

  for _, file in checked.files do
    local usedBy = table.clone(users[file.path] or {})

    -- Actors and their body parts collide by their bounding box, and magic effect visuals don't
    -- collide at all.
    local neverCollides = #usedBy > 0
    for _, user in usedBy do
      local visual = string.sub(user, 1, 5) == 'STAT ' and effectVisuals[string.lower(string.sub(user, 6))]
      if not visual and not table.find(Actors, string.sub(user, 1, 5)) then
        neverCollides = false
        break
      end
    end

    if neverCollides then
      local kept = {}
      for _, finding in file.findings do
        if finding.severity ~= 'collision' and finding.code ~= 'renderGeometryCollision' then
          table.insert(kept, finding)
        end
      end

      file.findings = kept
      file.worst = if kept[1] then kept[1].severity else nil
    end

    table.insert(report.meshes, {
      path = file.path,
      source = file.source,
      version = file.version,
      game = file.game,
      deeplyChecked = file.deeplyChecked,
      worst = file.worst,
      findings = file.findings,
      textures = file.textures,
      stats = file.stats,
      usedBy = usedBy,
    })

    local codes: { [string]: boolean } = {}
    for _, finding in file.findings do
      codes[finding.code] = true
    end

    for code in codes do
      summary.meshesByCode[code] = (summary.meshesByCode[code] or 0) + 1
    end
  end
end

--- Every file the references, models, and model textures resolve to, and where it is: sorted by
--- where, as paths sort, component by component, so that a folder's files come before those of a
--- folder whose name only starts the same; then by VFS path.
local function usedFiles(used: { [string]: boolean }, lookup: vfs.VFS): { UsedFile }
  -- A place on disk goes by its path with the separators made NUL, the least byte and one no
  -- path holds: those keys sort as bytes into the order the paths have by their components.
  local keys: { [string]: string }, places: { [string]: string } = {}, {}
  local pathsAt: { [string]: { string } }, order: { string } = {}, {}
  local archived: { [string]: boolean } = {}
  for path in used do
    local file = lookup:getFile(path)
    if not file then continue end

    local archive = file:parentArchivePath()
    local onDisk = archive or file:path()
    local key = keys[onDisk]
    if not key then
      local place = fs.canonicalize(onDisk) or onDisk
      key = bytes.translate(place, '/', '\0')
      keys[onDisk] = key

      -- Two paths can be one place, by a link.
      if not pathsAt[key] then
        places[key] = place
        pathsAt[key] = {}
        table.insert(order, key)
      end
    end

    archived[path] = archive ~= nil
    table.insert(pathsAt[key], path)
  end

  table.sort(order)
  for _, paths in pathsAt do
    table.sort(paths)
  end

  return [
    for key in order
    for path in pathsAt[key]
    => { file = places[key], path = path, inArchive = archived[path] }
  ]
end

--- The report with findings, and models' findings, less severe than `show` left out, and models
--- left without any, unless `everyModel`. References, used files, and the summary stay whole.
local function shown(report: Report, show: Severity, everyModel: boolean): Report
  local limit = SeverityRank[show]
  local findings = {}
  for _, finding in report.findings do
    if SeverityRank[finding.severity] <= limit then table.insert(findings, finding) end
  end

  local meshes: { MeshReport } = {}
  for _, mesh in report.meshes do
    local kept = {}
    for _, finding in mesh.findings do
      -- A severity the NIF check has and this doesn't know is always shown.
      if (SeverityRank[finding.severity] or 0) <= limit then table.insert(kept, finding) end
    end

    if not everyModel and #kept == 0 then continue end

    local copy = table.clone(mesh)
    copy.findings = kept
    table.insert(meshes, copy)
  end

  return {
    summary = report.summary,
    findings = findings,
    references = report.references,
    meshes = meshes,
    usedFiles = report.usedFiles,
  }
end

--- Checks the files `inputs` refer to, looked up in `lookup`: a load order's content files, in
--- load order, and its VFS.
local function check(inputs: { Input }, lookup: vfs.VFS, options: Options?): Report
  local given: Options = options or {}
  for option in (given :: unknown) :: { [string]: unknown } do
    if OptionKeys[option] then continue end

    error(
      `plugin-assets: unknown option '{option}': expected meshes, references, show, verbose, or winningOnly`,
      0
    )
  end

  local show = given.show
  if show and not SeverityRank[show] then
    error(`unknown severity '{show}': expected {table.concat(Severities, ', ', 1, 5)}, or info`, 0)
  end

  -- Only `false` turns either off: nil is the default, which is on.
  local keepReferences, wantMeshes = given.references ~= false, given.meshes ~= false
  local found, unreadable = collect(inputs, given.winningOnly ~= false)
  local summary: Summary = {
    plugins = {},
    unreadablePlugins = #unreadable,
    references = #found.references,
    files = 0,
    missing = 0,
    meshesChecked = 0,
    meshesWontLoad = 0,
    byCode = {},
    meshesByCode = {},
  }

  local report: Report =
    { summary = summary, findings = {}, references = {}, meshes = {}, usedFiles = {} }
  for _, input in inputs do
    table.insert(summary.plugins, input.name)
  end

  for _, input in unreadable do
    table.insert(report.findings, {
      severity = 'wontLoad',
      code = 'unreadablePlugin',
      message = input.problem :: string,
      plugin = input.name,
      recordType = '',
      id = '',
      path = '',
    })
  end

  for _, problem in found.problems do
    table.insert(report.findings, {
      severity = 'broken',
      code = problem.code,
      message = problem.message,
      plugin = problem.plugin,
      recordType = problem.recordType,
      id = problem.id,
      path = '',
    })
  end

  local function exists(path: string): boolean return lookup:contains(path) end

  local sources = nifAssets.new(lookup)
  local files: { [string]: boolean }, missing: { [string]: boolean } = {}, {}
  local users: { [string]: { string } }, models: { string } = {}, {}
  local used: { [string]: boolean }, leads: { [string]: { [string]: Lead } } = {}, {}
  for _, reference in found.references do
    local {plugin, recordType, id, kind, path, distant, width, height} = reference
    local byPath = leads[kind]
    if not byPath then
      byPath = {}
      leads[kind] = byPath
    end

    -- A load order names most of its files more than once, and a lookup that reads the same of
    -- a reference finds the same.
    local lead = byPath[path]
    if not lead or lead.distant ~= distant or lead.width ~= width or lead.height ~= height then
      local fresh = resolve(reference, exists)
      local resolved = fresh.resolved
      lead = {
        resolution = fresh,
        file = `{kind}\0{nifAssets.normalize(path)}`,
        source = if resolved and keepReferences then nifAssets.sourceOf(sources, resolved) else nil,
        distant = distant,
        width = width,
        height = height,
      }
      byPath[path] = lead
    end

    local {resolution, file} = lead
    if not files[file] then
      files[file] = true
      summary.files += 1
    end

    -- `TYPE id` of each record using each model, in reference order without repeats.
    local user = if resolution.models[1] then `{recordType} {id}` else ''
    for _, model in resolution.models do
      local modelUsers = users[model]
      if not modelUsers then
        modelUsers = {}
        users[model] = modelUsers
        table.insert(models, model)
      end

      if not table.find(modelUsers, user) then table.insert(modelUsers, user) end
    end

    for _, finding in resolution.findings do
      if finding.severity == 'missingAsset' and not missing[file] then
        missing[file] = true
        summary.missing += 1
      end

      table.insert(report.findings, {
        severity = finding.severity,
        code = finding.code,
        message = finding.message,
        plugin = plugin,
        recordType = recordType,
        id = id,
        path = path,
      })
    end

    if not keepReferences then continue end

    local resolved = resolution.resolved
    if resolved then used[resolved] = true end

    table.insert(report.references, {
      plugin = plugin,
      recordType = recordType,
      id = id,
      kind = kind,
      path = path,
      resolved = resolved,
      source = lead.source,
    })
  end

  for _, finding in report.findings do
    summary.byCode[finding.code] = (summary.byCode[finding.code] or 0) + 1
  end

  report.findings = bySeverity(report.findings)
  table.sort(models)

  if wantMeshes then
    local effectVisuals: { [string]: boolean } = {}
    for _, visual in found.effectVisuals do
      effectVisuals[visual] = true
    end

    checkMeshes(report, models, users, effectVisuals, lookup)
  end

  if keepReferences then
    for _, model in models do
      used[model] = true
    end

    for _, mesh in report.meshes do
      for _, texture in mesh.textures do
        if texture.resolved then used[texture.resolved] = true end
      end
    end

    report.usedFiles = usedFiles(used, lookup)
  end

  if given.verbose then return shown(report, 'info', true) end
  if show then return shown(report, show, false) end

  return report
end

return table.freeze {
  --- Record types with fields that name files: what a plugin has to be opened with for `check`
  --- to read it, as `@load-order`'s `types`. The TES3 header is always kept.
  recordTypes = references.assetTags,
  check = check,
}
