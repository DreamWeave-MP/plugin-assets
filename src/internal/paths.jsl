--!strict
--!native
-- SPDX-License-Identifier: MIT OR Apache-2.0

--[[
How OpenMW turns the paths records spell into VFS paths: the lookups of
`components/misc/resourcehelpers.cpp` that jess-assets' `paths` ported, beside the one for NIF
textures, which `@nif-assets` has (`texturePath`, and `resourcePath` under it).

Each lookup takes an `exists` callback, so the same rules work against any VFS.
]]

local nifAssets = require '@nif-assets'

export type Resolved = nifAssets.Resolved

--- Replaces the extension of the last component, if it has one (`Normalized::changeExtension`).
local function changeExtension(path: string, extension: string): string?
  local stem = string.match(path, '^(.*)%.[^./]*$')
  if not stem then return nil end

  return `{stem}.{extension}`
end

--- `correctIconPath`, for inventory icons.
local function iconPath(path: string, exists: (string) -> boolean): Resolved
  return nifAssets.resourcePath({ 'icons' }, path, 'dds', exists)
end

--- `correctBigIconPath`: the large icon of a magic effect is its icon's file name with a `b_`
--- prefix, in the same folder.
local function bigIconPath(path: string, exists: (string) -> boolean): Resolved
  local normalized = nifAssets.normalize(path)
  local folder, name = string.match(normalized, '^(.*/)([^/]*)$')
  if not folder then return iconPath(`b_{normalized}`, exists) end

  return iconPath(`{folder}b_{name}`, exists)
end

--- `correctBookartPath`, for book images.
local function bookartPath(path: string, exists: (string) -> boolean): Resolved
  return nifAssets.resourcePath({ 'bookart', 'textures' }, path, 'dds', exists)
end

--- `correctBookartPath` with an image's size: when the image isn't found, the same name with
--- `_<width>_<height>` before the extension is tried, since some books name it without.
local function sizedBookartPath(
  path: string,
  width: number,
  height: number,
  exists: (string) -> boolean
): Resolved
  local first = bookartPath(path, exists)
  if first.found then return first end

  local stem, extension = string.match(first.path, '^(.*)(%.[^.]*)$')
  local sized = if stem
    then string.format('%s_%d_%d%s', stem, width, height, extension)
    else string.format('%s_%d_%d', first.path, width, height)
  local second = bookartPath(sized, exists)
  local tried = first.tried
  for _, candidate in second.tried do
    if not table.find(tried, candidate) then table.insert(tried, candidate) end
  end

  second.tried = tried
  return second
end

--- `correctMeshPath`: record models are relative to `meshes`, with no search or fallback.
local function meshPath(path: string): string return `meshes/{nifAssets.normalize(path)}` end

--- `correctSoundPath`: sound records are relative to `sound`, and a missing file is replaced by
--- the same name as `.mp3`.
local function soundPath(path: string, exists: (string) -> boolean): Resolved
  local written = `sound/{nifAssets.normalize(path)}`
  if exists(written) then return { path = written, found = true, tried = { written } } end

  local mp3 = changeExtension(written, 'mp3') or written
  if mp3 == written then return { path = written, found = false, tried = { written } } end

  return { path = mp3, found = exists(mp3), tried = { written, mp3 } }
end

--- `correctActorModelPath`: an animated model `a/b.nif` uses `a/xb.nif` when `a/xb.kf` exists.
--- The model path, and whether an animation file was found for it.
local function actorModelPath(path: string, exists: (string) -> boolean): (string, boolean)
  local normalized = nifAssets.normalize(path)
  local folder, name = string.match(normalized, '^(.*/)([^/]*)$')
  local model = if folder then `{folder}x{name}` else `x{normalized}`
  local animation = if string.sub(model, -4) == '.nif' then string.sub(model, 1, -5) .. '.kf' else model
  if exists(animation) then return model, true end

  return normalized, false
end

--- A path used as written, normalized.
local function direct(path: string, exists: (string) -> boolean): Resolved
  local normalized = nifAssets.normalize(path)
  return { path = normalized, found = exists(normalized), tried = { normalized } }
end

return table.freeze {
  actorModelPath = actorModelPath,
  bigIconPath = bigIconPath,
  direct = direct,
  iconPath = iconPath,
  meshPath = meshPath,
  sizedBookartPath = sizedBookartPath,
  soundPath = soundPath,
}
