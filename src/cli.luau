--!strict
--!native
-- SPDX-License-Identifier: MIT OR Apache-2.0

--[[
@plugin-assets/cli: the command line `jess plugin assets` had, over @plugin-assets/commands.

  parse(argv) -> (command, nil) | (nil, message)
  render(result, options) -> the report as text
  diagnostics(result, options) -> what goes to standard error beside it
  status(result) -> exit status
  run(argv) -> exit status

  plugin-assets [OPTIONS] <PLUGIN>...

The arguments and flags are `jess plugin assets`', with `--format`, which was jess's own and went
before the command or after it: here it is one more flag. A flag's value follows it or is attached
with `=`; `--data` can be given more than once, the others once; `--` ends the flags.

`parse` reads an argument list into the request `commands.check` takes and how its result is to
be laid out, and touches no file. `--show` and `--verbose` are in both: in the request, where
`@plugin-assets` leaves out the findings and models they don't reach, and in the layout, which
decides the sections printed. A report without `--verbose` asks for no references, as the
original did, since it prints none.

`render` is the report as jess printed it: one YAML, JSON, or TOML document with serde's
snake_case fields and codes (`used_files`, `missing_asset`), where the result spells them
camelCase. `--show files` prints `used_files` alone; `references` and `used_files` are printed
only with `--verbose`, and `meshes` only when there are any. `diagnostics` is the original's
standard error: with `--show files` the missing files, which have no path to list, and last
`error: ...` counting what failed when something did. `status` is 1 for that outcome.

Exit statuses: 0 when nothing is missing and every model loads; 1 when a referenced file is
missing, a plugin can't be read, or a model won't load, after the report is printed; 8 when the
command line can't be used (an unknown or repeated flag, a missing or unknown value, no plugin);
9 when the check couldn't be made (a plugin or data path that isn't there, a data path that is no
folder or archive). The original exited 1 for all of these. Messages for 8 and 9 go to standard
error as `plugin-assets: <message>`.

`-V`/`--version` printed jess's version and is refused by name: `jess --version` prints it.
]]

local commands = require '@plugin-assets/commands'
local pluginAssets = require '@plugin-assets'
local process = require '@dream/process'
local serialize = require '@jess/data/value'

type Value = serialize.Value

export type Format = 'yaml' | 'json' | 'toml'

--- How a result is laid out.
export type Options = {
  --- YAML without one.
  format: Format?,
  --- Only the files the plugins load: `--show files`.
  files: boolean?,
  --- The references and the files used as well: `--verbose`.
  verbose: boolean?,
}

--- What an argument list asks for: a check, with the request `commands.check` takes and how its
--- result is laid out, or the usage.
export type Command = {
  command: 'check' | 'help',
  request: commands.CheckRequest?,
  options: Options?,
}

local Exit = table.freeze { ok = 0, failed = 1, invalidInput = 8, runtime = 9 }

