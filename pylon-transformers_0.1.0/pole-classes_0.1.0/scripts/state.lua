-- Everything saved in `storage` goes through here.
local S = {}

function S.init()
  storage.nbr = storage.nbr or {}             -- unit_number -> { neighbour unit_number -> true }
  storage.players = storage.players or {}     -- player_index -> per-player state
  storage.last_notify = storage.last_notify or {}
  storage.counts = storage.counts or { wire = 0, zone = 0 }
end

function S.player(player_index)
  local p = storage.players[player_index]
  if not p then
    p = {}
    storage.players[player_index] = p
  end
  return p
end

return S
