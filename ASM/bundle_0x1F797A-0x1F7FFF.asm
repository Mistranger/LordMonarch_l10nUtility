	rorg 0x1F797A
	nolist


; Fix for intermission level name transformation effect
sym_uploadTransformedImage	        include "bundle_0x1F797A/uploadTransformedImage.asm"
sym_runPostBattleSaveNameTransform	include "bundle_0x1F797A/runPostBattleSaveNameTransform.asm"
; LZSA2 unpacker (https://github.com/tattlemuss/lz4-m68k) 
sym_lzsaunpack                      include "bundle_0x1F797A/lzsaunpack.asm"
; Fix menu options offsets
sym_helpmenu                        include "bundle_0x1F797A/op_e_helpmenu.asm"
; Fix garble tiles on cutscene changes
sym_resetCutsceneTiles              include "bundle_0x1F797A/resetCutsceneTiles.asm"
sym_resetCacheTile                  include "bundle_0x1F797A/resetCacheTile.asm"

