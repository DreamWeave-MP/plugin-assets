--!strict
--!native
-- `@plugin-assets/cli`: the argument lists it reads into a request and a layout, the ones it
-- refuses and why; hand-built results as the text jess printed for them, the documentation's own
-- examples among them; the exit status of each outcome; and whole runs over the harness's
-- inputs. What a run prints goes to the suite's own standard output and standard error.
local cli = require '@plugin-assets/cli'
local commands = require '@plugin-assets/commands'
local fixture = require './fixture'
local json = require '@jess/json'
local pluginAssets = require '@plugin-assets'
local test = require '@jess/test'

local expect = test.expect
local suite = test.new()
local scratch = assert(rawget(_G, 'scratchRoot') :: string?, 'the suite needs a host-owned scratchRoot')

-- Each argument list `parse` refuses, and what it says of it.
local Refused: { { argv: { string }, message: string } } = {
  { argv = {}, message = 'at least one plugin is required' },
  { argv = { '--verbose' }, message = 'at least one plugin is required' },
  { argv = { '--data', 'Data Files' }, message = 'at least one plugin is required' },
  { argv = { '--' }, message = 'at least one plugin is required' },
  { argv = { 'Mod.esp', '--bogus' }, message = 'unknown option \'--bogus\'' },
  { argv = { 'Mod.esp', '--Verbose' }, message = 'unknown option \'--Verbose\'' },
  { argv = { 'Mod.esp', '--bogus=1' }, message = 'unknown option \'--bogus=1\'' },
  { argv = { 'Mod.esp', '-x' }, message = 'unknown option \'-x\'' },
  { argv = { 'Mod.esp', '-vx' }, message = 'unknown option \'-vx\'' },
  { argv = { 'Mod.esp', '--config', 'openmw.cfg' }, message = 'unknown option \'--config\'' },
  { argv = { 'Mod.esp', '--no-nifs' }, message = 'unknown option \'--no-nifs\'' },
  { argv = { 'Mod.esp', '--show' }, message = '--show requires a severity, or files' },
  { argv = { 'Mod.esp', '--show', '--verbose' }, message = '--show requires a severity, or files' },
  { argv = { 'Mod.esp', '--data' }, message = '--data requires a path' },
  { argv = { '--data', '--no-meshes', 'Mod.esp' }, message = '--data requires a path' },
  { argv = { 'Mod.esp', '--encoding' }, message = '--encoding requires an encoding' },
  { argv = { 'Mod.esp', '--format' }, message = '--format requires a format' },
  {
    argv = { 'Mod.esp', '--show', 'loud' },
    message = 'invalid value \'loud\' for --show: expected wont-load, broken, missing-asset, collision, performance, info, or files',
  },
  {
    argv = { 'Mod.esp', '--show=wontLoad' },
    message = 'invalid value \'wontLoad\' for --show: expected wont-load, broken, missing-asset, collision, performance, info, or files',
  },
  {
    argv = { 'Mod.esp', '--show=' },
    message = 'invalid value \'\' for --show: expected wont-load, broken, missing-asset, collision, performance, info, or files',
  },
  {
    argv = { 'Mod.esp', '--encoding', 'utf8' },
    message = 'invalid value \'utf8\' for --encoding: expected win1250, win1251, or win1252',
  },
  {
    argv = { 'Mod.esp', '--format', 'xml' },
    message = 'invalid value \'xml\' for --format: expected yaml, json, or toml',
  },
  { argv = { 'Mod.esp', '--show', 'info', '--show', 'files' }, message = '--show can only be given once' },
  { argv = { '--format=json', 'Mod.esp', '--format', 'json' }, message = '--format can only be given once' },
  {
    argv = { '--encoding=win1250', 'Mod.esp', '--encoding=win1251' },
    message = '--encoding can only be given once',
  },
  { argv = { 'Mod.esp', '-v', '--verbose' }, message = '--verbose can only be given once' },
  { argv = { 'Mod.esp', '-vv' }, message = '--verbose can only be given once' },
  { argv = { 'Mod.esp', '--no-meshes', '--no-meshes' }, message = '--no-meshes can only be given once' },
  { argv = { 'Mod.esp', '--verbose=true' }, message = '--verbose takes no value, not \'true\'' },
  { argv = { 'Mod.esp', '--no-meshes=1' }, message = '--no-meshes takes no value, not \'1\'' },
  { argv = { '--help=me' }, message = '--help takes no value, not \'me\'' },
  {
    argv = { '--version' },
    message = '--version isn\'t part of this command: it printed jess\'s version, which jess --version prints',
  },
  {
    argv = { 'Mod.esp', '-V' },
    message = '--version isn\'t part of this command: it printed jess\'s version, which jess --version prints',
  },
}