local Usage = [[
plugin-assets: check every file plugins refer to (models, textures, sounds, ...) the way OpenMW
finds them, and run the NIF check on their models. This was `jess plugin assets`.

Usage: plugin-assets [OPTIONS] <PLUGIN>...

Arguments:
  <PLUGIN>...  Plugins to check, by path.

Options:
      --show <SHOW>          The least severe findings to include, or files for just the files
                             the plugins load, with their absolute paths [default: collision]
                             [possible values: wont-load, broken, missing-asset, collision,
                             performance, info, files]
  -v, --verbose              Include everything: all findings, every model, every reference, and
                             every file used.
      --no-meshes            Don't run the NIF check on the models the plugins use.
      --data <PATH>          A data folder or archive to look files up in. Can be repeated; later
                             ones win, and the plugins' own folders win over all of them.
      --encoding <ENCODING>  The code page the plugin's text is in: win1252 for English and
                             Western European releases, win1251 for Russian, win1250 for Central
                             European. By default, win1252. [possible values: win1250, win1251,
                             win1252]
      --format <FORMAT>      Output format: YAML (the default), compact one-line JSON, or TOML
                             [possible values: yaml, json, toml]
  -h, --help                 Print help

The plugins are checked as named, not as a load order: nothing reads an openmw.cfg, and only the
plugins' own folders and --data are searched. Not here: -V/--version, which printed jess's
version; jess --version prints it.

Exit status: 0 nothing is missing and every model loads; 1 a referenced file is missing, a plugin
can't be read, or a model won't load, after the report is printed; 8 the command line can't be
used; 9 the check couldn't be made.]]

--- `--show`'s values, and the severity each stands for; `files` stands for none.
local Shows: { [string]: pluginAssets.Severity | 'files' } = table.freeze {
  ['wont-load'] = 'wontLoad' :: 'wontLoad',
  broken = 'broken' :: 'broken',
  ['missing-asset'] = 'missingAsset' :: 'missingAsset',
  collision = 'collision' :: 'collision',
  performance = 'performance' :: 'performance',
  info = 'info' :: 'info',
  files = 'files' :: 'files',
}

--- The flags that take a value: what each one's value is, and the values it can be.
local Valued: { [string]: { what: string, values: { string }? } } = table.freeze {
  ['--show'] = {
    what = 'a severity, or files',
    values = { 'wont-load', 'broken', 'missing-asset', 'collision', 'performance', 'info', 'files' },
  },
  ['--data'] = { what = 'a path' },
  ['--encoding'] = { what = 'an encoding', values = { 'win1250', 'win1251', 'win1252' } },
  ['--format'] = { what = 'a format', values = { 'yaml', 'json', 'toml' } },
}

--- The flags that take none.
local Switches: { [string]: boolean } =
  table.freeze { ['--verbose'] = true, ['--no-meshes'] = true, ['--help'] = true, ['--version'] = true }

local Shorts: { [string]: string } =
  table.freeze { ['v'] = '--verbose', ['h'] = '--help', ['V'] = '--version' }

local function out(text: string) process.write('stdout', text) end

local function err(text: string) process.write('stderr', text) end

local function usage(message: string): number
  err(`plugin-assets: {message}\n`)
  return Exit.invalidInput
end

--- `values` as a sentence lists them: `a, b, or c`.
local function listed(values: { string }): string
  local count = #values
  return `{table.concat(values, ', ', 1, count - 1)}, or {values[count]}`
end

--- What the flags of an argument list set, before they become a request.
type Given = {
  show: string?,
  encoding: string?,
  format: string?,
  verbose: boolean?,
  noMeshes: boolean?,
  help: boolean?,
  data: { string },
  plugins: { string },
}

--- Sets what the switch `name` stands for, or says why the command line can't be used.
local function switch(given: Given, name: string, attached: string?): string?
  if attached then return `{name} takes no value, not '{attached}'` end

  if name == '--version' then
    return '--version isn\'t part of this command: it printed jess\'s version, which jess --version prints'
  end

  if name == '--help' then
    given.help = true
    return nil
  end

  local field = if name == '--verbose' then 'verbose' else 'noMeshes'
  local fields = (given :: unknown) :: { [string]: unknown }
  if fields[field] then return `{name} can only be given once` end

  fields[field] = true
  return nil
end

--- Sets the value of the flag `name`, or says why the command line can't be used.
local function assign(given: Given, name: string, value: string): string?
  if name == '--data' then
    table.insert(given.data, value)
    return nil
  end

  local allowed = Valued[name].values :: { string }
  if not table.find(allowed, value) then
    return `invalid value '{value}' for {name}: expected {listed(allowed)}`
  end

  local field = string.sub(name, 3)
  local fields = (given :: unknown) :: { [string]: unknown }
  if fields[field] then return `{name} can only be given once` end

  fields[field] = value
  return nil
end

--- The request and layout the flags given stand for.
local function command(given: Given): Command
  local show = Shows[given.show or 'collision']
  local files, verbose = show == 'files', given.verbose == true
  local request: commands.CheckRequest = { plugins = given.plugins }
  if #given.data > 0 then request.data = given.data end
  if given.encoding then request.encoding = given.encoding :: commands.Encoding end
  if given.noMeshes then request.meshes = false end
  if show ~= 'files' then request.show = show end
  if verbose then request.verbose = true end

  -- Only a verbose report shows the references, and only it and the file list the files used.
  if not files and not verbose then request.references = false end

  local options: Options = {}
  if given.format then options.format = given.format :: Format end
  if files then options.files = true end
  if verbose then options.verbose = true end

  return { command = 'check' :: 'check', request = request, options = options }
end

local function parse(argv: { string }): (Command?, string?)
  local given: Given = { data = {}, plugins = {} }
  local index = 1

  while index <= #argv do
    local argument = argv[index]
    index += 1

    if argument == '--' then
      table.move(argv, index, #argv, #given.plugins + 1, given.plugins)
      break
    end

    if string.sub(argument, 1, 1) ~= '-' or argument == '-' then
      table.insert(given.plugins, argument)
      continue
    end

    if string.sub(argument, 1, 2) ~= '--' then
      -- Short flags take no value, and can share a dash.
      for position = 2, #argument do
        local name = Shorts[string.sub(argument, position, position)]
        if not name then return nil, `unknown option '{argument}'` end

        local problem = switch(given, name, nil)
        if problem then return nil, problem end

        if given.help then return { command = 'help' :: 'help' }, nil end
      end

      continue
    end

    local flag, attached = string.match(argument, '^(%-%-[^=]+)=(.*)$')
    local name: string = flag or argument

    if Switches[name] then
      local problem = switch(given, name, attached)
      if problem then return nil, problem end

      if given.help then return { command = 'help' :: 'help' }, nil end

      continue
    end

    local valued = Valued[name]
    if not valued then return nil, `unknown option '{argument}'` end

    local value: string? = attached
    if not value then
      local following = argv[index]
      -- An argument that starts with a dash is a flag, not a value; one can be attached with `=`.
      if following and (string.sub(following, 1, 1) ~= '-' or following == '-') then
        value = following
        index += 1
      end
    end

    if not value then return nil, `{name} requires {valued.what}` end

    local problem = assign(given, name, value)
    if problem then return nil, problem end
  end

  if #given.plugins == 0 then return nil, 'at least one plugin is required' end

  return command(given), nil
end

--- The names spelled so far: a report has a few dozen severities, codes, and kinds between them,
--- and each is on many of its rows.
local Snakes: { [string]: string } = {}

--- A camelCase field or code as serde spelled it in jess's output: `missingAsset` is
--- `missing_asset`.
local function snake(name: string): string
  local spelled = Snakes[name]
  if spelled then return spelled end

  spelled = string.gsub(name, '%u', function(letter: string): string return `_{string.lower(letter)}` end)
  Snakes[name] = spelled
  return spelled
end

--- Counts by code, the codes in snake_case and in order, as a `BTreeMap` serializes.
local function counts(byCode: { [string]: number }): Value
  local codes: { string } = {}
  local bySnake: { [string]: number } = {}
  for code, count in byCode do
    local spelled = snake(code)
    table.insert(codes, spelled)
    bySnake[spelled] = count
  end

  table.sort(codes)

  local map = serialize.map()
  for _, code in codes do
    serialize.set(map, code, bySnake[code])
  end

  return map
end

local function list<T>(rows: { T }, each: (T) -> Value): Value
  local items = table.create(#rows) :: { Value }
  for index, row in rows do
    items[index] = each(row)
  end

  return serialize.array(items)
end

local function text(value: string): Value return value end

local function summaryValue(summary: pluginAssets.Summary): Value
  return serialize.struct {
    { 'plugins', list(summary.plugins, text) },
    { 'unreadable_plugins', summary.unreadablePlugins },
    { 'references', summary.references },
    { 'files', summary.files },
    { 'missing', summary.missing },
    { 'meshes_checked', summary.meshesChecked },
    { 'meshes_wont_load', summary.meshesWontLoad },
    { 'by_code', counts(summary.byCode) },
    { 'meshes_by_code', counts(summary.meshesByCode) },
  }
end

local function findingValue(finding: pluginAssets.Finding): Value
  return serialize.struct {
    { 'severity', snake(finding.severity) },
    { 'code', snake(finding.code) },
    { 'message', finding.message },
    { 'plugin', finding.plugin },
    { 'record_type', finding.recordType },
    { 'id', finding.id },
    { 'path', finding.path },
  }
end

local function referenceValue(reference: pluginAssets.ResolvedReference): Value
  return serialize.struct {
    { 'plugin', reference.plugin },
    { 'record_type', reference.recordType },
    { 'id', reference.id },
    { 'kind', snake(reference.kind) },
    { 'path', reference.path },
    { 'resolved', reference.resolved },
    { 'source', reference.source },
  }
end

local function meshValue(mesh: pluginAssets.MeshReport): Value
  local stats = mesh.stats
  return serialize.struct {
    { 'path', mesh.path },
    { 'source', mesh.source },
    { 'version', mesh.version },
    { 'game', mesh.game },
    { 'deeply_checked', mesh.deeplyChecked },
    { 'worst', if mesh.worst then snake(mesh.worst) else nil },
    {
      'findings',
      list(mesh.findings, function(finding): Value
        return serialize.struct {
          { 'severity', snake(finding.severity) },
          { 'code', snake(finding.code) },
          { 'message', finding.message },
          { 'record', finding.record },
        }
      end),
    },
    {
      'textures',
      list(mesh.textures, function(texture): Value
        return serialize.struct {
          { 'path', texture.path },
          { 'resolved', texture.resolved },
          { 'source', texture.source },
        }
      end),
    },
    {
      'stats',
      if stats
        then serialize.struct {
          { 'records', stats.records },
          { 'reachable_records', stats.reachableRecords },
          { 'nodes', stats.nodes },
          { 'shapes', stats.shapes },
          { 'vertices', stats.vertices },
          { 'triangles', stats.triangles },
          { 'collision_triangles', stats.collisionTriangles },
          { 'controllers', stats.controllers },
          { 'embedded_textures', stats.embeddedTextures },
          { 'embedded_texture_bytes', stats.embeddedTextureBytes },
          { 'skinned', stats.skinned },
        }
        else nil,
    },
    { 'used_by', list(mesh.usedBy, text) },
  }
end

local function usedFileValue(file: pluginAssets.UsedFile): Value
  return serialize.struct {
    { 'file', file.file },
    { 'path', file.path },
    { 'in_archive', file.inArchive },
  }
end

--- A report's sections in the order jess printed them: the summary and findings, the models when
--- there are any, and with `verbose` the references and the files used.
local function sections(report: pluginAssets.Report, verbose: boolean?): { { unknown } }
  local fields: { { unknown } } = {
    { 'summary', summaryValue(report.summary) },
    { 'findings', list(report.findings, findingValue) },
  }

  if #report.meshes > 0 then table.insert(fields, { 'meshes', list(report.meshes, meshValue) }) end

  if not verbose then return fields end

  table.insert(fields, { 'references', list(report.references, referenceValue) })
  table.insert(fields, { 'used_files', list(report.usedFiles, usedFileValue) })
  return fields
end

--- The result as the document jess printed: `used_files` alone for the file list, else the
--- report's sections.
local function render(result: commands.CheckResult, options: Options?): string
  local given: Options = options or {}
  local report = result.report
  local fields = if given.files
    then { { 'used_files', list(report.usedFiles, usedFileValue) } }
    else sections(report, given.verbose)
  local format: Format = given.format or 'yaml'
  local document = serialize.encode(serialize.struct(fields), format)

  -- YAML and TOML documents end their last line; compact JSON is one line that doesn't.
  return if format == 'json' then `{document}\n` else document
end

--- `count` followed by `one` or `many`, whichever agrees with it.
local function counted(count: number, one: string, many: string): string
  return `{count} {if count == 1 then one else many}`
end

--- What jess said on standard error beside the report: with the file list, each plugin that
--- couldn't be read and each missing file, which have no path to list; and last, when something
--- failed, how much. Empty when there is nothing to say.
local function diagnostics(result: commands.CheckResult, options: Options?): string
  local lines: { string } = {}
  if options and options.files then
    for _, finding in result.report.findings do
      if finding.code == 'unreadablePlugin' or finding.severity == 'missingAsset' then
        table.insert(lines, `{finding.plugin}: {finding.message}\n`)
      end
    end
  end

  local summary = result.report.summary
  local failures: { string } = {}
  if summary.unreadablePlugins > 0 then
    table.insert(
      failures,
      counted(summary.unreadablePlugins, 'plugin couldn\'t be read', 'plugins couldn\'t be read')
    )
  end

  if summary.missing > 0 then
    table.insert(
      failures,
      counted(summary.missing, 'referenced file is missing', 'referenced files are missing')
    )
  end

  if summary.meshesWontLoad > 0 then
    table.insert(failures, counted(summary.meshesWontLoad, 'model won\'t load', 'models won\'t load'))
  end

  if #failures > 0 then table.insert(lines, `error: {table.concat(failures, '; ')}\n`) end

  return table.concat(lines)
end

--- 1 when a referenced file is missing, a plugin couldn't be read, or a model won't load; else 0.
local function status(result: commands.CheckResult): number
  local summary = result.report.summary
  if summary.unreadablePlugins > 0 or summary.missing > 0 or summary.meshesWontLoad > 0 then
    return Exit.failed
  end

  return Exit.ok
end

--- What a raised error says: a refusal as it is worded, without the script position Luau puts in
--- front of one raised from inside a package, and anything else whole.
local function reason(problem: unknown): string
  local message = tostring(problem)
  local own = string.match(message, '^(plugin%-assets: .*)$')
    or string.match(message, '^.-:%d+: (plugin%-assets: .*)$')
  return own or `plugin-assets: {message}`
end

local function run(argv: { string }): number
  local parsed, message = parse(argv)

  if not parsed then return usage(message :: string) end

  if parsed.command == 'help' then
    out(`{Usage}\n`)
    return Exit.ok
  end

  -- `check` raises for a request it can't carry out: a plugin or data path that isn't there, a
  -- data path that is no folder or archive. So does reading a file in a runtime without the
  -- filesystem.read capability.
  local checked, result = pcall(commands.check, parsed.request :: commands.CheckRequest)
  if not checked then
    err(`{reason(result)}\n`)
    return Exit.runtime
  end

  out(render(result, parsed.options))

  local said = diagnostics(result, parsed.options)
  if said ~= '' then err(said) end

  return status(result)
end

return table.freeze {
  Exit = Exit,
  parse = parse,
  render = render,
  diagnostics = diagnostics,
  status = status,
  run = run,
}
