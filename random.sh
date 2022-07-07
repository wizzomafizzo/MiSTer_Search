#!/usr/bin/env python

import os
import sys
import random
import zipfile

# TODO: check recents file for entries
# TODO: select specific systems
# TODO: select meta categories
# TODO: look into index database option

ROLL_LIMIT = 100
CMD_INTERFACE = "/dev/MiSTer_cmd"
MGL_PATH = "/tmp/randomizer.mgl"

# (<games folder name>, <relative rbf location>, (<set of file extensions>, <delay>, <type>, <index>)[])
MGL_MAP = (
    ("ATARI2600", "_Console/Atari7800", (({".a78", ".a26", ".bin"}, 1, "f", 1),)),
    ("ATARI7800", "_Console/Atari7800", (({".a78", ".a26", ".bin"}, 1, "f", 1),)),
    ("AtariLynx", "_Console/AtariLynx", (({".lnx"}, 1, "f", 0),)),
    ("C64", "_Computer/C64", (({".prg", ".crt", ".reu", ".tap"}, 1, "f", 1),)),
    (
        "Coleco",
        "_Console/ColecoVision",
        (({".col", ".bin", ".rom", ".sg"}, 1, "f", 0),),
    ),
    ("GAMEBOY", "_Console/Gameboy", (({".gb", ".gbc"}, 1, "f", 1),)),
    ("GAMEBOY2P", "_Console/Gameboy2P", (({".gb", ".gbc"}, 1, "f", 1),)),
    ("GBA", "_Console/GBA", (({".gba"}, 1, "f", 0),)),
    ("GBA2P", "_Console/GBA2P", (({".gba"}, 1, "f", 0),)),
    ("Genesis", "_Console/Genesis", (({".bin", ".gen", ".md"}, 1, "f", 0),)),
    ("MegaCD", "_Console/MegaCD", (({".cue", ".chd"}, 1, "s", 0),)),
    (
        "NeoGeo",
        "_Console/NeoGeo",
        (({".neo", ".zip"}, 1, "f", 1), ({".iso", ".bin"}, 1, "s", 1)),
    ),
    ("NES", "_Console/NES", (({".nes", ".fds", ".nsf"}, 1, "f", 0),)),
    ("PSX", "_Console/PSX", (({".cue", ".chd"}, 1, "s", 1),)),
    ("S32X", "_Console/S32X", (({".32x"}, 1, "f", 0),)),
    ("SMS", "_Console/SMS", (({".sms", ".sg"}, 1, "f", 1), ({".gg"}, 1, "f", 2))),
    ("SNES", "_Console/SNES", (({".sfc", ".smc"}, 2, "f", 0),)),
    (
        "TGFX16",
        "_Console/TurboGrafx16",
        (
            ({".pce", ".bin"}, 1, "f", 0),
            ({".sgx"}, 1, "f", 1),
        ),
    ),
    (
        "TGFX16-CD",
        "_Console/TurboGrafx16",
        (({".cue", ".chd"}, 1, "s", 0),),
    ),
    ("VECTREX", "_Console/Vectrex", (({".ovr", ".vec", ".bin", ".rom"}, 1, "f", 1),)),
    ("WonderSwan", "_Console/WonderSwan", (({".wsc", ".ws"}, 1, "f", 1),)),
    ("_Arcade", "", (({".mra"}, 0, "", 0),)),
)

GAMES_FOLDERS = (
    "/media/fat",
    "/media/usb0",
    "/media/usb1",
    "/media/usb2",
    "/media/usb3",
    "/media/usb4",
    "/media/usb5",
    "/media/fat/cifs",
)


def random_item(list):
    return list[random.randint(0, len(list) - 1)]


def match_system_file(system, filename):
    name, ext = os.path.splitext(filename)
    for type in system[2]:
        if ext.lower() in type[0]:
            return type


def type_has_zip(system):
    for type in system[2]:
        if ".zip" in type[0]:
            return True
    return False


def get_system(name: str):
    for system in MGL_MAP:
        if name.lower() == system[0].lower():
            return system


def generate_mgl(rbf, delay, type, index, path):
    mgl = '<mistergamedescription>\n\t<rbf>{}</rbf>\n\t<file delay="{}" type="{}" index="{}" path="../../../..{}"/>\n</mistergamedescription>'
    return mgl.format(rbf, delay, type, index, path)


def to_mgl_args(system, match, full_path):
    return (
        system[1],
        match[1],
        match[2],
        match[3],
        full_path,
    )


def create_mgl_file(system_name, path):
    system = get_system(system_name)
    with open(MGL_PATH, "w") as f:
        mgl = generate_mgl(*to_mgl_args(system, match_system_file(system, path), path))
        f.write(mgl)


# {<system name> -> <full games path>[]}
def get_system_paths():
    systems = {}

    def add_system(name, folder):
        path = os.path.join(folder, name)
        if name in systems:
            systems[name].append(path)
        else:
            systems[name] = [path]

    def find_folders(path):
        if not os.path.exists(path) or not os.path.isdir(path):
            return False

        for folder in os.listdir(path):
            system = get_system(folder)
            if os.path.isdir(os.path.join(path, folder)) and system:
                add_system(system[0], path)

        return True

    for games_path in GAMES_FOLDERS:
        parent = find_folders(games_path)
        if not parent:
            break

        for subpath in os.listdir(games_path):
            if subpath.lower() == "games":
                find_folders(os.path.join(games_path, subpath))

    return systems


def is_valid_file(system, filename, recurse=True):
    is_dir = os.path.isdir(filename) or os.path.sep in filename
    is_match = match_system_file(system, filename) is not None
    is_zip = filename.lower().endswith(".zip")
    return (recurse and is_dir) or is_match or (recurse and is_zip)


def random_file(system_name, path):
    system = get_system(system_name)
    files = [x for x in os.listdir(path) if is_valid_file(system, x)]
    if len(files) == 0:
        return

    file = os.path.join(path, random_item(files))
    if os.path.isdir(file):
        # directory
        return random_file(file)
    elif (
        file.lower().endswith(".zip")
        and not type_has_zip(system)
        and zipfile.is_zipfile(file)
    ):
        # zip file
        zip = zipfile.ZipFile(file)
        files = [x for x in zip.namelist() if is_valid_file(system, x, False)]
        if len(files) == 0:
            return
        file = os.path.join(file, random_item(files))
        return file
    else:
        # game file
        return file


def get_random_game(rolls=0):
    if rolls >= ROLL_LIMIT:
        return

    systems = get_system_paths()
    system_name = random_item(list(systems.keys()))
    system_path = random_item(systems[system_name])

    file = random_file(system_name, system_path)
    if not file:
        return get_random_game(rolls + 1)
    else:
        return system_name, file


def launch_game(system_name, path):
    if system_name == "_Arcade":
        launch_path = path
    else:
        create_mgl_file(system_name, path)
        launch_path = MGL_PATH

    # os.system(f'echo "load_core {launch_path}" > {CMD_INTERFACE}')
    sys.exit(0)


if __name__ == "__main__":
    print("Searching for a game...")
    game = get_random_game()
    if game:
        print(f"Launching: [{game[0]}] {game[1]}")
        launch_game(*game)