local function parsed(argv: { string }): cli.Command
  local command, message = cli.parse(argv)
  return command or error(message, 0)
end

suite.describe('parse', function()
  suite.it('reads plugins alone as a check down to collision that lists no references', function()
    expect(parsed { 'Mod.esp' }).toEqual {
      command = 'check',
      request = { plugins = { 'Mod.esp' }, show = 'collision', references = false },
      options = {},
    }

    expect(parsed { 'Data Files/A.esm', 'B.omwaddon' }).toEqual {
      command = 'check',
      request = { plugins = { 'Data Files/A.esm', 'B.omwaddon' }, show = 'collision', references = false },
      options = {},
    }
  end)

  suite.it('reads each --show value as the severity it names', function()
    local severities: { [string]: pluginAssets.Severity } = {
      ['wont-load'] = 'wontLoad',
      broken = 'broken',
      ['missing-asset'] = 'missingAsset',
      collision = 'collision',
      performance = 'performance',
      info = 'info',
    }

    for spelled, severity in severities do
      expect(parsed { '--show', spelled, 'Mod.esp' }).toEqual {
        command = 'check',
        request = { plugins = { 'Mod.esp' }, show = severity, references = false },
        options = {},
      }
    end
  end)

  suite.it('reads --show files as a whole check laid out as the file list', function()
    expect(parsed { 'Mod.esp', '--show=files' }).toEqual {
      command = 'check',
      request = { plugins = { 'Mod.esp' } },
      options = { files = true },
    }
  end)

  suite.it('reads --verbose into the request and the layout, and keeps the references', function()
    local verbose: cli.Command = {
      command = 'check',
      request = { plugins = { 'Mod.esp' }, show = 'collision', verbose = true },
      options = { verbose = true },
    }

    expect(parsed { '--verbose', 'Mod.esp' }).toEqual(verbose)
    expect(parsed { 'Mod.esp', '-v' }).toEqual(verbose)
    expect(parsed { '-v', '--show', 'files', 'Mod.esp' }).toEqual {
      command = 'check',
      request = { plugins = { 'Mod.esp' }, verbose = true },
      options = { files = true, verbose = true },
    }
  end)

  suite.it('reads every flag, attached or apart, on either side of the plugins', function()
    expect(parsed {
      '--data',
      'Data Files',
      'A.esp',
      '--no-meshes',
      '--data=Mods/OAAB/00 Core',
      '--encoding',
      'win1251',
      'B.esp',
      '--format=toml',
      '--show=broken',
      '--data',
      'Morrowind.bsa',
    }).toEqual {
      command = 'check',
      request = {
        plugins = { 'A.esp', 'B.esp' },
        data = { 'Data Files', 'Mods/OAAB/00 Core', 'Morrowind.bsa' },
        encoding = 'win1251',
        meshes = false,
        show = 'broken',
        references = false,
      },
      options = { format = 'toml' },
    }
  end)

  suite.it('takes everything after -- as a plugin, a lone dash as one, and an attached value as it is', function()
    expect(parsed { '--format', 'json', '--', '--verbose', '-v' }).toEqual {
      command = 'check',
      request = { plugins = { '--verbose', '-v' }, show = 'collision', references = false },
      options = { format = 'json' },
    }

    expect(parsed { '-', '--data=-odd', '--data', '-' }).toEqual {
      command = 'check',
      request = { plugins = { '-' }, data = { '-odd', '-' }, show = 'collision', references = false },
      options = {},
    }
  end)

  suite.it('reads help wherever it is asked for, before anything after it', function()
    expect(parsed { '--help' }).toEqual { command = 'help' }
    expect(parsed { '-h' }).toEqual { command = 'help' }
    expect(parsed { 'Mod.esp', '-vh', '--bogus' }).toEqual { command = 'help' }
    expect(parsed { '-hx' }).toEqual { command = 'help' }
    expect(parsed { '--show', 'info', '--help', '--show', 'loud' }).toEqual { command = 'help' }
  end)

  suite.it('refuses what it can\'t read, and says why', function()
    for _, case in Refused do
      local command, message = cli.parse(case.argv)
      expect({ argv = case.argv, command = command, message = message }).toEqual {
        argv = case.argv,
        message = case.message,
      }
    end
  end)
end)

