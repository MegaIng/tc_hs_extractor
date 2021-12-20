import std/re
import std/os

import strformat
import strutils

import argparse

import tc_hs_extractorpkg/save_monger

type
  sol_file* = object
    name*: string
    custom_components*: seq[(uint64, seq[uint8])]
    programs*: seq[(uint32, seq[int64])]
    circuit*: seq[uint8]

  assembly* = object
    file_name*: string
    program_name_field*: string
    content*: seq[int64]
    permanent_id*: uint32


proc get_seq_u8*(input: seq[uint8], i: var int): seq[uint8] =
  let len = input.get_u16(i).int
  for _ in 1..len:
    result.add(input.get_u8(i))

proc get_seq_short_i64*(input: seq[uint8], i: var int): seq[int64] =
  let len = input.get_u16(i).int
  for j in 1..len:
    result.add(get_int(input, i).int64)

proc split_sol_file*(data: seq[uint8]): sol_file =
  var i = 0
  let custom_component_count = data.get_u16(i).int

  for _ in 1..custom_component_count:
    let cc_id = data.get_u64(i)
    let cc_data = data.get_seq_u8(i)
    result.custom_components.add((cc_id, cc_data))

  let program_count = data.get_u16(i).int
  for _ in 1..program_count:
    result.programs.add((data.get_u32(i), data.get_seq_short_i64(i)))

  result.circuit = data[i..^1]

proc map_program_names*(sol: var sol_file, edit_programs: bool=true): seq[assembly] =
  var circuit = parse_state(sol.circuit)
  for i, (pid, data) in sol.programs:
    for j, component in circuit.components:
      if pid == component.permanent_id:
        result.add assembly(file_name: &"assembly_{i}.assembly",
                            program_name_field: component.program_name,
                            content: data,
                            permanent_id: pid)
        if edit_programs:
          circuit.components[j].program_name = &"assembly_{i}.assembly"
        break
    if result.len != i+1:
      echo "Couldn't find Program component with id ", pid
  if edit_programs:
    sol.circuit = state_to_binary(
          circuit.save_version,
          circuit.components,
          circuit.circuits,
          circuit.nand,
          circuit.delay,
          circuit.menu_visible,
          circuit.clock_speed,
          circuit.nesting_level,
          circuit.description
    )

proc build_assembly*(a: assembly, max_line_width=80): string =
  result.add(&"# {a.file_name}, pid:{a.permanent_id}\n")
  if a.program_name_field.len != 0:
    for line in a.program_name_field.split_lines:
      result.add(&"# {line}\n")
  var current_length = 0
  for value in a.content:
    let s = $value
    if current_length == 0:
      current_length += s.len
      result.add(s)
    elif current_length + 1 + s.len > max_line_width:
      result.add('\n')
      result.add(s)
      current_length = s.len
    else:
      result.add(' ')
      result.add(s)
      current_length += 1 + s.len

proc get_schematic_path*(): string =
  when hostOS == "windows":
    let appdata = get_env("AppData")
    result = fmt"{appdata}\godot\app_userdata\Turing Complete\schematics"
  elif hostOS == "macosx":
    result = expand_tilde(r"~/Library/Application Support/Godot/app_userdata/Turing Complete/schematics")
  else:
    result = expand_tilde(r"~/.local/share/godot/app_userdata/Turing Complete/schematics")

