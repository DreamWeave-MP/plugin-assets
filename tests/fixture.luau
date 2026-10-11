--!strict
--!native
-- The inputs `jess plugin assets`' harness checked (`plugin_assets_check_references_meshes_and_
-- data_folders` in jess's history, `libs/cli/tests/nif.rs`), built the way it built them: a data
-- folder with a good model, a model whose only root is pixel data, and a model that draws with a
-- texture; a second folder that has that texture; and beside the models a plugin, written byte
-- by byte as the harness wrote it, whose two statics use the good model and the textured one.
local fs = require '@dream/fs'
local nif = require '@nif'

local Corner = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
local Triangle = { { 0, 0, 0 }, { 1, 0, 0 }, { 0, 1, 0 } }

--- A triangle shape named `Tri Rock` under a node named `Rock`.
local function rock(): buffer
  local file = nif.new()
  local root = file:insert { type = 'NiNode', name = 'Rock' }
  file.roots = { root }
  file:shape { name = 'Tri Rock', parent = root, vertices = Corner, triangles = { { 0, 1, 2 } } }
  return file:save()
end

--- A model OpenMW won't load: its only root is pixel data.
local function broken(): buffer
  local file = nif.new()
  file.roots = { file:insert { type = 'NiPixelData' } }
  return file:save()
end

--- A shape under an unnamed node that draws with `texture`.
local function textured(texture: string): buffer
  local file = nif.new()
  local root = file:insert { type = 'NiNode' }
  file.roots = { root }
  file:shape { parent = root, vertices = Triangle, triangles = { { 0, 1, 2 } }, texture = texture }
  return file:save()
end

local function u32(value: number): string
  local bytes = buffer.create(4)
  buffer.writeu32(bytes, 0, value)
  return buffer.tostring(bytes)
end

local function f32(value: number): string
  local bytes = buffer.create(4)
  buffer.writef32(bytes, 0, value)
  return buffer.tostring(bytes)
end

local function fixed(value: string, width: number): string
  return value .. string.rep('\0', width - #value)
end

local function subrecord(tag: string, payload: string): string
  return tag .. u32(#payload) .. payload
end

local function record(tag: string, payload: string): string
  return tag .. u32(#payload) .. string.rep('\0', 8) .. payload
end

--- A version 1.3 header that counts `records` records.
local function header(records: number): string
  local hedr = f32(1.3) .. u32(0) .. fixed('test', 32) .. fixed('synthetic', 256) .. u32(records)
  return record('TES3', subrecord('HEDR', hedr))
end

local function static(id: string, mesh: string): string
  return record('STAT', subrecord('NAME', `{id}\0`) .. subrecord('MODL', `{mesh}\0`))
end

--- A plugin's bytes: a header and `records`, each a record's bytes.
local function plugin(records: { string }): string
  return header(#records) .. table.concat(records)
end

export type Built = {
  --- The data folder, with `meshes/rock.nif`, `meshes/broken.nif`, and `meshes/textured.nif`.
  root: string,
  --- `Jess.esp`, in the data folder.
  plugin: string,
  --- A folder with only `textures/tx_there.dds`, which the textured model draws with.
  textures: string,
}

--- Builds the harness's folders fresh under `folder`.
local function build(folder: string): Built
  if jess.fs.exists(folder) then fs.remove(folder, { recursive = true }) end

  local textures = jess.fs.join(folder, 'textures-only')
  local path = jess.fs.join(folder, 'Jess.esp')
  jess.fs.write(jess.fs.join(folder, 'meshes/rock.nif'), rock())
  jess.fs.write(jess.fs.join(folder, 'meshes/broken.nif'), broken())
  jess.fs.write(jess.fs.join(folder, 'meshes/textured.nif'), textured 'tx_there.tga')
  jess.fs.write(jess.fs.join(textures, 'textures/tx_there.dds'), 'DDS ')
  jess.fs.write(
    path,
    plugin { static('jess_rock', 'rock.nif'), static('jess_textured', 'textured.nif') }
  )

  return { root = folder, plugin = path, textures = textures }
end

return table.freeze {
  build = build,
  plugin = plugin,
  static = static,
  rock = rock,
  broken = broken,
  textured = textured,
}