local MissingBench: pluginAssets.Finding = {
  severity = 'missingAsset',
  code = 'missingMesh',
  message = 'model "bt\\balmora_bench.nif" not found at meshes/bt/balmora_bench.nif',
  plugin = 'BalmoraTweaks.esp',
  recordType = 'STAT',
  id = 'bt_balmora_bench',
  path = 'bt\\balmora_bench.nif',
}

--- The result behind the guide's first example (`guides/asset-checking.md` in jess's history):
--- six references, one file missing, named by two records.
local function tweaks(): commands.CheckResult
  return {
    command = 'check',
    plugins = { { name = 'BalmoraTweaks.esp', path = 'BalmoraTweaks.esp' } },
    sources = { '.' },
    report = {
      summary = {
        plugins = { 'BalmoraTweaks.esp' },
        unreadablePlugins = 0,
        references = 6,
        files = 5,
        missing = 1,
        meshesChecked = 2,
        meshesWontLoad = 0,
        byCode = { missingMesh = 2 },
        meshesByCode = {},
      },
      findings = { MissingBench, MissingBench },
      references = {},
      meshes = {},
      usedFiles = {},
    },
  }
end

local TweaksYaml = [[
summary:
  plugins:
  - BalmoraTweaks.esp
  unreadable_plugins: 0
  references: 6
  files: 5
  missing: 1
  meshes_checked: 2
  meshes_wont_load: 0
  by_code:
    missing_mesh: 2
  meshes_by_code: {}
findings:
- severity: missing_asset
  code: missing_mesh
  message: model "bt\balmora_bench.nif" not found at meshes/bt/balmora_bench.nif
  plugin: BalmoraTweaks.esp
  record_type: STAT
  id: bt_balmora_bench
  path: bt\balmora_bench.nif
- severity: missing_asset
  code: missing_mesh
  message: model "bt\balmora_bench.nif" not found at meshes/bt/balmora_bench.nif
  plugin: BalmoraTweaks.esp
  record_type: STAT
  id: bt_balmora_bench
  path: bt\balmora_bench.nif
]]

--- A result with one of everything a report can hold: a plugin that couldn't be read, a missing
--- file, a model with a finding and a texture that isn't there, a model with nothing to say and
--- nothing read of it, a reference that resolved into an archive and one that didn't resolve.
local function everything(): commands.CheckResult
  return {
    command = 'check',
    plugins = {
      { name = 'Junk.esp', path = 'mods/Junk.esp', problem = 'failed to read \'mods/Junk.esp\': truncated record header at offset 0' },
      { name = 'Mod.esp', path = 'mods/Mod.esp' },
    },
    sources = { 'Morrowind.bsa', 'mods' },
    report = {
      summary = {
        plugins = { 'Junk.esp', 'Mod.esp' },
        unreadablePlugins = 1,
        references = 3,
        files = 3,
        missing = 2,
        meshesChecked = 2,
        meshesWontLoad = 1,
        byCode = { unreadablePlugin = 1, missingMesh = 1, missingBigIcon = 1, doubledMeshesPrefix = 1 },
        meshesByCode = { wontLoad = 1, missingTexture = 1 },
      },
      findings = {
        {
          severity = 'wontLoad',
          code = 'unreadablePlugin',
          message = 'failed to read \'mods/Junk.esp\': truncated record header at offset 0',
          plugin = 'Junk.esp',
          recordType = '',
          id = '',
          path = '',
        },
        {
          severity = 'missingAsset',
          code = 'missingBigIcon',
          message = 'large icon for "s\\tx_s_fire.tga" not found (tried icons/s/b_tx_s_fire.dds)',
          plugin = 'Mod.esp',
          recordType = 'MGEF',
          id = 'FireDamage',
          path = 's\\tx_s_fire.tga',
        },
      },
      references = {
        {
          plugin = 'Mod.esp',
          recordType = 'NPC_',
          id = 'guard',
          kind = 'animatedMesh',
          path = 'base_anim.nif',
          resolved = 'meshes/base_anim.nif',
          source = 'Morrowind.bsa',
        },
        { plugin = 'Mod.esp', recordType = 'BOOK', id = 'bk_note', kind = 'bookArt', path = 'note.tga' },
      },
      meshes = {
        {
          path = 'meshes/base_anim.nif',
          source = 'Morrowind.bsa',
          version = '4.0.0.2',
          game = 'Morrowind',
          deeplyChecked = true,
          worst = 'missingAsset',
          findings = {
            { severity = 'missingAsset', code = 'missingTexture', message = 'texture "skin.tga" not found', record = 4 },
            { severity = 'info', code = 'manyShapes', message = '40 shapes' },
          },
          textures = {
            { path = 'skin.tga' },
            { path = 'eyes.tga', resolved = 'textures/eyes.dds', source = 'mods/textures/eyes.dds' },
          },
          stats = {
            records = 12,
            reachableRecords = 11,
            nodes = 3,
            shapes = 40,
            vertices = 900,
            triangles = 300,
            collisionTriangles = 0,
            controllers = 2,
            embeddedTextures = 0,
            embeddedTextureBytes = 0,
            skinned = true,
          },
          usedBy = { 'NPC_ guard', 'CREA rat' },
        },
        {
          path = 'meshes/x/odd.nif',
          source = 'mods/meshes/x/odd.nif',
          deeplyChecked = false,
          findings = {},
          textures = {},
          usedBy = {},
        },
      },
      usedFiles = {
        { file = '/games/Morrowind/Data Files/Morrowind.bsa', path = 'meshes/base_anim.nif', inArchive = true },
        { file = '/mods/My Mod/textures/eyes.dds', path = 'textures/eyes.dds', inArchive = false },
      },
    },
  }
