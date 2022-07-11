#!/usr/bin/env python

import os
import zipfile
import subprocess
import tarfile
import tempfile
import sys
import random
import math
from io import BytesIO


DB_PATH = "/media/fat/search.db"
CMD_INTERFACE = "/dev/MiSTer_cmd"
MGL_PATH = "/tmp/search_launcher.mgl"

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
    ("GAMEBOY2P", "_Console/Gameboy2P", (({".gb", ".gbc"}, 1, "f", 1),)),
    ("GAMEBOY", "_Console/Gameboy", (({".gb", ".gbc"}, 1, "f", 1),)),
    ("GBA2P", "_Console/GBA2P", (({".gba"}, 1, "f", 0),)),
    ("GBA", "_Console/GBA", (({".gba"}, 1, "f", 0),)),
    ("Genesis", "_Console/Genesis", (({".bin", ".gen", ".md"}, 1, "f", 0),)),
    ("MegaCD", "_Console/MegaCD", (({".cue", ".chd"}, 1, "s", 0),)),
    (
        "NeoGeo",
        "_Console/NeoGeo",
        (({".neo"}, 1, "f", 1), ({".iso", ".bin"}, 1, "s", 1)),
    ),
    ("NES", "_Console/NES", (({".nes", ".fds", ".nsf"}, 1, "f", 0),)),
    ("PSX", "_Console/PSX", (({".cue", ".chd"}, 1, "s", 1),)),
    ("S32X", "_Console/S32X", (({".32x"}, 1, "f", 0),)),
    ("SMS", "_Console/SMS", (({".sms", ".sg"}, 1, "f", 1), ({".gg"}, 1, "f", 2))),
    ("SNES", "_Console/SNES", (({".sfc", ".smc"}, 2, "f", 0),)),
    (
        "TGFX16-CD",
        "_Console/TurboGrafx16",
        (({".cue", ".chd"}, 1, "s", 0),),
    ),
    (
        "TGFX16",
        "_Console/TurboGrafx16",
        (
            ({".pce", ".bin"}, 1, "f", 0),
            ({".sgx"}, 1, "f", 1),
        ),
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


def get_system(name: str):
    for system in MGL_MAP:
        if name.lower() == system[0].lower():
            return system


def match_system_file(system, filename):
    _, ext = os.path.splitext(filename)
    for type in system[2]:
        if ext.lower() in type[0]:
            return type


def random_item(list):
    return list[random.randint(0, len(list) - 1)]


def get_system(name: str):
    for system in MGL_MAP:
        if name.lower() == system[0].lower():
            return system


def generate_mgl(rbf, delay, type, index, path):
    mgl = '<mistergamedescription>\n\t<rbf>{}</rbf>\n\t<file delay="{}" type="{}" index="{}" path="../../../..{}"/>\n</mistergamedescription>\n'
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
    with open(MGL_PATH, "w") as mgl:
        mgl.write(
            generate_mgl(*to_mgl_args(system, match_system_file(system, path), path))
        )
    return mgl


# {<system name>: <full games path>[]}
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


# return a generator for all valid system roms
# (<full path>, <system>, <name>)
def get_system_files(name, folder):
    system = get_system(name)

    for root, _, files in os.walk(folder):
        for filename in files:
            path = os.path.join(root, filename)

            if filename.lower().endswith(".zip") and zipfile.is_zipfile(path):
                # zip files
                for zip_path in zipfile.ZipFile(path).namelist():
                    match = match_system_file(system, zip_path)
                    if match:
                        full_path = os.path.join(path, zip_path)
                        game_name, ext = os.path.splitext(os.path.basename(zip_path))
                        yield (full_path, game_name)

            else:
                # regular files
                match = match_system_file(system, filename)
                if match is not None:
                    game_name, ext = os.path.splitext(filename)
                    yield (path, game_name)


# create new index db file, yields at progress points
def generate_db():
    system_paths = get_system_paths()
    count_index = ""

    paths_total = 0
    for paths in system_paths.values():
        paths_total += len(paths)

    tar = tarfile.open(DB_PATH, "w:")

    def add(name, s: str):
        info = tarfile.TarInfo(name)
        info.size = len(s)
        tar.addfile(info, BytesIO(s.encode("utf-8")))

    for system in sorted(system_paths.keys()):
        path_index = ""
        name_index = ""
        count = 0

        for system_path in system_paths[system]:
            yield system, system_path, paths_total

            for file_path, name in get_system_files(system, system_path):
                path_index += file_path + "\n"
                name_index += name + "\n"
                count += 1

        add(system + "__path", path_index)
        add(system + "__name", name_index)
        count_index += f"{system}\t{count}\n"

    add("_count", count_index)
    tar.close()

def get_db():
    return tarfile.open(DB_PATH, "r:")


def search_name(db: tarfile.TarFile, query: str):
    results = []
    query_words = query.split()

    if len(query_words) == 0:
        return []

    for index_name in db.getnames():
        if not index_name.endswith("__name"):
            continue

        system_name = index_name[:-6]

        name_file = tempfile.NamedTemporaryFile()
        index = db.extractfile(index_name).read()
        name_file.write(index)

        grep = subprocess.run(
            ["grep", "-in", query_words[0], name_file.name],
            text=True,
            capture_output=True,
        )
        grep_output = grep.stdout.splitlines()

        if len(query_words) > 1:
            for word in query_words[1:]:
                grep_output = [
                    x for x in grep_output if word.casefold() in x.casefold()
                ]

        grep_results = []
        for line in grep_output:
            lineno, name = line.split(":", 1)
            grep_results.append((int(lineno), name))

        name_file.close()

        if len(grep_results) > 0:
            path_index = (
                db.extractfile(system_name + "__path")
                .read()
                .decode("utf-8")
                .splitlines()
            )

            for lineno, name in grep_results:
                results.append((system_name, path_index[lineno - 1], name))

    return results


def launch_game(system_name, path):
    if system_name == "_Arcade":
        launch_path = path
    else:
        mgl = create_mgl_file(system_name, path)
        launch_path = mgl.name

    os.system(f'echo "load_core {launch_path}" > {CMD_INTERFACE}')
    sys.exit(0)


def dialog_env():
    return dict(os.environ, DIALOGRC="/media/fat/Scripts/.dialogrc")


def display_search_input(query=""):
    args = [
        "dialog",
        "--title",
        "Search",
        "--ok-label",
        "Search",
        "--cancel-label",
        "Exit",
        # "--extra-button",
        # "--extra-label",
        # "Advanced",
        "--inputbox",
        "",
        "7",
        "75",
        query,
    ]

    result = subprocess.run(args, stderr=subprocess.PIPE, env=dialog_env())

    button = result.returncode
    query = result.stderr.decode()

    if button == 0:
        display_search_results(query)


def display_message(msg, info=False, height=5, title="Search"):
    if info:
        type = "--infobox"
    else:
        type = "--msgbox"

    args = [
        "dialog",
        "--title",
        title,
        "--ok-label",
        "Ok",
        type,
        msg,
        str(height),
        "75",
    ]

    subprocess.run(args, env=dialog_env())


def display_search_results(query):
    # TODO: random button
    display_message(f"Searching for: {query}", info=True, height=3)

    db = get_db()
    search = search_name(db, query)

    if len(search) == 0:
        display_message("No results found.")
        display_search_input(query)
        return

    names = set()
    filtered_search = []

    for r in search:
        if r[2] in names:
            continue
        names.add(r[2])
        filtered_search.append(r)

    filtered_search.sort(key=lambda x: x[2].lower())

    args = [
        "dialog",
        "--title",
        "Search",
        "--ok-label",
        "Launch",
        "--cancel-label",
        "Cancel",
        "--menu",
        f"Found {len(filtered_search)} results. Select game to launch:",
        "20",
        "75",
        "20",
    ]

    for i, v in enumerate(filtered_search, start=1):
        names.add(v[2])
        args.append(str(i))
        args.append(f"{v[2]} [{v[0]}]")

    result = subprocess.run(args, stderr=subprocess.PIPE, env=dialog_env())

    index = str(result.stderr.decode())
    button = result.returncode

    if button == 0:
        selected = filtered_search[int(index) - 1]
        launch_game(selected[0], selected[1])
    else:
        display_search_input()


def display_generate_db():
    display_message(
        "This script will now create an index of all your games. This only happens once, but it can 1-2 minutes for a large collection.",
        height=6,
        title="Creating Index",
    )

    def display_progress(msg, pct):
        args = [
            "dialog",
            "--title",
            "Creating Index...",
            "--gauge",
            msg,
            "6",
            "75",
            str(pct),
        ]
        progress = subprocess.Popen(args, env=dialog_env(), stdin=subprocess.PIPE)
        progress.communicate("".encode())

    for i, v in enumerate(generate_db()):
        pct = math.ceil(i / v[2] * 100)
        display_progress(f"Scanning {v[0]} ({v[1]})", pct)

    display_message(
        f"Index generated successfully. Found {get_count()} games.",
        title="Indexing Complete",
    )


def get_count(system=None):
    db = get_db()
    counts = db.extractfile("_count").read().decode("utf-8").splitlines()

    if system is None:
        total = 0
        for system in counts:
            _, count = system.split("\t", 1)
            total += int(count)
        return total


if __name__ == "__main__":
    if not os.path.exists(DB_PATH):
        display_generate_db()
    display_search_input()