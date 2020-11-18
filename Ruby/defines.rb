# Required modules

require "csv"
require "pp"
require 'open3'
require 'fileutils'

# Paths to data and tools

module Const
  ROM_Size = 0x200000
  ROM_MinAddr = 0x0
  ROM_MaxAddr = ROM_Size - 1

  # ROM Addresses
  Resources_Offset = 0x040800
  Resources_Count = 529
  Resources_End = 0x11D400
  Resources_Font8x8 = 0x54000

  # Tutorial pointers
  Data_TutFlowStart = 0x1e677c
  Data_TutTimingsStart = 0x1e6552

  # Static strings area
  Strings_RelStart = 0x022C84 # pointed by relative pointers
  Strings_DirStart = 0x1EDAFD # pointed by direct pointers

  LineWidth_InBattle = 208
end

module Paths
  MAIN_PATH = File.expand_path(__dir__ + "/..")
  TEMP_PATH = File.expand_path(__dir__ + "/../Temp")
  ASM_PATH = File.expand_path(__dir__ + "/../ASM")
  GFX_PATH = File.expand_path(__dir__ + "/../GFX")
  RES_EXTRACT_PATH = File.expand_path(__dir__ + "/../Temp/resextract")

  ORIGINAL_ROM = MAIN_PATH + "/ROM_Original/Lord Monarch - Tokoton Sentou Densetsu (Japan).md"
  PATCHED_ROM = MAIN_PATH + "/ROM_Patched/Lord Monarch - Tokoton Sentou Densetsu (WIP).md"

  VDA = MAIN_PATH + "/Tools/vda68k.exe"
  VASM = MAIN_PATH + "/Tools/vasmm68k_mot_win32.exe"
  LZSA_EXE = MAIN_PATH + "/Tools/lzsa.exe"

  EXPORT_TBL = MAIN_PATH + "/TBLs/export.tbl"
  EXPORT_8X16_TBL = MAIN_PATH + "/TBLs/export8x16.tbl"
  IMPORT_TBL = MAIN_PATH + "/TBLs/import.tbl"
  NAME_TBL = MAIN_PATH + "/TBLs/names.tbl"

  PTRS_CSV = MAIN_PATH + "/Data/ptrs2.csv"
  OPCODES_CSV = MAIN_PATH + "/Data/opcodes.csv"
  FREESPACE_CSV = MAIN_PATH + "/Data/free_space.csv"
  ASM_CSV = MAIN_PATH + "/Data/asm.csv"
  ASM_LINKS_CSV = MAIN_PATH + "/Data/asm_links.csv"
  GFX_REPLACE_CSV = MAIN_PATH + "/Data/gfxreplace.csv"
  PATCHBIN_CSV = MAIN_PATH + "/Data/patchbin.csv"
  TUTORIAL_CSV = MAIN_PATH + "/Data/tutorial.csv"
  PTRS_8X16_CSV = MAIN_PATH + "/Data/ptrs8x16.csv"

  TRANSLATION_TEMPLATE_DB = MAIN_PATH + "/Translations/template.db"
  TRANSLATION_EN_US_DB = MAIN_PATH + "/Translations/en_US.db"

  DATA_FONT3 = MAIN_PATH + "/GFX/font3_8x16.png"
  DATA_FONT_TRIO2 = MAIN_PATH + "/GFX/TrioDX2tiled.png"
  DATA_FONT_TRIO = MAIN_PATH + "/GFX/TrioDXtiled.png"
  DATA_FONT16 = MAIN_PATH + "/GFX/font16_16x16.png"

  # for debug purposes
  EXPORT_DB = TEMP_PATH + "/textExport.db"
end