end

local EverythingYaml = [[
summary:
  plugins:
  - Junk.esp
  - Mod.esp
  unreadable_plugins: 1
  references: 3
  files: 3
  missing: 2
  meshes_checked: 2
  meshes_wont_load: 1
  by_code:
    doubled_meshes_prefix: 1
    missing_big_icon: 1
    missing_mesh: 1
    unreadable_plugin: 1
  meshes_by_code:
    missing_texture: 1
    wont_load: 1
findings:
- severity: wont_load
  code: unreadable_plugin
  message: 'failed to read ''mods/Junk.esp'': truncated record header at offset 0'
  plugin: Junk.esp
  record_type: ''
  id: ''
  path: ''
- severity: missing_asset
  code: missing_big_icon
  message: large icon for "s\tx_s_fire.tga" not found (tried icons/s/b_tx_s_fire.dds)
  plugin: Mod.esp
  record_type: MGEF
  id: FireDamage
  path: s\tx_s_fire.tga
meshes:
- path: meshes/base_anim.nif
  source: Morrowind.bsa
  version: 4.0.0.2
  game: Morrowind
  deeply_checked: true
  worst: missing_asset
  findings:
  - severity: missing_asset
    code: missing_texture
    message: texture "skin.tga" not found
    record: 4
  - severity: info
    code: many_shapes
    message: 40 shapes
    record: null
  textures:
  - path: skin.tga
    resolved: null
    source: null
  - path: eyes.tga
    resolved: textures/eyes.dds
    source: mods/textures/eyes.dds
  stats:
    records: 12
    reachable_records: 11
    nodes: 3
    shapes: 40
    vertices: 900
    triangles: 300
    collision_triangles: 0
    controllers: 2
    embedded_textures: 0
    embedded_texture_bytes: 0
    skinned: true
  used_by:
  - NPC_ guard
  - CREA rat
- path: meshes/x/odd.nif
  source: mods/meshes/x/odd.nif
  version: null
  game: null
  deeply_checked: false
  worst: null
  findings: []
  textures: []
  stats: null
  used_by: []
]]

local EverythingVerboseTail = [[
references:
- plugin: Mod.esp
  record_type: NPC_
  id: guard
  kind: animated_mesh
  path: base_anim.nif
  resolved: meshes/base_anim.nif
  source: Morrowind.bsa
- plugin: Mod.esp
  record_type: BOOK
  id: bk_note
  kind: book_art
  path: note.tga
  resolved: null
  source: null
used_files:
- file: /games/Morrowind/Data Files/Morrowind.bsa
  path: meshes/base_anim.nif
  in_archive: true
- file: /mods/My Mod/textures/eyes.dds
  path: textures/eyes.dds
  in_archive: false
]]

