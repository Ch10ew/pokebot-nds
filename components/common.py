import io
import time
import mmap
import json
import traceback
from pokemon import enrich_mon_data

def load_json_mmap(size, file): 
    # BizHawk writes game information to memory mapped files every few frames (see pokebot.lua)
    # See https://tasvideos.org/Bizhawk/LuaFunctions (comm.mmfWrite)
    shmem = mmap.mmap(0, size, file)
    bytes_io = io.BytesIO(shmem)
    byte_str = bytes_io.read().decode('utf-8').split("\x00")[0]

    try:
        if byte_str != "":
            return json.loads(byte_str)
    except Exception as e:
        traceback.print_exc()
        print(byte_str)
        return False

def mem_get_game_info():
    global trainer_info, game_info, opponent_info, emu_speed

    while True:
        try:
            game_info_mmap = load_json_mmap(4096, "bizhawk_game_info")
            
            if game_info_mmap:
                trainer_info =  game_info_mmap["trainer"]
                game_info =     game_info_mmap["game_state"]
                emu_speed =     max(1, game_info_mmap["emu_fps"] / 60.0)

                if "opponent" in game_info_mmap:
                    if opponent_info is None or len(opponent_info) != len(game_info_mmap["opponent"]):
                        opponent_info = [None] * len(game_info_mmap["opponent"])
                    
                    for i, foe in enumerate(game_info_mmap["opponent"]):
                        if opponent_info[i] is None or foe["checksum"] != opponent_info[i]["checksum"]:
                            opponent_info[i] = enrich_mon_data(foe)
                else:
                    opponent_info = None

            time.sleep(0.08)
        except Exception as e:
            traceback.print_exc()
            pass

def mem_get_party_info():
    global party_info

    while True:
        try:
            party_info_mmap = load_json_mmap(8192, "bizhawk_party_info")

            if party_info_mmap:
                # Initialize updated party info
                new_party = [None] * party_info_mmap["party_count"]
                party_updated = len(new_party) != len(party_info)

                for i, mon in enumerate(party_info_mmap["party"]):
                    mon_oob = i >= len(party_info) or party_info[i] is None

                    if mon_oob or mon["checksum"] != party_info[i]["checksum"]:
                        # If mon didn't exist before, or was updated, enrich the new data
                        new_party[i] = enrich_mon_data(mon)
                        party_updated = True
                    elif not mon_oob:
                        # Otherwise reuse already enriched data
                        new_party[i] = party_info[i]

                if party_updated:
                    party_info = new_party
            time.sleep(0.08)
        except Exception as e:
            traceback.print_exc()
            pass

trainer_info, game_info, opponent_info, emu_speed, party_info = None, None, None, 1, []