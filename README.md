Lord Monarch patching utility used for Nebulous Translations English translation release of Lord Monarch
(c) 2020 by cybermind, cybermindid@gmail.com

Directory structure:
ASM - 68000 assembly code
Data - helper CSV files used to mark pointers or other data in ROM
GFX - graphics and plane mappings
Ghidra - Ghidra reverse-engineered database of Lord Monarch (with lots of stuff marked and identified)
ROM_Original - utility expects "Lord Monarch - Tokoton Sentou Densetsu (Japan).md" ROM file in this folder
ROM_Patched - utility places translated ROM file here
Ruby - utility source code
TBLs - character translation tables
Temp - temporary data folder
Tools - 68000 compiler and LZSA2 (de)compressor
Translations - SQLite3 translation databases (template file included)

Helper CSV files info:
asm.csv
	Defines memory blocks in ROM space that are vacant for ASM patches
asm_links.csv
	Defines hooks from ASM patches to original code (r - using JSRs, d - using JMPs)
	The utility parses "vasm" log file to determine real addresses of assembled code in ROM and then uses this information to create hooks in code.
free_space.csv
	ROM vacant space map. length field is just for reference. The file structure is used by memory allocator in utility to store translated scripts.
gfxreplace.csv
	Data that needs to be replaced using in-game resource manager. The resource index is located at 0x040800 in ROM.
opcodes.csv
	Opcodes used in dialogue scripts.
patchbin.csv
	Files that are directly included into ROM at specified addresses.
ptrs2.csv
	Script pointer references. The main file used by utility.
ptrs8x16.csv
	Pointers to text that use 8x16 font to draw (hints, menu labels)
tutorial.csv
	Tutorial demo replay file (used to fix demo sync)

Usage:
1. Place original ROM file in ROM_Original directory.
2. Install Ruby interpreter and "sqlite3" gem.
3. Run patch.rb.
4. If successful, the translated ROM file will be found in ROM_Patched directory.

Hints:
To translate the game to your favorite language, modify en_US.db (or create new one desired language) using SQLite3 database editor (I prefer DB Browser). In case you need extra characters, modify character tables in TBLs directory and fonts in GFX folder. Refer to Ghidra database for internals of game structure.