local EverythingJson = '{"summary":{"plugins":["Junk.esp","Mod.esp"],"unreadable_plugins":1,"references":3,"files":3,'
  .. '"missing":2,"meshes_checked":2,"meshes_wont_load":1,"by_code":{"doubled_meshes_prefix":1,'
  .. '"missing_big_icon":1,"missing_mesh":1,"unreadable_plugin":1},"meshes_by_code":{"missing_texture":1,'
  .. '"wont_load":1}},"findings":[{"severity":"wont_load","code":"unreadable_plugin","message":"failed to read'
  .. ' \'mods/Junk.esp\': truncated record header at offset 0","plugin":"Junk.esp","record_type":"","id":"",'
  .. '"path":""},{"severity":"missing_asset","code":"missing_big_icon","message":"large icon for'
  .. ' \\"s\\\\tx_s_fire.tga\\" not found (tried icons/s/b_tx_s_fire.dds)","plugin":"Mod.esp",'
  .. '"record_type":"MGEF","id":"FireDamage","path":"s\\\\tx_s_fire.tga"}],"meshes":[{"path":'
  .. '"meshes/base_anim.nif","source":"Morrowind.bsa","version":"4.0.0.2","game":"Morrowind",'
  .. '"deeply_checked":true,"worst":"missing_asset","findings":[{"severity":"missing_asset","code":'
  .. '"missing_texture","message":"texture \\"skin.tga\\" not found","record":4},{"severity":"info","code":'
  .. '"many_shapes","message":"40 shapes","record":null}],"textures":[{"path":"skin.tga","resolved":null,'
  .. '"source":null},{"path":"eyes.tga","resolved":"textures/eyes.dds","source":"mods/textures/eyes.dds"}],'
  .. '"stats":{"records":12,"reachable_records":11,"nodes":3,"shapes":40,"vertices":900,"triangles":300,'
  .. '"collision_triangles":0,"controllers":2,"embedded_textures":0,"embedded_texture_bytes":0,"skinned":true},'
  .. '"used_by":["NPC_ guard","CREA rat"]},{"path":"meshes/x/odd.nif","source":"mods/meshes/x/odd.nif",'
  .. '"version":null,"game":null,"deeply_checked":false,"worst":null,"findings":[],"textures":[],"stats":null,'
  .. '"used_by":[]}]}\n'

suite.describe('render', function()
  suite.it('writes the guide\'s example as jess printed it', function()
    expect(cli.render(tweaks(), {})).toBe(TweaksYaml)
    expect(cli.render(tweaks())).toBe(TweaksYaml)
    expect(cli.render(tweaks(), { format = 'yaml' })).toBe(TweaksYaml)
  end)

  suite.it('spells fields and codes in snake_case, codes in order, and what is absent as null', function()
    expect(cli.render(everything(), {})).toBe(EverythingYaml)
  end)

  suite.it('adds the references and the files used only when verbose', function()
    expect(cli.render(everything(), { verbose = true })).toBe(EverythingYaml .. EverythingVerboseTail)

    local empty = tweaks()
    expect(cli.render(empty, { verbose = true })).toBe(TweaksYaml .. 'references: []\nused_files: []\n')
  end)

  suite.it('writes the file list alone for --show files, whatever else is asked', function()
    local files = [[
used_files:
- file: /games/Morrowind/Data Files/Morrowind.bsa
  path: meshes/base_anim.nif
  in_archive: true
- file: /mods/My Mod/textures/eyes.dds
  path: textures/eyes.dds
  in_archive: false
]]

    expect(cli.render(everything(), { files = true })).toBe(files)
    expect(cli.render(everything(), { files = true, verbose = true })).toBe(files)
    expect(cli.render(tweaks(), { files = true })).toBe 'used_files: []\n'
    expect(cli.render(tweaks(), { files = true, format = 'json' })).toBe '{"used_files":[]}\n'
  end)

  suite.it('writes compact JSON on one line', function()
    expect(cli.render(everything(), { format = 'json' })).toBe(EverythingJson)
  end)

  suite.it('writes TOML with what is absent left out', function()
    local document = jess.toml.decode(cli.render(everything(), { format = 'toml', verbose = true }))
    local summary = document.summary :: { [string]: unknown }
    expect(summary.meshes_by_code).toEqual { missing_texture = 1, wont_load = 1 }
    expect(summary.unreadable_plugins).toBe(1)

    local meshes = document.meshes :: { { [string]: unknown } }
    expect(meshes[1].worst).toBe 'missing_asset'
    expect(meshes[1].findings).toEqual {
      { severity = 'missing_asset', code = 'missing_texture', message = 'texture "skin.tga" not found', record = 4 },
      { severity = 'info', code = 'many_shapes', message = '40 shapes' },
    }

    expect(meshes[2]).toEqual {
      path = 'meshes/x/odd.nif',
      source = 'mods/meshes/x/odd.nif',
      deeply_checked = false,
      findings = {},
      textures = {},
      used_by = {},
    }

    local references = document.references :: { { [string]: unknown } }
    expect(references[2]).toEqual {
      plugin = 'Mod.esp',
      record_type = 'BOOK',
      id = 'bk_note',
      kind = 'book_art',
      path = 'note.tga',
    }

    expect(document.used_files).toEqual {
      { file = '/games/Morrowind/Data Files/Morrowind.bsa', path = 'meshes/base_anim.nif', in_archive = true },
      { file = '/mods/My Mod/textures/eyes.dds', path = 'textures/eyes.dds', in_archive = false },
    }
  end)
end)