proc write_files_architecture*(sol: sol_file, base_path: string, mapped_programs: seq[assembly], level_name: string, save_name: string, dry_run: bool=false) =
  proc `/`(parent: string, child: string): string = fmt"{parent}{DirSep}{child}"

  let architecture = base_path / "architecture" / "from_high_score" / save_name
  if not dry_run:
    create_dir(architecture)

  let circuit_path = architecture / "circuit.data"

  echo fmt"Writing main circuit to {circuit_path}"
  if not dry_run:
    circuit_path.write_file(sol.circuit)

  let assembly_folder = architecture / level_name
  if not dry_run:
    create_dir(assembly_folder)

  for a in mapped_programs:
    let assembly_path = assembly_folder / a.file_name
    echo fmt"Writing assembly file to {assembly_path}"
    if not dry_run:
      assembly_path.write_file(build_assembly(a))

  let cc_base = base_path / "component_factory" / "from_high_score" / save_name

  for (i, data) in sol.custom_components:
    let cc_folder = cc_base / fmt"{i}"
    if not dry_run:
      create_dir(cc_folder)
    let cc_path = cc_folder / "circuit.data"
    echo fmt"Writing Custom Component to {cc_path}"
    if not dry_run:
      cc_path.write_file(data)



proc write_files*(sol: sol_file, base_path: string, level_name: string, save_name: string, dry_run: bool=false) =
  proc `/`(parent: string, child: string): string = fmt"{parent}{DirSep}{child}"

  if sol.custom_components.len != 0:
    raise new_exception(ValueError, "Expected no Custom Components in non-architecture levels")
  if sol.programs.len != 0:
    raise new_exception(ValueError, "Expected no Assembly files in non-architecture levels")

  let save_folder = base_path / level_name / "from_high_score" / save_name

  if not dry_run:
    create_dir(save_folder)

  let circuit_path = save_folder / "circuit.data"
  echo fmt"Writing main circuit to {circuit_path}"

  if not dry_run:
    circuit_path.write_file(sol.circuit)



proc guess_level*(file_name: string): string =
  var matches: array[1, string]
  if file_name.match(re"^\d+_(\w+).sol$", matches):
    return matches[0]
  elif file_name.match(re"^(\w+).hs$", matches):
    return matches[0]
  else:
    echo &"Unkown file name format: {file_name.repr}"
    return file_name.split(".", 1)[0]


proc guess_name*(file_name: string): string =
  return file_name.split(".", 1)[0]


const known_architecures* = [
    "registers",
    "computing_codes",
    "program",
    "constants",
    "turing_complete",
    "binary_programming",
    "circumference",
    "mod_4",
    "binary_search",
    "spacial_invasion",
    "maze",
    "compute_xor",
    "leg_1",
    "leg_2",
    "leg_3",
    "leg_4",
    "sandbox",
    "ram",
    "shift",
    "divide",
    "unseen_fruit",
    "test_lab",
    "capitalize",
    "sorter",
    "push_pop",
    "call_ret",
    "dance",
    "tower",
    "robot_racing",
    "ai_showdown",
    "flood_predictor"
]

proc guess_architecture*(level: string): bool =
  if level in known_architecures:
    return true
  else:
    return false

when isMainModule:
  var p = new_parser:
    flag("-a", "--architecture", help="This is a solution for an architecture. Guesses based on level otherwise")
    flag("-d", "--dry-run", help="Don't actually write any files")
    option("-l", "--level", help="The level for which this solution is (guesses based on name otherwise)")
    option("-n", "--save-name", help="The name to use for the save folder (guesses based on name otherwise)")
    option("-s", "--schematics", help="The schematics folder. If not provided uses game default path")
    arg("sol_file", help="The .sol/.hs file to extract")

    run:
      if opts.level == "":
        opts.level = guess_level(opts.sol_file.extract_filename())
      if opts.save_name == "":
        opts.save_name = guess_name(opts.sol_file.extract_filename())
      if opts.schematics == "":
        opts.schematics = get_schematic_path()
      if not opts.architecture:
        opts.architecture = guess_architecture(opts.level)

      let data: seq[uint8] = cast[seq[uint8]](read_file(opts.sol_file))
      var sol = split_sol_file(data)
      sol.name = opts.save_name

      if opts.architecture:
        let mapped_programs = map_program_names(sol)
        write_files_architecture(sol, opts.schematics, mapped_programs, opts.level, opts.save_name, opts.dry_run)
      else:
        echo sol.repr
        write_files(sol, opts.schematics, opts.level, opts.save_name, opts.dry_run)
  p.run()

