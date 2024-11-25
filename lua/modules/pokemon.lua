-----------------------------------------------------------------------------
-- Pure Lua handler for emulator Pokemon data
-- Author: wyanido
-- Homepage: https://github.com/wyanido/pokebot-nds
--
-- Responsible for reading, parsing, and handling general logic
-- that uses Pokemon data for other bot modes.
-----------------------------------------------------------------------------
local pokemon = {}

--- Verifies the checksum of Pokemon data in memory
local function verify_checksums(data, checksum)
    local sum = 0

    for i = 0x09, 0x88, 2 do
        sum = sum + data[i] + bit.lshift(data[i + 1], 8)
    end

    sum = bit.band(sum, 0xFFFF)

    return sum == checksum and sum ~= 0
end

--- Creates a surface-level copy of a lua table without nested elements 
local function shallow_copy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

--- Returns a decrypted byte table of Pokemon data from memory
function pokemon.read_data(address, is_raw)
    local function rand(seed) -- Thanks Kaphotics
        return (0x4e6d * (seed % 65536) + ((0x41c6 * (seed % 65536) + 0x4e6d * math.floor(seed / 65536)) % 65536) * 65536 + 0x6073) % 4294967296
    end

    local function decrypt_block(start, finish)
        local data = {}

        for i = start, finish, 0x2 do
            local word = mword(address + i)
            
            -- Decrypt bytes if the data isn't already unencrypted (only applies to Platinum statics)
            if not is_raw then
                seed = rand(seed)

                local rs = bit.rshift(seed, 16)
                word = bit.bxor(word, rs)
                word = bit.band(word, 0xFFFF)
            end

            table.insert(data, bit.band(word, 0xFF))
            table.insert(data, bit.band(bit.rshift(word, 8), 0xFF))
        end

        return data
    end

    local function append_bytes(source)
        table.move(source, 1, #source, #data + 1, data)
    end

    local substruct = {
        [0] = {1, 2, 3, 4},
        [1] = {1, 2, 4, 3},
        [2] = {1, 3, 2, 4},
        [3] = {1, 4, 2, 3},
        [4] = {1, 3, 4, 2},
        [5] = {1, 4, 3, 2},
        [6] = {2, 1, 3, 4},
        [7] = {2, 1, 4, 3},
        [8] = {3, 1, 2, 4},
        [9] = {4, 1, 2, 3},
        [10] = {3, 1, 4, 2},
        [11] = {4, 1, 3, 2},
        [12] = {2, 3, 1, 4},
        [13] = {2, 4, 1, 3},
        [14] = {3, 2, 1, 4},
        [15] = {4, 2, 1, 3},
        [16] = {3, 4, 1, 2},
        [17] = {4, 3, 1, 2},
        [18] = {2, 3, 4, 1},
        [19] = {2, 4, 3, 1},
        [20] = {3, 2, 4, 1},
        [21] = {4, 2, 3, 1},
        [22] = {3, 4, 2, 1},
        [23] = {4, 3, 2, 1}
    }

    data = {}
    append_bytes({mbyte(address), mbyte(address + 1), mbyte(address + 2), mbyte(address + 3)}) -- PID
    append_bytes({0x0, 0x0}) -- Unused Bytes
    append_bytes({mbyte(address + 6), mbyte(address + 7)}) -- Checksum

    -- Unencrypted bytes
    local pid = mdword(address)
    local checksum = mword(address + 0x06)

    -- Find intended order of the shuffled data blocks
    local shift = bit.rshift(bit.band(pid, 0x3E000), 0xD) % 24
    local block_order = substruct[shift]

    -- Decrypt blocks A,B,C,D and rearrange according to the order
    seed = checksum

    local _block = {}
    for index = 1, 4 do
        local block = (index - 1) * 0x20
        _block[index] = decrypt_block(0x08 + block, 0x27 + block)
    end

    for _, index in ipairs(block_order) do
        append_bytes(_block[index])
    end

    -- Re-calculate checksum of the data blocks and match it with mon.checksum
    -- If there is no match, assume the Pokemon data is garbage or still being written
    if not verify_checksums(data, checksum) then
        return nil
    end

    -- Party-only status data
    seed = pid
    append_bytes(decrypt_block(0x88, 0xDB))

    if _ROM.gen == 4 then
        -- Write blank ball seal data
        for i = 0x1, 0x10 do
            table.insert(data, 0x0)
        end
    end

    return data
end

--- Parses raw Pokemon data from bytes into a human-readable table
-- All properties are included here, but ones that aren't relevant to any
-- bot modes have been commented out to keep the data simple. Customise if needed.
function pokemon.parse_data(data, enrich)
    local function read_real(start, length)
        local bytes = 0
        local j = 0

        for i = start + 1, start + length do
            bytes = bytes + bit.lshift(data[i], j * 8)
            j = j + 1
        end

        return bytes
    end

    if data == nil then
        print_warn("Tried to parse data of a non-existent Pokemon!")
        return nil
    end

    mon = {}
    mon.pid = read_real(0x00, 0x4)
    mon.checksum = read_real(0x06, 0x02)

    -- Block A
    mon.species = read_real(0x08, 2)
    mon.heldItem = read_real(0x0A, 2)
    mon.otID = read_real(0x0C, 2)
    mon.otSID = read_real(0x0E, 2)
    mon.experience = read_real(0x10, 3)
    mon.friendship = read_real(0x14, 1)
    mon.ability = read_real(0x15, 1)
    -- mon.markings         = read_real(0x16, 1)
    mon.otLanguage = read_real(0x17, 1)
    mon.hpEV = read_real(0x18, 1)
    mon.attackEV = read_real(0x19, 1)
    mon.defenseEV = read_real(0x1A, 1)
    mon.speedEV = read_real(0x1B, 1)
    mon.spAttackEV = read_real(0x1C, 1)
    mon.spDefenseEV = read_real(0x1D, 1)
    -- mon.cool 			 = read_real(0x1E, 1)
    -- mon.beauty 			 = read_real(0x1F, 1)
    -- mon.cute 			 = read_real(0x20, 1)
    -- mon.smart 			 = read_real(0x21, 1)
    -- mon.tough 			 = read_real(0x22, 1)
    -- mon.sheen 			 = read_real(0x23, 1)
    -- mon.sinnohRibbonSet1 = read_real(0x24, 2)
    -- mon.unovaRibbonSet 	 = read_real(0x26, 2)

    local tid = mon.otID
    local sid = mon.otSID

    if config.ot_override then
        tid = tonumber(config.tid_override)
        sid = tonumber(config.sid_override)
    end

    mon.shinyValue = bit.bxor(bit.bxor(bit.bxor(tid, sid), (bit.band(bit.rshift(mon.pid, 16), 0xFFFF))), bit.band(mon.pid, 0xFFFF))
    mon.shiny = mon.shinyValue < 8

    -- Block B
    mon.moves = {read_real(0x28, 2), read_real(0x2A, 2), read_real(0x2C, 2), read_real(0x2E, 2)}
    mon.pp = {read_real(0x30, 1), read_real(0x31, 1), read_real(0x32, 1), read_real(0x33, 1)}
    -- mon.ppUps = read_real(0x34, 4)

    local value = read_real(0x38, 5)
    mon.hpIV = bit.band(value, 0x1F)
    mon.attackIV = bit.band(bit.rshift(value, 5), 0x1F)
    mon.defenseIV = bit.band(bit.rshift(value, 10), 0x1F)
    mon.speedIV = bit.band(bit.rshift(value, 15), 0x1F)
    mon.spAttackIV = bit.band(bit.rshift(value, 20), 0x1F)
    mon.spDefenseIV = bit.band(bit.rshift(value, 25), 0x1F)
    mon.isEgg = bit.band(bit.rshift(value, 30), 0x01) == 1
    -- mon.isNicknamed = bit.band(bit.rshift(value, 31), 0x01)

    -- mon.hoennRibbonSet1		= read_real(0x3C, 2)
    -- mon.hoennRibbonSet2		= read_real(0x3E, 2)

    local value = read_real(0x40, 1)
    -- mon.fatefulEncounter = bit.band(bit.rshift(value, 0), 0x01)
    mon.gender = bit.band(bit.rshift(value, 1), 0x03)
    mon.altForm = bit.band(bit.rshift(value, 3), 0x1F)

    if _ROM.gen == 4 then
        -- mon.leaf_crown = read_real(0x41, 1)
        mon.nature = mon.pid % 25
    else
        mon.nature = read_real(0x41, 1)

        -- local value = read_real(0x42, 1)
        -- mon.dreamWorldAbility = bit.band(value, 0x01)
        -- mon.isNsPokemon		  = bit.band(value, 0x01)
    end

    -- Block C
    mon.nickname = read_string(data, 0x48)
    -- mon.originGame		 = read_real(0x5F, 1)
    -- mon.sinnohRibbonSet3 = read_real(0x60, 2)
    -- mon.sinnohRibbonSet3 = read_real(0x62, 2)

    -- Block D
    -- mon.otName          = read_string(data, 0x68)
    -- mon.dateEggReceived	= read_real(0x78, 3)
    -- mon.dateMet			= read_real(0x7B, 3)
    -- mon.eggLocation		= read_real(0x7E, 2)
    -- mon.metLocation		= read_real(0x80, 2)
    mon.pokerus = read_real(0x82, 1)
    mon.pokeball = read_real(0x83, 1)
    -- mon.encounterType	= read_real(0x85, 1)

    -- Battle Stats
    -- mon.status       = read_real(0x88, 1)
    mon.level = read_real(0x8C, 1)
    -- mon.capsuleIndex = read_real(0x8D, 1)
    mon.currentHP = read_real(0x8E, 2)
    mon.maxHP = read_real(0x90, 2)
    mon.attack = read_real(0x92, 2)
    mon.defense = read_real(0x94, 2)
    mon.speed = read_real(0x96, 2)
    mon.spAttack = read_real(0x98, 2)
    mon.spDefense = read_real(0x9A, 2)
    -- mon.mailMessage	 = read_real(0x9C, 37)

    -- Substitute property IDs with ingame names
    if enrich then
        mon.pid = string.format("%08X", mon.pid)
        mon.name = _DEX[mon.species + 1][1]
        mon.type = _DEX[mon.species + 1][2]

        -- mon.rating = pokemon.get_rating(mon)
        mon.pokeball = _ITEM[mon.pokeball + 1]
        mon.otLanguage = _LANGUAGE[mon.otLanguage + 1]
        mon.ability = _ABILITY[mon.ability + 1]
        mon.nature = _NATURE[mon.nature + 1]
        mon.heldItem = _ITEM[mon.heldItem + 1]
        mon.gender = _GENDER[mon.gender + 1]

        local move_id = mon.moves
        mon.moves = {}

        for _, move in ipairs(move_id) do
            table.insert(mon.moves, _MOVE[move + 1])
        end

        mon.ivSum = mon.hpIV + mon.attackIV + mon.defenseIV + mon.spAttackIV + mon.spDefenseIV + mon.speedIV

        local hpTypeList = {"fighting", "flying", "poison", "ground", "rock", "bug", "ghost", "steel", "fire", "water",
                            "grass", "electric", "psychic", "ice", "dragon", "dark"}
        local lsb = (mon.hpIV % 2) + (mon.attackIV % 2) * 2 + (mon.defenseIV % 2) * 4 + (mon.speedIV % 2) * 8 +
                        (mon.spAttackIV % 2) * 16 + (mon.spDefenseIV % 2) * 32
        local slsb = bit.rshift((bit.band(mon.hpIV, 2)), 1) + bit.rshift(bit.band(mon.attackIV, 2), 1) * 2 +
                         bit.rshift(bit.band(mon.defenseIV, 2), 1) * 4 + bit.rshift(bit.band(mon.speedIV, 2), 1) * 8 +
                         bit.rshift(bit.band(mon.spAttackIV, 2), 1) * 16 + bit.rshift(bit.band(mon.spDefenseIV, 2), 1) *
                         32

        mon.hpType = hpTypeList[math.floor((lsb * 15) / 63) + 1]
        mon.hpPower = math.floor((slsb * 40) / 63) + 30

        -- Keep a reference of the original data, necessary for exporting pkx
        mon.raw = data
    end

    return mon
end

--- Sends a Pokemon to the dashboard to log it as an encounter
function pokemon.log_encounter(mon)
    if not mon then
        print_warn("Tried to log a non-existent Pokemon!")
        return false
    end

    -- Create a watered down copy of the Pokemon data for logging only
    local mon_new = shallow_copy(mon)

    local key_whitelist = {"pid", "species", "name", "level", "gender", "nature", "heldItem", "hpIV", "attackIV",
                           "defenseIV", "spAttackIV", "spDefenseIV", "speedIV", "shiny", "shinyValue", "ability",
                           "altForm", "ivSum", "hpType", "hpPower", "isEgg"}

    for k, v in pairs(mon_new) do
        local allowed = false

        for _, k2 in ipairs(key_whitelist) do
            if k2 == k then
                allowed = true
                break
            end
        end

        if not allowed then
            mon_new[k] = nil
        end
    end

    -- Send encounter to dashboard for logging
    local is_target = pokemon.matches_ruleset(mon, config.target_traits)
    local msg_type = is_target and "seen_target" or "seen"

    if is_target then
        print(mon.name .. " is a target!")

        if config.save_pkx then
            local shiny = mon.shiny and " ★" or ""
            local hex_string = string.format("%04X", mon.checksum) .. mon.pid
            local filename =
                string.format("%04d", mon.species) .. shiny .. " - " .. mon.nickname .. " - " .. hex_string .. ".pk" ..
                    _ROM.gen

            dashboard_send({
                type = "save_pkx",
                data = mon.raw,
                filename = filename
            })
        end
    end

    dashboard_send({
        type = msg_type,
        data = mon_new
    })

    return is_target
end

--- Returns the index of the most suitable move for KO-ing the target
function pokemon.find_best_attacking_move(ally, foe)
    local max_power_index = 1
    local max_power = 0

    for i, move in ipairs(ally.moves) do
        local power = move.power

        -- Don't waste Thief PP when trying to farm items
        if config.thief_wild_items and move.name == "Thief" then
            power = nil
        end

        -- Only check damaging moves with PP remaining
        if ally.pp[i] ~= 0 and power ~= nil then
            local type_matchup = _TYPE[move.type]

            -- Calculate effectiveness against foe's type(s)
            for j = 1, #foe.type do
                local foe_type = foe.type[j]

                if table_contains(type_matchup.cant_hit, foe_type) then
                    power = 0
                    break
                elseif table_contains(type_matchup.resisted_by, foe_type) then
                    power = power / 2
                elseif table_contains(type_matchup.super_effective, foe_type) then
                    power = power * 2
                end
            end

            -- Apply STAB
            for j = 1, #ally.type do
                if ally.type[j] == move.type then
                    power = power * 1.5
                    break
                end
            end

            -- Average power by accuracy (favours more accurate moves)
            if move.accuracy then
                power = power * (move.accuracy / 100.0)
            end

            if power > max_power then
                max_power = power
                max_power_index = i
            end
        end

        i = i + 1
    end

    return {
        name = ally.moves[max_power_index].name,
        index = max_power_index,
        power = max_power
    }
end

--- Returns whether a Pokemon has traits desired by a specified user ruleset
function pokemon.matches_ruleset(mon, ruleset)
    if not ruleset then
        print_warn("Can't check Pokemon against an empty ruleset")
        return false
    end

    -- Other traits don't matter with this override
    if config.always_catch_shinies and mon.shiny then
        return true
    end

    -- This function intentionally doesn't do an early exit
    -- so it can print a warning when a meaningless value 
    -- is written into target traits
    local is_target = true

    -- Check items from ruleset against values from the Pokemon's data,
    -- dynamically changing for different data types
    for property, rule in pairs(ruleset) do
        local value = mon[property]

        if value ~= nil then
            if type(rule) == "boolean" then
                -- Simple boolean check
                if value ~= rule then
                    print_debug(property .. "? is not " .. tostring(rule))
                    is_target = false
                end
            elseif type(rule) == "table" then
                if type(value) == "table" then
                    -- Check every mon table entry against every rule entry
                    -- to ensure it contains at least one entry
                    local has_entry = false

                    for _, entry in pairs(rule) do
                        if table_contains(value, entry) then
                            has_entry = true
                            break
                        end
                    end

                    if not has_entry then
                        print_debug(property .. " does not contain any entries from ruleset")
                        is_target = false
                    end
                else
                    -- Check value against every rule table entry
                    if not table_contains(rule, value) then
                        print_debug(value .. " is not in " .. property .. " ruleset")
                        is_target = false
                    end
                end
            else
                if type(value) == "string" then
                    -- Case-insensitive string comparison
                    if string.lower(value) ~= string.lower(rule) then
                        print_debug(property .. " " .. value .. " does not match " .. rule)
                        is_target = false
                    end
                else
                    -- Numerical threshold check
                    if value < rule then
                        print_debug(property .. " " .. value .. " does not meet threshold " .. rule)
                        is_target = false
                    end
                end
            end
        else
            print_warn("Unknown field " .. property .. " in ruleset")
        end
    end

    return is_target
end

--- Returns the index of a given move within a Pokemon's moveset
function pokemon.get_move_slot(mon, move_name)
    for i, v in ipairs(mon.moves) do
        if v.name == move_name and mon.pp[i] > 0 then
            return i
        end
    end
    return 0
end

--- Returns whether a Pokemon is both newly hatched and not a target
function pokemon.is_hatched_dud(mon)
    return mon.level == 1 and not pokemon.matches_ruleset(mon, config.target_traits)
end

return pokemon