suite.describe('status and diagnostics', function()
  --- A result whose summary counts `unreadable` plugins, `missing` files, and `wontLoad` models.
  local function counting(unreadable: number, missing: number, wontLoad: number): commands.CheckResult
    local result = tweaks()
    local summary = result.report.summary
    summary.unreadablePlugins, summary.missing, summary.meshesWontLoad = unreadable, missing, wontLoad
    return result
  end

  suite.it('are 0 and nothing when nothing is missing and every model loads', function()
    local clean = counting(0, 0, 0)
    expect(cli.status(clean)).toBe(0)
    expect(cli.diagnostics(clean, {})).toBe ''

    -- Findings that aren't failures don't change the outcome.
    expect(#clean.report.findings).toBe(2)
  end)

  suite.it('are 1 and what failed for a missing file, an unreadable plugin, or a model that won\'t load', function()
    expect(cli.status(tweaks())).toBe(1)
    expect(cli.diagnostics(tweaks(), {})).toBe 'error: 1 referenced file is missing\n'
    expect(cli.diagnostics(tweaks())).toBe 'error: 1 referenced file is missing\n'

    expect(cli.status(counting(1, 0, 0))).toBe(1)
    expect(cli.diagnostics(counting(1, 0, 0), {})).toBe 'error: 1 plugin couldn\'t be read\n'
    expect(cli.status(counting(0, 0, 1))).toBe(1)
    expect(cli.diagnostics(counting(0, 0, 1), {})).toBe 'error: 1 model won\'t load\n'
    expect(cli.status(counting(2, 3, 4))).toBe(1)
    expect(cli.diagnostics(counting(2, 3, 4), { verbose = true })).toBe(
      'error: 2 plugins couldn\'t be read; 3 referenced files are missing; 4 models won\'t load\n'
    )
  end)

  suite.it('name each missing file and unreadable plugin beside the file list, which has no path for them', function()
    expect(cli.diagnostics(everything(), { files = true })).toBe(
      'Junk.esp: failed to read \'mods/Junk.esp\': truncated record header at offset 0\n'
        .. 'Mod.esp: large icon for "s\\tx_s_fire.tga" not found (tried icons/s/b_tx_s_fire.dds)\n'
        .. 'error: 1 plugin couldn\'t be read; 2 referenced files are missing; 1 model won\'t load\n'
    )

    expect(cli.diagnostics(everything(), {})).toBe(
      'error: 1 plugin couldn\'t be read; 2 referenced files are missing; 1 model won\'t load\n'
    )
  end)
end)

suite.describe('run', function()
  local built = fixture.build(jess.fs.join(scratch, 'plugin-assets-cli', 'harness'))

  --- What `run` prints for `argv`, read back as the harness read it: the parsed JSON document.
  local function printed(argv: { string }): { [string]: unknown }
    local command = parsed(argv)
    local result = commands.check(command.request :: commands.CheckRequest)
    return json.decode(cli.render(result, command.options)) :: { [string]: unknown }
  end

  suite.it('prints the usage and returns 0 for help', function()
    expect(cli.run { '--help' }).toBe(0)
    expect(cli.run { '-h' }).toBe(0)
  end)

  suite.it('returns 8 for a command line it can\'t use', function()
    for _, case in Refused do
      expect({ argv = case.argv, status = cli.run(case.argv) }).toEqual { argv = case.argv, status = 8 }
    end
  end)

  suite.it('returns 9 for a check that can\'t be made', function()
    expect(cli.run { jess.fs.join(built.root, 'Gone.esp') }).toBe(9)
    expect(cli.run { built.plugin, '--data', jess.fs.join(built.root, 'nowhere') }).toBe(9)
    expect(cli.run { built.plugin, '--data', jess.fs.join(built.root, 'meshes/rock.nif') }).toBe(9)
  end)

  suite.it('checks the harness\'s plugin as jess plugin assets did, flag for flag', function()
    -- The plugin's own folder has the models; the texture is missing without --data.
    expect(cli.run { '--format', 'json', built.plugin }).toBe(0)

    local report = printed { '--format', 'json', built.plugin }
    local summary = report.summary :: { [string]: unknown }
    expect(summary.plugins).toEqual { 'Jess.esp' }
    expect(summary.meshes_checked).toBe(2)
    expect(report.references).toBeNil()

    local meshes = report.meshes :: { { [string]: unknown } }
    expect(#meshes).toBe(1)
    expect(meshes[1].path).toBe 'meshes/textured.nif'

    local withData = { '--format', 'json', '--data', built.textures, built.plugin }
    expect(cli.run(withData)).toBe(0)
    expect(printed(withData).meshes).toBeNil()

    local noMeshes = printed { '--format', 'json', '--no-meshes', built.plugin }
    expect((noMeshes.summary :: { [string]: unknown }).meshes_checked).toBe(0)

    local verbose = printed { '--format', 'json', '--verbose', built.plugin }
    expect(#(verbose.references :: { unknown })).toBe(2)
    expect(#(verbose.used_files :: { unknown })).toBe(2)
    expect(cli.run { '--format=json', '-v', built.plugin }).toBe(0)

    local files = printed { '--format', 'json', '--show', 'files', built.plugin }
    local paths: { unknown } = {}
    for _, file in files.used_files :: { { [string]: unknown } } do
      table.insert(paths, file.path)
    end

    expect(paths).toContain 'meshes/rock.nif'
    expect(files.summary).toBeNil()
    expect(cli.run { '--format', 'json', '--show', 'files', built.plugin }).toBe(0)
  end)

  suite.it('returns 1 once a model the plugin names isn\'t anywhere', function()
    local removed = fixture.build(jess.fs.join(scratch, 'plugin-assets-cli', 'harness-missing'))
    jess.fs.remove(jess.fs.join(removed.root, 'meshes/rock.nif'))

    local argv = { '--format', 'json', '--no-meshes', removed.plugin }
    expect(cli.run(argv)).toBe(1)
    expect((printed(argv).summary :: { [string]: unknown }).missing).toBe(1)

    local command = parsed(argv)
    local result = commands.check(command.request :: commands.CheckRequest)
    expect(cli.diagnostics(result, command.options)).toBe 'error: 1 referenced file is missing\n'
    expect(cli.status(result)).toBe(1)
    expect(cli.run { '--show', 'files', removed.plugin }).toBe(1)
  end)

  suite.it('returns 1 for a plugin that can\'t be read, and for a model that won\'t load', function()
    local root = jess.fs.join(scratch, 'plugin-assets-cli', 'failures')
    jess.fs.write(jess.fs.join(root, 'Junk.esp'), 'junk')
    jess.fs.write(jess.fs.join(root, 'meshes/broken.nif'), fixture.broken())
    jess.fs.write(
      jess.fs.join(root, 'Broken.esp'),
      fixture.plugin { fixture.static('broken', 'broken.nif') }
    )

    expect(cli.run { '--format', 'json', '--show', 'wont-load', jess.fs.join(root, 'Junk.esp') }).toBe(1)
    expect(cli.run { '--format', 'json', '--show', 'wont-load', jess.fs.join(root, 'Broken.esp') }).toBe(1)

    -- A model that won't load isn't looked at with --no-meshes, so nothing fails.
    expect(cli.run { '--format', 'json', '--no-meshes', jess.fs.join(root, 'Broken.esp') }).toBe(0)
  end)
end)

return suite
